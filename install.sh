#!/usr/bin/env bash
# install.sh - install the self-learn extension into a Claude Code setup.
#
#   ./install.sh                     setup wizard (in a terminal, no flags): dependencies,
#                                    repo roots, which repos to study, routing hook, nightly
#                                    time, private remote, VS Code companions
#   ./install.sh [--workspace DIRS] [--schedule [HH:MM] | --no-schedule] [--store-remote URL]
#                [--hook | --no-hook] [--vscode LIST] [--plugin] [--wizard] [--yes] [--dry-run]
#
#   --workspace DIRS     root(s) holding your git repos, comma-separated (default ~/workspace).
#                        Discovered repos are registered in the private store; nothing is
#                        written into the projects themselves.
#   --schedule [HH:MM]   install the nightly job (launchd on macOS, systemd --user timer on
#                        Linux; prints a crontab line elsewhere). Default 03:07.
#   --no-schedule        do not (re)install the nightly job, and remember that.
#   --store-remote URL   point the private store at a PRIVATE git remote and push once.
#   --hook / --no-hook   install / skip the UserPromptSubmit routing hook (default: install).
#   --vscode LIST        VS Code companions: claude-launcher,graphify-watch | all | none.
#   --wizard             ask the questions even when flags or a saved config exist.
#   --yes                never ask: flags, then the saved config, then defaults.
#   --dry-run            print what would change, touch nothing.
#   --plugin             plugin install: skip what the plugin already delivers (skills, routing-hook
#                        registration); still do deps, config.json, store, discovery, scheduler, VS Code.
#
# Precedence on every run: flags > $SELF_LEARN_HOME/config.json > defaults. The effective
# answers are written back to config.json, so the next run - an upgrade, CI, another machine
# restoring the store - repeats them silently. A run with no flags outside a terminal never asks.
#
# Idempotent: re-running upgrades the skills/hook/lib in place, backs up anything it
# overwrites (<file>.bak-<stamp>), and never touches learned state (journal, cursors,
# learned-patterns.md, routing map) once it exists.
#
# Env overrides: CLAUDE_CONFIG_DIR (default ~/.claude), SELF_LEARN_HOME (default
# $CLAUDE_CONFIG_DIR/self-learn).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL_HOME="${SELF_LEARN_HOME:-$CLAUDE_DIR/self-learn}"
STAMP="$(date +%Y%m%d%H%M%S)"
LABEL="com.self-learn.nightly"
# Answers: empty = not given on the command line (filled from config.json, then defaults).
# shellcheck disable=SC2034  # the answer variables are consumed by the sourced wizard
DISABLED_REPOS=""; ROOTS_CSV=""; WITH_HOOK=""; SCHEDULE=""; SCHED_TIME=""; STORE_REMOTE=""
VSCODE_LAUNCHER=""; VSCODE_GRAPHIFY=""
WIZARD=0; ASSUME_YES=0; DRY=0; FLAGGED=0; PLUGIN_MODE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) ROOTS_CSV="$2"; FLAGGED=1; shift 2 ;;
    --schedule)
      SCHEDULE=1; FLAGGED=1; shift
      if [ $# -gt 0 ] && printf '%s' "$1" | grep -qE '^[0-9]{1,2}:[0-9]{2}$'; then SCHED_TIME="$1"; shift; fi ;;
    --no-schedule) SCHEDULE=0; FLAGGED=1; shift ;;
    --store-remote) STORE_REMOTE="$2"; FLAGGED=1; shift 2 ;;
    --hook) WITH_HOOK=1; FLAGGED=1; shift ;;
    --no-hook) WITH_HOOK=0; FLAGGED=1; shift ;;
    --vscode)
      FLAGGED=1; VSCODE_LAUNCHER=0; VSCODE_GRAPHIFY=0
      case ",$2," in *,all,*) VSCODE_LAUNCHER=1; VSCODE_GRAPHIFY=1 ;; esac
      case ",$2," in *,claude-launcher,*) VSCODE_LAUNCHER=1 ;; esac
      case ",$2," in *,graphify-watch,*) VSCODE_GRAPHIFY=1 ;; esac
      shift 2 ;;
    --plugin) PLUGIN_MODE=1; shift ;;
    --wizard) WIZARD=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | cut -c3-; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# Plugin mode: point rule 1 of sl_skill_dir at the plugin checkout this installer runs from.
