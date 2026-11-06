#!/usr/bin/env bash
# uninstall.sh - remove the self-learn extension. Keeps your private store (journal,
# cursors, snapshots) unless you pass --purge-store; --hoply also disconnects Hoply.
#
#   ./uninstall.sh [--purge-store] [--hoply] [--dry-run]
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL_HOME="${SELF_LEARN_HOME:-$CLAUDE_DIR/self-learn}"
LABEL="com.self-learn.nightly"
PURGE=0; DRY=0; HOPLY=0
for a in "$@"; do
  case "$a" in
    --purge-store) PURGE=1 ;;
    --hoply) HOPLY=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
say() { printf '  %s\n' "$*"; }
run() { if [ "$DRY" -eq 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# lib/install-aliases.sh owns the alias list and its removal (one place, not two). Sourced
# before the first removal so a missing lib aborts intact instead of half-uninstalled.
ALIAS_LIB="$(dirname "$0")/lib/install-aliases.sh"
[ -f "$ALIAS_LIB" ] || { echo "uninstall: missing $ALIAS_LIB - aborting, nothing was removed" >&2; exit 2; }
# shellcheck source=lib/install-aliases.sh
. "$ALIAS_LIB"
REMINDER_LIB="$(dirname "$0")/lib/install-reminder.sh"
[ -f "$REMINDER_LIB" ] || { echo "uninstall: missing $REMINDER_LIB - aborting, nothing was removed" >&2; exit 2; }
# shellcheck source=lib/install-reminder.sh
. "$REMINDER_LIB"

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

reminder_remove

echo "==> Skills"
for s in self-learn model-balance loop-audit loop-contract kaizen-setup; do   # loop-contract: pre-1.1.1 name; kaizen-setup: pre-1.1.2 name
  [ -d "$CLAUDE_DIR/skills/$s" ] && { run rm -rf "$CLAUDE_DIR/skills/$s"; say "removed $CLAUDE_DIR/skills/$s"; }
done
for s in setup hoply-day commit review-code fix-pr-comments github; do   # generic names: ours only with the marker
  d="$CLAUDE_DIR/skills/$s"
  [ -d "$d" ] && sl_is_ours "$d" && { run rm -rf "$d"; say "removed $d"; } || true
done
aliases_remove

echo "==> Hook"
for h in skill-router.py hoply-day-nudge.py; do
  [ -f "$CLAUDE_DIR/hooks/$h" ] && { run rm -f "$CLAUDE_DIR/hooks/$h"; say "removed $CLAUDE_DIR/hooks/$h"; }
done
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ] && jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then say "[dry-run] drop the skill-router and hoply-day-nudge entries from $SETTINGS"; else
    settings_drop_hook "$SETTINGS" 'skill-router[.]py|hoply-day-nudge[.]py'
    say "unregistered hooks in $SETTINGS"
  fi
fi

if [ "$HOPLY" -eq 1 ]; then
  echo "==> Hoply"
  if command -v "${CLAUDE_BIN:-claude}" >/dev/null 2>&1; then
    run "${CLAUDE_BIN:-claude}" mcp logout hoply >/dev/null 2>&1 || true
    run "${CLAUDE_BIN:-claude}" mcp remove hoply --scope user >/dev/null 2>&1 || true
    say "signed out of Hoply and removed MCP server hoply"
  fi
  HOPLY_DIR="${HOPLY_CONFIG_DIR:-$HOME/.config/hoply}"
  [ -d "$HOPLY_DIR" ] && { run rm -rf "$HOPLY_DIR"; say "removed $HOPLY_DIR (token and headers helper)"; }
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
