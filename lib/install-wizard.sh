#!/usr/bin/env bash
# install-wizard.sh - the interactive first-run setup, sourced by install.sh.
#
# Seven steps: dependencies, repo roots, which repos to study, routing hook, nightly time,
# private remote, VS Code companions. Each explains itself in one line and Enter keeps the
# default. Answers persist in $SL_HOME/config.json so every later run (an upgrade, CI,
# another machine restoring the store) is silent; flags always win over saved answers.
#
# Caller contract (install.sh): SRC, SL_HOME, CLAUDE_DIR, DRY, say(), step() and the deps
# table (lib/install-deps.sh) exist; the answer variables ROOTS_CSV, WITH_HOOK, SCHEDULE,
# SCHED_TIME, STORE_REMOTE, DISABLED_REPOS, VSCODE_LAUNCHER, VSCODE_GRAPHIFY hold whatever
# the flags set (empty = not given) and are completed here - ALIASES included, which has no
# question of its own (default on when the caller leaves it unset; --no-aliases turns the short
# /kz-* commands off). Answers come from stdin, so a piped answer file drives the wizard
# non-interactively (that is how the tests use it).
# Also relies on sl_skill_dir from lib/skill-dir.sh (loaded below when not already sourced)
# to resolve the self-learn skill directory in both repo and plugin-cache layouts.

if ! command -v sl_skill_dir >/dev/null 2>&1; then . "$SRC/lib/skill-dir.sh"; fi
if ! command -v aliases_list  >/dev/null 2>&1; then . "$SRC/lib/install-aliases.sh"; fi

CONFIG_FILE="$SL_HOME/config.json"
PREV_DISABLED=""
MAX_LISTED=60

# ---------- persistence ----------
# Saved answers fill only the blanks, so an explicit flag keeps precedence.
wizard_load_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  if ! jq -e . "$CONFIG_FILE" >/dev/null 2>&1; then say "WARN $CONFIG_FILE is not valid JSON - ignoring it"; return 0; fi
  [ -n "$ROOTS_CSV" ]       || ROOTS_CSV="$(jq -r '(.roots // []) | join(",")' "$CONFIG_FILE")"
  [ -n "$WITH_HOOK" ]       || WITH_HOOK="$(jq -r 'if .hook == false then 0 else 1 end' "$CONFIG_FILE")"
  [ -n "$SCHEDULE" ]        || SCHEDULE="$(jq -r 'if .schedule.enabled == true then 1 else 0 end' "$CONFIG_FILE")"
  [ -n "$SCHED_TIME" ]      || SCHED_TIME="$(jq -r '.schedule.time // ""' "$CONFIG_FILE")"
  [ -n "$STORE_REMOTE" ]    || STORE_REMOTE="$(jq -r '.storeRemote // ""' "$CONFIG_FILE")"
  [ -n "$VSCODE_LAUNCHER" ] || VSCODE_LAUNCHER="$(jq -r 'if .vscode.claudeLauncher == true then 1 else 0 end' "$CONFIG_FILE")"
  [ -n "$VSCODE_GRAPHIFY" ] || VSCODE_GRAPHIFY="$(jq -r 'if .vscode.graphifyWatch == true then 1 else 0 end' "$CONFIG_FILE")"
  [ -n "${ALIASES:-}" ]     || ALIASES="$(jq -r 'if .aliases == false then 0 else 1 end' "$CONFIG_FILE")"
  PREV_DISABLED="$(jq -r '(.disabledRepos // [])[]' "$CONFIG_FILE")"
  DISABLED_REPOS="$PREV_DISABLED"
}

wizard_defaults() {
  [ -n "$ROOTS_CSV" ]       || ROOTS_CSV="$HOME/workspace"
  [ -n "$WITH_HOOK" ]       || WITH_HOOK=1
  [ -n "$SCHEDULE" ]        || SCHEDULE=0
  [ -n "$SCHED_TIME" ]      || SCHED_TIME="03:07"
  [ -n "$VSCODE_LAUNCHER" ] || VSCODE_LAUNCHER=0
  [ -n "$VSCODE_GRAPHIFY" ] || VSCODE_GRAPHIFY=0
  [ -n "${ALIASES:-}" ]     || ALIASES=1
}

