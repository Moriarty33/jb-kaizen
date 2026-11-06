#!/usr/bin/env bash
# hoply-day-notify.sh - launchd/systemd reminder; the clock and the stamps shared with the hook live in hoply-day-nudge.py.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command_name="$(python3 "$HERE/hoply-day-nudge.py" --channel notified "$@" 2>/dev/null)" || exit 0
[ -n "$command_name" ] || exit 0
text="Your day is ready: open Claude Code and type $command_name"

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$text\" with title \"Hoply\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "Hoply" "$text" >/dev/null 2>&1 || true
else
  printf 'Hoply: %s\n' "$text"
fi
exit 0
