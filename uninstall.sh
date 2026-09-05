#!/usr/bin/env bash
# uninstall.sh - remove the self-learn extension. Keeps your private store (journal,
# cursors, snapshots) unless you pass --purge-store.
#
#   ./uninstall.sh [--purge-store] [--dry-run]
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL_HOME="${SELF_LEARN_HOME:-$CLAUDE_DIR/self-learn}"
LABEL="com.self-learn.nightly"
PURGE=0; DRY=0
for a in "$@"; do
  case "$a" in
    --purge-store) PURGE=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
say() { printf '  %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

echo "==> Scheduler"
case "$(uname -s)" in
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    if [ -f "$PLIST" ]; then
      run launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
      run rm -f "$PLIST"; say "removed $PLIST"
    fi ;;
  Linux)
    if [ -f "$HOME/.config/systemd/user/self-learn-nightly.timer" ]; then
      run systemctl --user disable --now self-learn-nightly.timer 2>/dev/null || true
      run rm -f "$HOME/.config/systemd/user/self-learn-nightly.timer" "$HOME/.config/systemd/user/self-learn-nightly.service"
      say "removed systemd user units"
    fi ;;
esac

echo "==> Skills"
for s in self-learn model-balance loop-audit loop-contract setup; do   # last two: pre-1.1.1 names
  [ -d "$CLAUDE_DIR/skills/$s" ] && { run rm -rf "$CLAUDE_DIR/skills/$s"; say "removed $CLAUDE_DIR/skills/$s"; }
done

echo "==> Hook"
HOOK="$CLAUDE_DIR/hooks/skill-router.py"
[ -f "$HOOK" ] && { run rm -f "$HOOK"; say "removed $HOOK"; }
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ] && jq -e '.hooks.UserPromptSubmit' "$SETTINGS" >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then say "[dry-run] drop skill-router entry from $SETTINGS"; else
    tmp="$(mktemp)"
    jq '
      .hooks.UserPromptSubmit = [ .hooks.UserPromptSubmit[]
        | .hooks = [ .hooks[]? | select((.command // "") | test("skill-router.py") | not) ]
        | select((.hooks | length) > 0) ]
      | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    say "unregistered hook in $SETTINGS"
  fi
fi

echo "==> Runtime"
[ -f "$CLAUDE_DIR/lib/claude-retry.sh" ] && { run rm -f "$CLAUDE_DIR/lib/claude-retry.sh"; say "removed lib/claude-retry.sh"; }
[ -f "$CLAUDE_DIR/lib/skill-dir.sh" ] && { run rm -f "$CLAUDE_DIR/lib/skill-dir.sh"; say "removed lib/skill-dir.sh"; }
[ -f "$CLAUDE_DIR/night-guard-settings.json" ] && { run rm -f "$CLAUDE_DIR/night-guard-settings.json"; say "removed night-guard-settings.json"; }

echo "==> Store"
if [ "$PURGE" -eq 1 ]; then
  [ -d "$SL_HOME" ] && { run rm -rf "$SL_HOME"; say "PURGED $SL_HOME"; }
else
  say "kept $SL_HOME (journal, cursors, snapshots). Pass --purge-store to delete it."
fi
echo "done"