json_bool() { if [ "$1" = 1 ]; then echo true; else echo false; fi; }

wizard_save_config() {
  if [ "$DRY" -eq 1 ]; then say "[dry-run] write $CONFIG_FILE"; return 0; fi
  mkdir -p "$SL_HOME"
  local roots_json disabled_json
  roots_json="$(printf '%s\n' "$ROOTS_CSV" | tr ',' '\n' | jq -R . | jq -s .)"
  disabled_json="$(printf '%s\n' "$DISABLED_REPOS" | { grep -v '^$' || true; } | jq -R . | jq -s .)"
  jq -n --argjson roots "$roots_json" --argjson hook "$(json_bool "$WITH_HOOK")" \
        --argjson sched "$(json_bool "$SCHEDULE")" --arg time "$SCHED_TIME" --arg remote "$STORE_REMOTE" \
        --argjson disabled "$disabled_json" --argjson launcher "$(json_bool "$VSCODE_LAUNCHER")" \
        --argjson gw "$(json_bool "$VSCODE_GRAPHIFY")" --argjson aliases "$(json_bool "${ALIASES:-1}")" \
        --arg ver "$(cat "$SRC/VERSION")" '
    {version: 1, roots: $roots, disabledRepos: $disabled, hook: $hook,
     schedule: {enabled: $sched, time: $time}, storeRemote: $remote,
     vscode: {claudeLauncher: $launcher, graphifyWatch: $gw}, aliases: $aliases,
     installedVersion: $ver, updatedAt: (now | todate)}
  ' > "$CONFIG_FILE"
  say "saved   $CONFIG_FILE"
}

# disabledRepos -> registry, and repos switched back on in the wizard -> enabled again.
apply_repo_toggles() {
  local p reg
  reg="$(sl_skill_dir)/scripts/register.sh" || {
    say "WARN cannot locate the self-learn skill directory - repo toggles skipped"; return 1; }
  while IFS= read -r p; do
    { [ -n "$p" ] && [ -d "$p" ]; } || continue
    SELF_LEARN_HOME="$SL_HOME" bash "$reg" "$p" "$(basename "$p")" --disabled | sed 's/^/  /'
  done <<< "$DISABLED_REPOS"
  while IFS= read -r p; do
    { [ -n "$p" ] && [ -d "$p" ]; } || continue
    is_disabled "$p" && continue
    SELF_LEARN_HOME="$SL_HOME" bash "$reg" "$p" "$(basename "$p")" | sed 's/^/  /'
  done <<< "$PREV_DISABLED"
}

# ---------- prompting (bash 3.2; stdin, so piped answers work) ----------
# ask VAR "question" "default" - Enter or EOF keeps the default.
ask() {
  local __var="$1" __q="$2" __def="$3" __in
  if [ -n "$__def" ]; then printf '  %s [%s]: ' "$__q" "$__def"; else printf '  %s: ' "$__q"; fi
  IFS= read -r __in || { __in=""; echo; }
  [ -n "$__in" ] || __in="$__def"
  printf -v "$__var" '%s' "$__in"
}
# yes_no "question" y|n -> exit 0 means yes.
yes_no() {
  local ans def="$2" hint="y/N"
  [ "$def" = y ] && hint="Y/n"
  ask ans "$1 ($hint)" ""
  ans="${ans:-$def}"
  case "$ans" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}
yn_default() { if [ "$1" = 1 ]; then echo y; else echo n; fi; }

