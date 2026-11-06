#!/usr/bin/env bash
# install-hoply.sh - question 2 of the one-line installer: the Hoply token, its headers helper and the MCP server entry.

HOPLY_DIR="${HOPLY_CONFIG_DIR:-$HOME/.config/hoply}"
HOPLY_DEFAULT_URL="https://app.hoply.work/mcp"
HOPLY_TOKEN_RE='^hpt_[A-Za-z0-9]{43}$'
HOPLY_CONNECTED=0

hoply_token_valid() { printf '%s' "$1" | grep -qE "$HOPLY_TOKEN_RE"; }

hoply_read_token() {
  local __var="$1" __in=""
  printf '  %s' "Do you use Hoply? Paste your token from Hoply - Connectors - Claude Code (Enter to skip): "
  IFS= read -rs __in || true
  echo
  printf -v "$__var" '%s' "$(printf '%s' "$__in" | tr -d '[:space:]')"
}

# The token lives in its own 0600 file; Claude Code runs headers.sh per connection, so ~/.claude.json never holds it.
hoply_write_files() {
  case "$HOPLY_DIR" in *"'"*|*[[:space:]]*) echo "the Hoply config path may not contain quotes or spaces: $HOPLY_DIR" >&2; return 1 ;; esac
  ( umask 077 && mkdir -p "$HOPLY_DIR" && printf '%s\n' "$1" > "$HOPLY_DIR/token" ) || return 1
  chmod 700 "$HOPLY_DIR" && chmod 600 "$HOPLY_DIR/token" || return 1
  cat > "$HOPLY_DIR/headers.sh" <<EOF || return 1
#!/bin/sh
t="\$(cat '$HOPLY_DIR/token')" || exit 1
printf '{"Authorization":"Bearer %s"}\n' "\$t"
EOF
  chmod 700 "$HOPLY_DIR/headers.sh" || return 1
  say "saved   $HOPLY_DIR/token (0600) and headers.sh (0700)"
}

hoply_register() {
  local url="$1" json out
  json="$(jq -cn --arg url "$url" --arg h "$HOPLY_DIR/headers.sh" '{type: "http", url: $url, headersHelper: $h}')" || return 1
  "$CLAUDE_BIN" mcp remove hoply --scope user >/dev/null 2>&1 || true
  "$CLAUDE_BIN" mcp add-json hoply "$json" --scope user >/dev/null || {
    echo "claude mcp add-json failed - the Hoply MCP server was not added; fix the error above, then run: npx -y jb-kaizen --hoply" >&2
    return 1; }
  out="$("$CLAUDE_BIN" mcp get hoply 2>&1)" || { echo "claude mcp get hoply failed after the add - check: claude mcp list" >&2; return 1; }
  say "added   MCP server hoply -> $url (user scope)"
  case "$out" in
    *"Failed to connect"*) say "WARN    Hoply did not answer yet - check the URL or your network; /mcp in Claude Code shows the live state" ;;
    *) say "status  $(printf '%s\n' "$out" | grep -m1 'Status:' | sed 's/^ *Status: *//')" ;;
  esac
}

hoply_save_config() {
  local cfg="$SL_HOME/config.json" tmp
  mkdir -p "$SL_HOME" || return 1; [ -f "$cfg" ] || echo '{}' > "$cfg"
  jq -e . "$cfg" >/dev/null 2>&1 || { say "WARN    $cfg is not valid JSON - Hoply settings not saved there"; return 0; }
  tmp="$(mktemp)"
  jq --arg url "$1" '.hoply = ((.hoply // {}) + {url: $url, connected: true})' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
}

# $1 = ask (hidden prompt) | stdin (one line, for scripts and tests). Returns 2 for a malformed scripted token, 1 when a write fails.
hoply_step() {
  local token="" url="${HOPLY_URL:-$HOPLY_DEFAULT_URL}"
  step "Hoply"
  if [ "$1" = stdin ]; then
    IFS= read -r token || true
    token="$(printf '%s' "$token" | tr -d '[:space:]')"
    hoply_token_valid "$token" || { echo "refused: not a Hoply token (hpt_ followed by 43 letters and digits) - nothing written" >&2; return 2; }
  else
    hoply_read_token token
    if [ -n "$token" ] && ! hoply_token_valid "$token"; then
      say "that is not a Hoply token (it starts with hpt_) - paste it once more, or Enter to skip"
      hoply_read_token token
    fi
    if ! hoply_token_valid "$token"; then say "skip    nothing written (connect later: npx -y jb-kaizen --hoply)"; return 0; fi
  fi
  hoply_write_files "$token" || return 1
  token=""
  hoply_register "$url" || return 1
  hoply_save_config "$url" || return 1
  HOPLY_CONNECTED=1
}

hoply_summary() {
  local day="/kaizen:hoply-day"
  [ "${REC_MODE:-plugin}" = plugin ] || day="/hoply-day"
  step "Ready"
  if [ "$HOPLY_CONNECTED" = 1 ] || jq -e '.hoply.connected == true' "$SL_HOME/config.json" >/dev/null 2>&1; then
    say "Hoply:   connected - in Claude Code type $day to review and confirm your day"
    say "         (offered on workdays from 17:15 Europe/Kyiv; disconnect: uninstall.sh --hoply)"
  else
    say "Hoply:   not connected - add it any time: npx -y jb-kaizen --hoply  (token: Hoply - Connectors - Claude Code)"
  fi
}
