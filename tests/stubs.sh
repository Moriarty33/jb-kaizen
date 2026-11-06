# shellcheck shell=bash disable=SC2154  # sourced by smoke.sh: no smoke run may reach the real claude, launchd, systemd or notifications

STUB="$T/stub"; STUB_LOG="$T/stub-log"; mkdir -p "$STUB" "$STUB_LOG"
for t in launchctl systemctl osascript notify-send; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/%s.log"\n' "$t" "$STUB_LOG" "$t" > "$STUB/$t"
done
cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$STUB_LOG/claude.log"
case "\$1 \$2" in
  "mcp get") [ -f "$STUB_LOG/mcp-hoply" ] || exit 1; printf 'hoply:\n  Status: connected\n' ;;
  "mcp add-json") if [ -f "$STUB_LOG/fail-add-json" ]; then echo "stub: add-json refused" >&2; exit 1; fi; touch "$STUB_LOG/mcp-hoply" ;;
  "mcp remove") rm -f "$STUB_LOG/mcp-hoply" ;;
  "plugin marketplace") if [ "\$3" = add ]; then touch "$STUB_LOG/mkt-kaizen"; elif [ -f "$STUB_LOG/mkt-kaizen" ]; then echo jb-kaizen; fi ;;
  "plugin list") if [ -f "$STUB_LOG/plugin-kaizen" ]; then echo "kaizen@jb-kaizen"; fi ;;
  "plugin install") touch "$STUB_LOG/plugin-kaizen" ;;
esac
exit 0
EOF
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