# "~/a, ~/b" -> "/home/u/a,/home/u/b"
normalize_roots() {
  printf '%s' "$1" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e "s|^~|$HOME|" \
    | { grep -v '^$' || true; } | paste -sd, -
}
# Conventional dirs that exist and actually contain git repos, comma-separated.
suggest_roots() {
  local d found=""
  for d in workspace projects code dev src repos git; do
    [ -d "$HOME/$d" ] || continue
    [ -n "$(find "$HOME/$d" -maxdepth 3 -name .git -type d -print 2>/dev/null | head -1)" ] || continue
    found="${found:+$found,}$HOME/$d"
  done
  printf '%s' "$found"
}
is_disabled() { printf '%s\n' "$DISABLED_REPOS" | grep -qxF -- "$1"; }
toggle_disabled() {
  if is_disabled "$1"; then DISABLED_REPOS="$(printf '%s\n' "$DISABLED_REPOS" | { grep -vxF -- "$1" || true; })"
  else DISABLED_REPOS="$(printf '%s\n%s\n' "$DISABLED_REPOS" "$1" | { grep -v '^$' || true; })"; fi
}
count_disabled() { printf '%s\n' "$DISABLED_REPOS" | { grep -c . || true; }; }

# ---------- the seven steps ----------
ask_deps() {
  say ""; say "1/7  Dependencies - what this machine has, and what each tool is for:"
  deps_report || true
  yes_no "Install the missing ones now" n && deps_offer_install
  deps_report >/dev/null || { echo "install aborted: required tools missing (git, jq, python3)" >&2; exit 1; }
}

ask_roots() {
  local def roots missing r
  def="${ROOTS_CSV:-$(suggest_roots)}"; def="${def:-$HOME/workspace}"
  say ""; say "2/7  Where do your git repositories live? Several roots: comma-separated."
  while :; do
    ask roots "Roots" "$def"
    roots="$(normalize_roots "$roots")"
    [ -n "$roots" ] || { say "at least one root is required"; continue; }
    missing=""
    while IFS= read -r r; do [ -d "$r" ] || missing="${missing:+$missing, }$r"; done <<< "$(printf '%s' "$roots" | tr ',' '\n')"
    [ -z "$missing" ] && break
    say "not found: $missing"
    yes_no "Use anyway (create them before the first run)" n && break
    [ -t 0 ] || break
  done
  ROOTS_CSV="$roots"
}

ask_repos() {
  local -a roots_arr found
  local n i mark sel t
  IFS=, read -r -a roots_arr <<< "$ROOTS_CSV"
  found=()
  while IFS= read -r t; do [ -n "$t" ] && found+=("$t"); done \
    < <(bash "$SRC/skills/self-learn/scripts/discover.sh" --list "${roots_arr[@]}")
  n="${#found[@]}"
  say ""; say "3/7  Which repositories should it study? New ones under your roots join automatically."
  if [ "$n" -eq 0 ]; then say "none found yet - fine, they are picked up on every run"; return 0; fi
  say "found $n  (x = studied, - = skipped; numbers to toggle, Enter to accept):"
  i=0
  while [ "$i" -lt "$n" ] && [ "$i" -lt "$MAX_LISTED" ]; do
    mark=x; is_disabled "${found[$i]}" && mark=-
    say "  [$mark] $((i+1))) ${found[$i]}"
    i=$((i+1))
  done
  [ "$n" -gt "$MAX_LISTED" ] && say "  ... $((n-MAX_LISTED)) more - edit disabledRepos in $CONFIG_FILE for those"
  ask sel "Toggle" ""
  for t in $sel; do
    case "$t" in ''|*[!0-9]*) continue ;; esac
    { [ "$t" -ge 1 ] && [ "$t" -le "$n" ]; } || continue
    toggle_disabled "${found[$((t-1))]}"
  done
  say "studying $((n - $(count_disabled))) of $n"
}

ask_hook() {
  say ""; say "4/7  Routing hook (UserPromptSubmit): a one-line nudge toward a skill when a prompt matches a learned phrasing; silent otherwise."
  if yes_no "Install the routing hook" "$(yn_default "$WITH_HOOK")"; then WITH_HOOK=1; else WITH_HOOK=0; fi
}

