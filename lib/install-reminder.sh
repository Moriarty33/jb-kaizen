#!/usr/bin/env bash
# install-reminder.sh - the Hoply day-review nudge hook (clone installs) and the OS reminder; sourced by install.sh and uninstall.sh.

HOPLY_LABEL="com.self-learn.hoply-day"
HOPLY_UNIT="self-learn-hoply-day"

# Drop every hook entry whose command matches the regex, from every event; empty events and .hooks go too.
settings_drop_hook() {
  local settings="$1" re="$2" tmp
  [ -f "$settings" ] && jq -e '.hooks' "$settings" >/dev/null 2>&1 || return 0
  tmp="$(mktemp)"
  jq --arg re "$re" '
    .hooks |= with_entries(
      .value = [ .value[]? | .hooks = [ .hooks[]? | select((.command // "") | test($re) | not) ] | select((.hooks | length) > 0) ]
      | select((.value | length) > 0))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

settings_add_hook() {
  local settings="$1" cmd="$2" tmp
  [ -f "$settings" ] || echo '{}' > "$settings"
  tmp="$(mktemp)"
  jq --arg c "$cmd" '
    def add(ev): .hooks[ev] = ((.hooks[ev] // [])
      + (if ([.hooks[ev][]?.hooks[]? | select(.command == $c)] | length) > 0 then [] else [{hooks: [{type: "command", command: $c}]}] end));
    .hooks = (.hooks // {}) | add("SessionStart") | add("UserPromptSubmit")
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
}

# Clone installs register the nudge themselves; the plugin ships it in hooks/hooks.json.
nudge_hook_apply() {
  local settings="$CLAUDE_DIR/settings.json" hook="$CLAUDE_DIR/hooks/hoply-day-nudge.py"
  [ "$PLUGIN_MODE" -eq 1 ] && return 0
  if [ -d "$CLAUDE_DIR/skills/hoply-day" ] && sl_is_ours "$CLAUDE_DIR/skills/hoply-day"; then
    step "Hoply day nudge (SessionStart, UserPromptSubmit)"
    put "$SRC/hooks/hoply-day-nudge.py" "$hook"
    if [ "$DRY" -eq 1 ]; then say "[dry-run] register 'python3 $hook' in $settings"; return 0; fi
    if jq -e --arg c "python3 $hook" '[.hooks.SessionStart[]?.hooks[]? | select(.command == $c)] | length > 0' "$settings" >/dev/null 2>&1; then
      say "keep    nudge already registered in $settings"
    else
      cp "$settings" "$settings.bak-$STAMP" 2>/dev/null || true
      settings_add_hook "$settings" "python3 $hook"
      say "register nudge in $settings"
    fi
  elif [ -f "$hook" ]; then
    run rm -f "$hook"; say "removed $hook (hoply-day not installed)"
    [ "$DRY" -eq 1 ] || settings_drop_hook "$settings" 'hoply-day-nudge[.]py'
  fi
}

# Older tzdata only knows the Kiev spelling; systemd refuses an unknown zone in OnCalendar.
reminder_tz() {
  local tz="${HOPLY_TZ:-Europe/Kyiv}" zi="${TZDIR:-/usr/share/zoneinfo}"
  if [ "$tz" = Europe/Kyiv ] && [ ! -e "$zi/Europe/Kyiv" ] && [ -e "$zi/Europe/Kiev" ]; then tz="Europe/Kiev"; fi
  printf '%s' "$tz"
}

reminder_render() {
  local from="$1" to="$2" arg="" tz
  [ "$PLUGIN_MODE" -eq 1 ] && arg="--plugin"
  tz="$(reminder_tz)"
  sed -e "s|__HOPLY_LABEL__|$HOPLY_LABEL|g" -e "s|__SL_HOME__|$SL_HOME|g" -e "s|__HOME__|$HOME|g" \
      -e "s|__HOPLY_ARG__|$arg|g" -e "s|__HOPLY_TIME__|${HOPLY_TIME:-17:15}|g" -e "s|__HOPLY_TZ__|$tz|g" "$from" > "$to"
}

# Writes $2 from template $1 only when it changed; returns 0 when it did.
reminder_put() {
  local tmp; tmp="$(mktemp)"
  reminder_render "$1" "$tmp"
  if [ -f "$2" ] && cmp -s "$tmp" "$2"; then rm -f "$tmp"; return 1; fi
  mkdir -p "$(dirname "$2")"; mv "$tmp" "$2"; say "render  $2"
}

reminder_remove() {
  local plist="$HOME/Library/LaunchAgents/$HOPLY_LABEL.plist" units="$HOME/.config/systemd/user"
  if [ -f "$plist" ]; then
    run launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    run rm -f "$plist"; say "removed $plist"
  fi
  if [ -f "$units/$HOPLY_UNIT.timer" ]; then
    run systemctl --user disable --now "$HOPLY_UNIT.timer" 2>/dev/null || true
    run rm -f "$units/$HOPLY_UNIT.timer" "$units/$HOPLY_UNIT.service"; say "removed $HOPLY_UNIT systemd units"
  fi
}

reminder_apply() {
  local plist="$HOME/Library/LaunchAgents/$HOPLY_LABEL.plist" units="$HOME/.config/systemd/user"
  if [ "${HOPLY_REMINDER:-}" != 1 ]; then
    if [ "${HOPLY_REMINDER:-}" = 0 ] && { [ -f "$plist" ] || [ -f "$units/$HOPLY_UNIT.timer" ]; }; then step "Hoply reminder"; reminder_remove; fi
    return 0
  fi
  step "Hoply reminder (workdays from ${HOPLY_TIME:-17:15} ${HOPLY_TZ:-Europe/Kyiv})"
  put "$SRC/hooks/hoply-day-nudge.py" "$SL_HOME/scripts/hoply-day-nudge.py"
  put "$SRC/templates/hoply-day-notify.sh" "$SL_HOME/scripts/hoply-day-notify.sh"
  if [ "$DRY" -eq 1 ]; then say "[dry-run] install the $HOPLY_LABEL reminder"; return 0; fi
  chmod +x "$SL_HOME/scripts/hoply-day-notify.sh"; mkdir -p "$SL_HOME/logs"
  case "$(uname -s)" in
    Darwin)
      if reminder_put "$SRC/templates/hoply-day.plist" "$plist"; then
        launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
        launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || launchctl load "$plist"
        say "loaded  $HOPLY_LABEL"
      else say "keep    $plist"; fi ;;
    Linux)
      reminder_put "$SRC/templates/hoply-day.service" "$units/$HOPLY_UNIT.service" || true
      reminder_put "$SRC/templates/hoply-day.timer" "$units/$HOPLY_UNIT.timer" || true
      if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null; then
        if systemctl --user enable --now "$HOPLY_UNIT.timer" >/dev/null 2>&1; then say "enabled $HOPLY_UNIT.timer"; else say "WARN    could not enable $HOPLY_UNIT.timer"; fi
      else say "systemd --user unavailable - the in-session nudge still offers the review"; fi ;;
    *) say "no OS reminder for $(uname -s) - the in-session nudge still offers the review" ;;
  esac
}