if [ "$PLUGIN_MODE" -eq 1 ]; then export SELF_LEARN_SKILL_DIR="${SELF_LEARN_SKILL_DIR:-$SRC/skills/self-learn}"; fi

say()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
run()  { if [ "$DRY" -eq 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

. "$SRC/lib/install-deps.sh"
. "$SRC/lib/skill-dir.sh"
. "$SRC/lib/install-wizard.sh"
. "$SRC/lib/install-summary.sh"

# ---------- 0. answers: flags > saved config > wizard > defaults ----------
wizard_load_config
if [ "$WIZARD" -eq 1 ] || { [ "$FLAGGED" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; }; then
  wizard_run
else
  step "Checking dependencies"
  deps_report || { echo "install aborted: required tools missing (git, jq, python3)" >&2; exit 1; }
fi
wizard_defaults
IFS=, read -r -a ROOTS <<< "$ROOTS_CSV"
WORKSPACE="${ROOTS[0]}"
step "Configuration"
wizard_save_config

# ---------- helpers ----------
# Copy SRC file to DEST, backing DEST up first when it exists and differs.
put() {
  local from="$1" to="$2"
  if [ -f "$to" ] && cmp -s "$from" "$to"; then return 0; fi
  if [ -f "$to" ]; then
    say "update  $to  (backup: $(basename "$to").bak-$STAMP)"
    run cp "$to" "$to.bak-$STAMP"
  else
    say "install $to"
  fi
  run mkdir -p "$(dirname "$to")"
  run cp "$from" "$to"
}
# Copy only when DEST does not exist (user-owned state / seeds).
seed() {
  local from="$1" to="$2"
  if [ -e "$to" ]; then say "keep    $to"; return 0; fi
  say "seed    $to"
  run mkdir -p "$(dirname "$to")"
  run cp "$from" "$to"
}
# Substitute __TOKENS__ in a template into DEST.
render() {
  local from="$1" to="$2"
  local hour minute
  hour="${SCHED_TIME%%:*}"; minute="${SCHED_TIME##*:}"
  hour="$((10#$hour))"; minute="$((10#$minute))"
  say "render  $to"
  [ "$DRY" -eq 1 ] && return 0
  mkdir -p "$(dirname "$to")"
  sed -e "s|__LABEL__|$LABEL|g" -e "s|__SL_HOME__|$SL_HOME|g" -e "s|__HOME__|$HOME|g" \
      -e "s|__WORKSPACE__|$WORKSPACE|g" -e "s|__HOUR__|$hour|g" -e "s|__MINUTE__|$minute|g" \
      "$from" > "$to"
}

# ---------- 1. skills ----------
if [ "$PLUGIN_MODE" -eq 1 ]; then
  step "Skills"
  say "skip    delivered by the plugin"
else
  step "Installing skills into $CLAUDE_DIR/skills"
  for sk in "$SRC"/skills/*/; do
    name="$(basename "$sk")"
    if [ "$name" = setup ]; then continue; fi   # plugin-only: needs ${CLAUDE_PLUGIN_ROOT}
    dest="$CLAUDE_DIR/skills/$name"
    while IFS= read -r f; do
      rel="${f#"$sk"}"
      case "$rel" in
        references/learned-patterns*.md|journal/*) seed "$f" "$dest/$rel" ;;   # accumulated state
        *) put "$f" "$dest/$rel" ;;
      esac
    done < <(find "$sk" -type f | sort)
    [ "$DRY" -eq 1 ] || chmod +x "$dest"/scripts/*.sh 2>/dev/null || true
  done
fi

# ---------- 2. lib + guard settings ----------
step "Installing runtime pieces into $CLAUDE_DIR"
put  "$SRC/lib/claude-retry.sh"               "$CLAUDE_DIR/lib/claude-retry.sh"
put  "$SRC/lib/skill-dir.sh"                  "$CLAUDE_DIR/lib/skill-dir.sh"
seed "$SRC/templates/night-guard-settings.json" "$CLAUDE_DIR/night-guard-settings.json"

# ---------- 3. routing hook ----------
if [ "$PLUGIN_MODE" -eq 0 ] && [ "$WITH_HOOK" = 1 ]; then
  step "Installing the routing hook (UserPromptSubmit)"
  put "$SRC/hooks/skill-router.py" "$CLAUDE_DIR/hooks/skill-router.py"
  [ "$DRY" -eq 1 ] || chmod +x "$CLAUDE_DIR/hooks/skill-router.py"
  SETTINGS="$CLAUDE_DIR/settings.json"
  HOOK_CMD="python3 $CLAUDE_DIR/hooks/skill-router.py"
  if [ "$DRY" -eq 1 ]; then
    say "[dry-run] register '$HOOK_CMD' in $SETTINGS -> hooks.UserPromptSubmit"
  else
    mkdir -p "$CLAUDE_DIR"
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    if jq -e --arg c "$HOOK_CMD" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command==$c)] | length > 0' "$SETTINGS" >/dev/null 2>&1; then
      say "keep    hook already registered in $SETTINGS"
    else
      cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
      tmp="$(mktemp)"
      jq --arg c "$HOOK_CMD" '
        .hooks = (.hooks // {})
        | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{hooks:[{type:"command",command:$c}]}])
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      say "register hook in $SETTINGS  (backup: settings.json.bak-$STAMP)"
    fi
  fi
elif [ "$PLUGIN_MODE" -eq 1 ]; then
  step "Routing hook"
  say "skip    the plugin registers it itself (hooks/hooks.json)"
  if [ -f "$CLAUDE_DIR/settings.json" ] && jq -e \
    '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command|test("skill-router"))] | length > 0' \
    "$CLAUDE_DIR/settings.json" >/dev/null 2>&1; then
    say "WARN    a clone-install routing hook is still registered in settings.json - the plugin"
    say "WARN    registers its own; remove the old one with ./uninstall.sh or delete the entry"
  fi
fi

# ---------- skill dir: resolved after step 1, which is what creates it on a clone install ----------
if ! SKILL_DIR="$(sl_skill_dir)"; then
  if [ "$DRY" -eq 1 ]; then SKILL_DIR="$SRC/skills/self-learn"   # a dry run installed nothing to find
  else echo "cannot locate the self-learn skill directory" >&2; exit 1; fi
fi

# ---------- 4. private store ----------
step "Initializing the private store at $SL_HOME"
if [ "$DRY" -eq 0 ]; then
  SELF_LEARN_HOME="$SL_HOME" bash "$SKILL_DIR/scripts/state.sh" status >/dev/null
fi
put  "$SRC/templates/nightly-run.sh"     "$SL_HOME/scripts/nightly-run.sh"
[ "$DRY" -eq 1 ] || chmod +x "$SL_HOME/scripts/nightly-run.sh"
seed "$SRC/templates/nightly-prompt.txt" "$SL_HOME/nightly-prompt.txt"
seed "$SRC/templates/routing-map.json"   "$SL_HOME/routing/routing-map.json"
seed "$SRC/templates/intent-lexicon.md"  "$SL_HOME/routing/intent-lexicon.md"
if [ "$DRY" -eq 0 ]; then
  mkdir -p "$SL_HOME/logs"
  # pending/ is transient crash-safety state; logs/ are local noise - neither belongs in git.
  touch "$SL_HOME/.gitignore"
  for line in 'pending/' 'logs/'; do grep -qxF "$line" "$SL_HOME/.gitignore" || echo "$line" >> "$SL_HOME/.gitignore"; done
fi

# ---------- 5. discover repos ----------
step "Discovering git repos under ${ROOTS[*]}"
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || say "WARN $r does not exist - create it before the first run; the nightly job refuses to start without its workspace"
done
if [ "$DRY" -eq 1 ]; then say "[dry-run] discover.sh ${ROOTS[*]}"; else
  SELF_LEARN_HOME="$SL_HOME" bash "$SKILL_DIR/scripts/discover.sh" "${ROOTS[@]}" | sed 's/^/  /'
  apply_repo_toggles
fi

# ---------- 6. scheduler ----------
if [ "$SCHEDULE" = 1 ]; then
  step "Installing the nightly job at $SCHED_TIME local time"
  case "$(uname -s)" in
    Darwin)
      PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
      render "$SRC/templates/launchd.plist" "$PLIST"
      if [ "$DRY" -eq 0 ]; then
        launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"
        say "loaded  $LABEL  (check: launchctl list | grep self-learn)"
      fi ;;
    Linux)
      UNIT_DIR="$HOME/.config/systemd/user"
      render "$SRC/templates/systemd.service" "$UNIT_DIR/self-learn-nightly.service"
      render "$SRC/templates/systemd.timer"   "$UNIT_DIR/self-learn-nightly.timer"
      if [ "$DRY" -eq 0 ]; then
        if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null; then
          systemctl --user enable --now self-learn-nightly.timer
          say "enabled self-learn-nightly.timer  (check: systemctl --user list-timers)"
        else
          say "systemd --user unavailable; add this crontab line instead:"
          say "  ${SCHED_TIME##*:} ${SCHED_TIME%%:*} * * * SELF_LEARN_HOME=$SL_HOME SELF_LEARN_WORKSPACE=$WORKSPACE /bin/bash $SL_HOME/scripts/nightly-run.sh"
        fi
      fi ;;
    *)
      say "no scheduler integration for $(uname -s); add this crontab line:"
      say "  ${SCHED_TIME##*:} ${SCHED_TIME%%:*} * * * SELF_LEARN_HOME=$SL_HOME SELF_LEARN_WORKSPACE=$WORKSPACE /bin/bash $SL_HOME/scripts/nightly-run.sh" ;;
  esac
elif [ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ] || [ -f "$HOME/.config/systemd/user/self-learn-nightly.timer" ]; then
  step "Nightly job"
  say "a nightly job is still installed; remove it with ./uninstall.sh, or turn it back on with --schedule"
fi

# ---------- 7. store remote ----------
if [ -n "$STORE_REMOTE" ]; then
  step "Pointing the private store at $STORE_REMOTE"
  say "the store holds your project names, paths and distilled feedback - this remote must be PRIVATE"
  current="$(git -C "$SL_HOME" remote get-url origin 2>/dev/null || true)"
  if [ "$current" = "$STORE_REMOTE" ]; then say "keep    store already tracks $STORE_REMOTE"
  elif [ "$DRY" -eq 1 ]; then say "[dry-run] sync.sh init $STORE_REMOTE"
  else SELF_LEARN_HOME="$SL_HOME" bash "$SKILL_DIR/scripts/sync.sh" init "$STORE_REMOTE" | sed 's/^/  /'; fi
fi

# ---------- 8. VS Code companions ----------
if [ "$VSCODE_LAUNCHER" = 1 ] || [ "$VSCODE_GRAPHIFY" = 1 ]; then
  step "Installing VS Code companions"
  companions=()
  [ "$VSCODE_LAUNCHER" = 1 ] && companions+=(claude-launcher)
  [ "$VSCODE_GRAPHIFY" = 1 ] && companions+=(graphify-watch)
  if ! dep_present code; then
    say "WARN code CLI not found - skipped; in VS Code run 'Shell Command: Install code command in PATH', then re-run $0"
  elif [ "$DRY" -eq 1 ]; then say "[dry-run] vscode/install-vscode.sh ${companions[*]}"
  else bash "$SRC/vscode/install-vscode.sh" "${companions[@]}" | sed 's/^/  /'; fi
fi

# ---------- done ----------
install_summary