ask_schedule() {
  local t
  say ""; say "5/7  Nightly run: launchd on macOS, systemd --user on Linux, a crontab line elsewhere."
  if ! yes_no "Run every night" "$(yn_default "$SCHEDULE")"; then SCHEDULE=0; return 0; fi
  SCHEDULE=1
  while :; do
    ask t "Local time, 24h HH:MM" "${SCHED_TIME:-03:07}"
    if printf '%s' "$t" | grep -qE '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'; then SCHED_TIME="$t"; return 0; fi
    say "not a valid HH:MM"
    [ -t 0 ] || { SCHED_TIME="${SCHED_TIME:-03:07}"; return 0; }
  done
}

ask_remote() {
  say ""; say "6/7  Private remote: the store holds project names, paths and distilled feedback - back it up ONLY to a PRIVATE repo."
  ask STORE_REMOTE "Git remote URL (Enter to skip, 'none' to clear)" "$STORE_REMOTE"
  case "$STORE_REMOTE" in none|-|skip) STORE_REMOTE="" ;; esac
}

ask_vscode() {
  say ""; say "7/7  VS Code companions (bundled in vscode/, MIT, installed through the code CLI):"
  say "  claude-launcher  a rocket button in the editor title bar: opens a terminal at the window's root and runs claude in auto mode - one click into a session from any project"
  say "  graphify-watch   keeps the graphify knowledge graph of the open folder current (native file watching, one-shot rebuilds, state in the status bar) so agents query the graph instead of grepping; needs graphify"
  dep_present code || say "  (code CLI not found - choices are saved; in VS Code run 'Shell Command: Install code command in PATH', then re-run $0)"
  if yes_no "Install claude-launcher" "$(yn_default "$VSCODE_LAUNCHER")"; then VSCODE_LAUNCHER=1; else VSCODE_LAUNCHER=0; fi
  if yes_no "Install graphify-watch" "$(yn_default "$VSCODE_GRAPHIFY")"; then VSCODE_GRAPHIFY=1; else VSCODE_GRAPHIFY=0; fi
}

wizard_run() {
  step "Setup wizard  (Enter keeps the default; re-run any time with: $0 --wizard)"
  if [ -f "$CONFIG_FILE" ] && [ -n "$ROOTS_CSV" ]; then
    say "saved configuration in $CONFIG_FILE:"
    say "  roots $ROOTS_CSV | skipped repos $(count_disabled) | hook $([ "$WITH_HOOK" = 1 ] && echo on || echo off) | nightly $([ "$SCHEDULE" = 1 ] && echo "at $SCHED_TIME" || echo off) | remote ${STORE_REMOTE:-none} | vscode launcher=$(yn_default "$VSCODE_LAUNCHER") graphify-watch=$(yn_default "$VSCODE_GRAPHIFY") | short aliases $([ "${ALIASES:-1}" = 1 ] && echo on || echo off)"
    yes_no "Keep it and just upgrade" y && return 0
  fi
  ask_deps
  ask_roots
  ask_repos
  ask_hook
  ask_schedule
  ask_remote
  ask_vscode
  step "Summary"
  say "roots:    $ROOTS_CSV"
  say "skipped:  $(count_disabled) repos"
  say "hook:     $([ "$WITH_HOOK" = 1 ] && echo install || echo skip)"
  say "nightly:  $([ "$SCHEDULE" = 1 ] && echo "every day at $SCHED_TIME" || echo off)"
  say "remote:   ${STORE_REMOTE:-none (store stays local)}"
  say "vscode:   claude-launcher=$(yn_default "$VSCODE_LAUNCHER") graphify-watch=$(yn_default "$VSCODE_GRAPHIFY")"
  say "aliases:  $([ "${ALIASES:-1}" = 1 ] && aliases_list || echo "skipped")"
  say "saved to: $CONFIG_FILE"
  yes_no "Proceed" y || { echo "aborted - nothing was changed"; exit 0; }
}
