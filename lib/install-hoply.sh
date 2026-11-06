#!/usr/bin/env bash
# install-hoply.sh - question 2 of the one-line installer: add the Hoply MCP server and sign in through the browser.

HOPLY_DIR="${HOPLY_CONFIG_DIR:-$HOME/.config/hoply}"
HOPLY_DEFAULT_URL="https://app.hoply.work/mcp"
HOPLY_TOKEN_RE='^hpt_[A-Za-z0-9]{43}$'
HOPLY_AUTH_LINE="open Claude Code and run /mcp -> hoply -> Authenticate"
HOPLY_CONNECTED=0; HOPLY_AUTH_PENDING=0

hoply_token_valid() { printf '%s' "$1" | grep -qE "$HOPLY_TOKEN_RE"; }

# CI only: the token lives in its own 0600 file; Claude Code runs headers.sh per connection, so ~/.claude.json never holds it.
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

hoply_add_token() {
  local url="$1" json out
  json="$(jq -cn --arg url "$url" --arg h "$HOPLY_DIR/headers.sh" '{type: "http", url: $url, headersHelper: $h}')" || return 1
  "$CLAUDE_BIN" mcp remove hoply --scope user >/dev/null 2>&1 || true
  "$CLAUDE_BIN" mcp add-json hoply "$json" --scope user >/dev/null || {
    echo "claude mcp add-json failed - the Hoply MCP server was not added; fix the error above and run this again" >&2
    return 1; }
  out="$("$CLAUDE_BIN" mcp get hoply 2>&1)" || { echo "claude mcp get hoply failed after the add - check: claude mcp list" >&2; return 1; }
  say "added   MCP server hoply -> $url (user scope, token from $HOPLY_DIR)"
  case "$out" in
    *"Failed to connect"*) say "WARN    Hoply did not answer yet - check the URL or your network; /mcp in Claude Code shows the live state" ;;
    *) say "status  $(printf '%s\n' "$out" | grep -m1 'Status:' | sed 's/^ *Status: *//')" ;;
  esac
}

# No header: Claude Code discovers Hoply's sign-in from the server's 401 and keeps the OAuth tokens itself.
hoply_add_oauth() {
  "$CLAUDE_BIN" mcp remove hoply --scope user >/dev/null 2>&1 || true
  "$CLAUDE_BIN" mcp add --transport http --scope user hoply "$1" >/dev/null || {
    echo "claude mcp add failed - the Hoply MCP server was not added; fix the error above and run: npx -y jb-kaizen --hoply" >&2
    return 1; }
  say "added   MCP server hoply -> $1 (user scope, sign-in with your Hoply account)"
}

hoply_has_login() {
  local help; help="$("$CLAUDE_BIN" mcp --help 2>&1 || true)"
  printf '%s\n' "$help" | grep -qE '^[[:space:]]+login[[:space:]]'
}

# `claude mcp login` refuses to run without a terminal, so a piped stdin borrows /dev/tty when there is one.
hoply_tty() {
  if [ -t 0 ] || [ "${KAIZEN_TEST_MODE:-}" = 1 ]; then echo stdin; return 0; fi
  if (exec 3</dev/tty) 2>/dev/null; then echo devtty; return 0; fi
  return 1
}

# Best first: `claude mcp login` opens the browser and returns here; then Claude Code's own /mcp screen; last, one line to follow.
hoply_sign_in() {
  local tty
  if ! tty="$(hoply_tty)"; then HOPLY_AUTH_PENDING=1; say "next    $HOPLY_AUTH_LINE"; return 0; fi
  if hoply_has_login; then
    say "opening your browser to sign in to Hoply - come back here when the page says you are signed in"
    if { [ "$tty" = stdin ] && "$CLAUDE_BIN" mcp login hoply; } || { [ "$tty" = devtty ] && "$CLAUDE_BIN" mcp login hoply < /dev/tty; }; then
      say "signed in to Hoply"; return 0
    fi
    HOPLY_AUTH_PENDING=1; say "WARN    sign-in did not finish - $HOPLY_AUTH_LINE"; return 0
  fi
  HOPLY_AUTH_PENDING=1
  say "this Claude Code has no 'mcp login': it opens on /mcp now - pick hoply -> Authenticate, then /exit to come back"
  if [ "$tty" = devtty ]; then "$CLAUDE_BIN" "/mcp" < /dev/tty || true; else "$CLAUDE_BIN" "/mcp" || true; fi
}

hoply_save_config() {
  local cfg="$SL_HOME/config.json" tmp
  mkdir -p "$SL_HOME" || return 1; [ -f "$cfg" ] || echo '{}' > "$cfg"
  jq -e . "$cfg" >/dev/null 2>&1 || { say "WARN    $cfg is not valid JSON - Hoply settings not saved there"; return 0; }
  tmp="$(mktemp)"
  jq --arg url "$1" --arg auth "$2" '.hoply = ((.hoply // {}) + {url: $url, connected: true, auth: $auth})' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
}

# $1 = ask (question 2) | connect (--hoply) | token (--token / HOPLY_TOKEN, CI). Returns 2 for a malformed token, 1 when a write fails.
hoply_step() {
  local url="${HOPLY_URL:-$HOPLY_DEFAULT_URL}" token="${HOPLY_TOKEN_VALUE:-}" ans=""
  step "Hoply"
  if [ "$1" = token ]; then
    hoply_token_valid "$token" || { echo "refused: not a Hoply token (hpt_ followed by 43 letters and digits) - nothing written" >&2; return 2; }
    hoply_write_files "$token" || return 1
    token=""
    hoply_add_token "$url" || return 1
    hoply_save_config "$url" token || return 1
    HOPLY_CONNECTED=1
    return 0
  fi
  if [ "$1" = ask ]; then
    say "Hoply reviews your day at 17:15 so you confirm your hours instead of typing them; you sign in in the browser."
    entry_ask ans "Connect Hoply? [Y/n]" || true
    case "$ans" in n|N|no|No|NO) say "skip    Hoply (connect later: npx -y jb-kaizen --hoply)"; return 0 ;; esac
  fi
  hoply_add_oauth "$url" || return 1
  hoply_save_config "$url" oauth || return 1
  HOPLY_CONNECTED=1
  hoply_sign_in
}

hoply_summary() {
  local day="/kaizen:hoply-day"
  [ "${REC_MODE:-plugin}" = plugin ] || day="/hoply-day"
  step "Ready"
  if [ "$HOPLY_CONNECTED" = 1 ] || jq -e '.hoply.connected == true' "$SL_HOME/config.json" >/dev/null 2>&1; then
    say "Hoply:   connected - in Claude Code type $day to review and confirm your day"
    [ "$HOPLY_AUTH_PENDING" = 1 ] && say "         still to do: $HOPLY_AUTH_LINE"
    say "         (offered on workdays from 17:15 Europe/Kyiv; disconnect: uninstall.sh --hoply)"
  else
    say "Hoply:   not connected - add it any time: npx -y jb-kaizen --hoply"
  fi
}
