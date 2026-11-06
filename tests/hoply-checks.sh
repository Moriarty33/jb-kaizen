# shellcheck shell=bash disable=SC2154,SC2034  # sourced by smoke.sh after tests/stubs.sh; uses its harness helpers and sets lib inputs
# Hoply pairing and the one-line installer: nudge clock, notify script, install-entry flows, bundled skills, leaks.

# ---- 10a. syntax, manifests, versions ----
for f in "$ROOT/install-entry.sh" "$ROOT/bootstrap.sh" "$ROOT/templates/hoply-day-notify.sh" "$ROOT/tests/stubs.sh" "$ROOT/tests/hoply-checks.sh"; do check bash -n "$f"; done
check python3 -m py_compile "$ROOT/hooks/hoply-day-nudge.py"
HK="$ROOT/hooks/hooks.json"
check jq -e '.hooks.SessionStart[0].hooks[0].command | test("CLAUDE_PLUGIN_ROOT.*hooks/hoply-day-nudge[.]py.*--plugin")' "$HK"
check jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | test("skill-router[.]py")' "$HK"
check jq -e '.hooks.UserPromptSubmit[0].hooks[1].command | test("hoply-day-nudge[.]py.*--plugin")' "$HK"
check jq -e --arg v "$VER" '.version == $v and .name == "jb-kaizen" and .bin["jb-kaizen"] == "bin/jb-kaizen.js"' "$ROOT/npm/package.json"
check grep -q "^## \[$VER\]" "$ROOT/CHANGELOG.md"
check grep -q "refs/tags/v$VER.tar.gz" "$ROOT/brew/jb-kaizen.rb"
check test "$(bash "$ROOT/install-entry.sh" --version)" = "$VER"
if command -v node >/dev/null 2>&1; then check test "$(node "$ROOT/npm/bin/jb-kaizen.js" --version)" = "$VER"; fi
for f in install.sh install-entry.sh tests/smoke.sh tests/hoply-checks.sh README.md README.uk.md lib/install-wizard.sh; do check test "$(wc -l < "$ROOT/$f" | tr -d ' ')" -le 300; done
for s in hoply-day commit review-code fix-pr-comments github; do
  check grep -q 'Shipped with JB Kaizen' "$ROOT/skills/$s/SKILL.md"
  check grep -qE '^description: .{80,}' "$ROOT/skills/$s/SKILL.md"
done
check test -f "$ROOT/skills/review-code/rules.md"
check grep -q 'mcp__hoply__confirmProposals' "$ROOT/skills/hoply-day/SKILL.md"
check jq -e '[.rules[] | select(.skill == "hoply-day")] | length == 1' "$ROOT/templates/routing-map.json"

# ---- 10b. no personal or client names in the public tree (the widened pattern lives only in the private store) ----
LEAK_BASE='/Users/bogda[n]|bogdan\.jaminski|jaminski\.ua'
no_leak() { ! grep -rniE "$1" --exclude-dir=.git --exclude-dir=__pycache__ --exclude-dir=node_modules --exclude-dir=dist "$ROOT" >/dev/null 2>&1; }
check no_leak "$LEAK_BASE"
PUB="$ROOT/../scripts/publish.sh"
if [ -f "$PUB" ]; then
  CL="$(sed -n "s/^CLIENT_LEAK='\(.*\)'$/\1/p" "$PUB")"
  no_client_leak() { [ -n "$CL" ] && no_leak "$CL"; }; check no_client_leak
else ok "client-name leak check skipped (no private store around this checkout)"; fi
EMDASH="$(printf '\342\200\224')"
for s in hoply-day commit review-code fix-pr-comments github; do check bash -c '! grep -rqF "$1" "$2"' _ "$EMDASH" "$ROOT/skills/$s"; done

# ---- 10c. the nudge: fake clock, stamps, channels ----
NH="$T/nudge"; mkdir -p "$NH/hoply" "$NH/sl"; NUDGE="$ROOT/hooks/hoply-day-nudge.py"
PROMPT_JSON='{"hook_event_name":"UserPromptSubmit","prompt":"hi"}'
nudge() { echo "${2:-$PROMPT_JSON}" | TZ=UTC KAIZEN_TEST_MODE=1 KAIZEN_NOW="$1" \
  HOPLY_CONFIG_DIR="$NH/hoply" SELF_LEARN_HOME="$NH/sl" python3 "$NUDGE" ${3:-}; }
silent() { [ -z "$(nudge "$@")" ]; }
fires() { nudge "$@" | jq -e '.systemMessage | test("hoply-day")' >/dev/null; }
check silent 2026-11-06T15:15:00+00:00                          # no token file yet
echo t > "$NH/hoply/token"
check silent 2026-11-06T15:14:00+00:00                          # Friday 17:14 Kyiv (winter, UTC+2)
check fires 2026-11-06T15:15:00+00:00                           # 17:15 Kyiv on a UTC machine
check test -f "$NH/sl/hoply-day/2026-11-06.offered"
check silent 2026-11-06T16:00:00+00:00                          # offered once per day
check silent 2026-11-07T15:30:00+00:00                          # Saturday
check fires 2026-07-03T14:15:00+00:00                           # summer, UTC+3: DST honoured
check silent 2026-07-03T15:00:00+00:00 '{"prompt":"x"}' --plugin # stamp from the line above holds
check test ! -f "$NH/sl/hoply-day/2026-11-06.offered"           # older stamps are pruned
touch "$NH/sl/hoply-day/2026-11-09.done"
check silent 2026-11-09T15:20:00+00:00                          # the skill marked the day done
check grep -q '/kaizen:hoply-day' <<<"$(nudge 2026-11-10T15:20:00+00:00 '' --plugin)"
check jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' <<<"$(nudge 2026-11-11T15:20:00+00:00 '{"hook_event_name":"SessionStart"}')"
check jq -e '.systemMessage | endswith("type /hoply-day")' <<<"$(nudge 2026-11-12T15:20:00+00:00)"   # clone install
check silent 2026-11-13T15:20:00+00:00 '{"prompt":"/kaizen:hoply-day"}'   # already asking for it
check test ! -f "$NH/sl/hoply-day/2026-11-13.offered"
echo '{"hoply":{"reminder":false}}' > "$NH/sl/config.json"; check silent 2026-11-16T15:20:00+00:00
echo '{"hoply":{"time":"18:00","timezone":"UTC"}}' > "$NH/sl/config.json"
check silent 2026-11-16T17:59:00+00:00; check fires 2026-11-16T18:00:00+00:00
rm -f "$NH/sl/config.json"
bad_stdin() { nudge 2026-11-17T15:20:00+00:00 'not json at all' | jq -e .systemMessage >/dev/null; }
check bad_stdin                                                 # odd stdin degrades to the default event
chan() { TZ=UTC KAIZEN_TEST_MODE=1 KAIZEN_NOW="$1" HOPLY_CONFIG_DIR="$NH/hoply" SELF_LEARN_HOME="$NH/sl" python3 "$NUDGE" --channel notified; }
check chan 2026-11-18T15:30:00+00:00; check test -f "$NH/sl/hoply-day/2026-11-18.notified"
not_chan() { ! chan "$@"; }
check not_chan 2026-11-18T16:00:00+00:00                        # notified once
check not_chan 2026-11-19T19:00:00+00:00                        # 21:00 Kyiv: too late for a desktop notification
check fires 2026-11-18T16:00:00+00:00                           # the hook channel keeps its own stamp

# ---- 10d. the notify script, osascript/notify-send stubbed ----
mkdir -p "$NH/scripts"; cp "$NUDGE" "$ROOT/templates/hoply-day-notify.sh" "$NH/scripts/"
notify() { TZ=UTC KAIZEN_TEST_MODE=1 KAIZEN_NOW="$1" HOPLY_CONFIG_DIR="$NH/hoply" SELF_LEARN_HOME="$NH/sl" bash "$NH/scripts/hoply-day-notify.sh" --plugin; }
check notify 2026-11-20T15:30:00+00:00
check grep -q 'display notification "Your day is ready: open Claude Code and type /kaizen:hoply-day" with title "Hoply"' "$STUB_LOG/osascript.log"
check notify 2026-11-20T15:45:00+00:00
check test "$(grep -c 'display notification' "$STUB_LOG/osascript.log")" = "1"

# ---- 10e. install-entry: recommended set, picked skills, Hoply token, no claude ----
TOKEN="hpt_0123456789abcdefghijABCDEFGHIJklmnopqrstuvw"
mode_of() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
entry() { local h="$1"; shift; mkdir -p "$h/workspace"
  HOME="$h" CLAUDE_CONFIG_DIR="$h/.claude" SELF_LEARN_HOME="$h/.claude/self-learn" bash "$ROOT/install-entry.sh" --workspace "$h/workspace" "$@"; }
H5="$T/home5"; : > "$STUB_LOG/claude.log"; rm -f "$STUB_LOG"/mkt-kaizen "$STUB_LOG"/plugin-kaizen "$STUB_LOG"/mcp-hoply
printf '%s\n' y "" | entry "$H5" --ask > "$T/entry-y.log" 2>&1; check test "$?" = 0
check grep -q '^plugin marketplace add Moriarty33/jb-kaizen' "$STUB_LOG/claude.log"
check grep -q '^plugin install kaizen@jb-kaizen --scope user' "$STUB_LOG/claude.log"
check jq -e '.schedule.enabled == true and .schedule.time == "03:07" and .hook == true and .aliases == true and .hoply.reminder == true' "$H5/.claude/self-learn/config.json"
check test ! -d "$H5/.claude/skills/hoply-day"                  # the plugin delivers the skills
check test ! -d "$H5/.config/hoply"                             # Enter skipped Hoply: nothing written
if ! grep -q 'mcp add-json' "$STUB_LOG/claude.log"; then ok "skip adds no MCP server"; else fail "skip adds no MCP server"; fi
case "$(uname -s)" in
  Darwin) P5="$H5/Library/LaunchAgents/com.self-learn.hoply-day.plist"; check test -f "$P5"; check grep -q '<string>--plugin</string>' "$P5"
          check grep -q "bootstrap gui/.*com.self-learn.hoply-day.plist" "$STUB_LOG/launchctl.log"
          if command -v plutil >/dev/null 2>&1; then check plutil -lint "$P5"; fi ;;
  Linux)  check grep -q 'OnCalendar=Mon..Fri \*-\*-\* 17:15:00 Europe/Kyiv' "$H5/.config/systemd/user/self-learn-hoply-day.timer" ;;
esac
check test -f "$H5/.claude/self-learn/scripts/hoply-day-nudge.py"
n_before="$(grep -c '^plugin install' "$STUB_LOG/claude.log" || true)"
check entry "$H5" --yes                                         # re-run: plugin already there, saved answers kept
check test "$(grep -c '^plugin install' "$STUB_LOG/claude.log" || true)" = "$n_before"

printf '%s\n' "$TOKEN" | entry "$H5" --hoply --hoply-token-stdin --hoply-url http://localhost:3000/mcp > "$T/entry-hoply.log" 2>&1; check test "$?" = 0
check test "$(mode_of "$H5/.config/hoply/token")" = "600"
check test "$(mode_of "$H5/.config/hoply")" = "700"; check test "$(mode_of "$H5/.config/hoply/headers.sh")" = "700"
check test "$(bash "$H5/.config/hoply/headers.sh" | jq -r .Authorization)" = "Bearer $TOKEN"
check grep -qF "mcp add-json hoply {\"type\":\"http\",\"url\":\"http://localhost:3000/mcp\",\"headersHelper\":\"$H5/.config/hoply/headers.sh\"} --scope user" "$STUB_LOG/claude.log"
check jq -e '.hoply.url == "http://localhost:3000/mcp" and .hoply.connected == true and .hoply.reminder == true' "$H5/.claude/self-learn/config.json"
if grep -rqF "$TOKEN" "$STUB_LOG" "$T/entry-hoply.log" "$H5/.claude"; then fail "the token leaked outside ~/.config/hoply"; else ok "the token stays in ~/.config/hoply"; fi
bad_token() { ! echo "hpt_short" | entry "$T/home5b" --hoply --hoply-token-stdin >/dev/null 2>&1 && [ ! -e "$T/home5b/.config/hoply" ]; }
check bad_token
no_claude() { local out; out="$(CLAUDE_BIN="$T/nowhere/claude" entry "$T/home5c" --yes 2>&1)" && return 1; grep -q 'Claude Code is not installed' <<<"$out"; }
check no_claude; check test ! -d "$T/home5c/.claude"

H6="$T/home6"; mkdir -p "$H6/.claude/skills/commit"; printf -- '---\nname: commit\n---\nmine\n' > "$H6/.claude/skills/commit/SKILL.md"
printf '%s\n' n "nope, github ,/kaizen:hoply-day,commit" "" | entry "$H6" --ask > "$T/entry-n.log" 2>&1; check test "$?" = 0
check grep -q 'unknown skill: nope' "$T/entry-n.log"
check test -f "$H6/.claude/skills/github/SKILL.md"; check test -f "$H6/.claude/skills/hoply-day/SKILL.md"
check grep -q mine "$H6/.claude/skills/commit/SKILL.md"         # a person's own /commit is never overwritten
check test ! -d "$H6/.claude/skills/self-learn"
check jq -e '.skills == ["github","hoply-day","commit"] and .schedule.enabled == false and .hoply.reminder == true' "$H6/.claude/self-learn/config.json"
check jq -e '[.hooks.SessionStart[].hooks[].command, .hooks.UserPromptSubmit[].hooks[].command] | map(select(test("hoply-day-nudge"))) | length == 2' "$H6/.claude/settings.json"
check test -f "$H6/.claude/hooks/hoply-day-nudge.py"
uninstall6() { HOME="$H6" CLAUDE_CONFIG_DIR="$H6/.claude" SELF_LEARN_HOME="$H6/.claude/self-learn" bash "$ROOT/uninstall.sh" "$@"; }
mkdir -p "$H6/.config/hoply"; echo x > "$H6/.config/hoply/token"; : > "$STUB_LOG/claude.log"
check uninstall6 --hoply
check test ! -d "$H6/.claude/skills/hoply-day"; check test ! -d "$H6/.claude/skills/github"; check grep -q mine "$H6/.claude/skills/commit/SKILL.md"
check test ! -f "$H6/.claude/hooks/hoply-day-nudge.py"; check test ! -d "$H6/.config/hoply"
check jq -e '.hooks == null' "$H6/.claude/settings.json"
check grep -q '^mcp remove hoply --scope user' "$STUB_LOG/claude.log"

# ---- 10e2. a refused `claude mcp add-json` fails the run and never reads as connected ----
touch "$STUB_LOG/fail-add-json"
for mode in --hoply-token-stdin --ask; do
  H7="$T/home7$mode"; rc7=0
  out7="$(printf '%s\n' "$TOKEN" | entry "$H7" --hoply "$mode" 2>&1)" || rc7=$?
  check test "$rc7" -ne 0
  if grep -qi 'connected' <<<"$out7"; then fail "add-json refused ($mode): output claims connected"; else ok "add-json refused ($mode): not reported connected"; fi
  not_connected7() { ! jq -e '.hoply.connected == true' "$H7/.claude/self-learn/config.json" >/dev/null 2>&1; }
  check not_connected7
done
rm -f "$STUB_LOG/fail-add-json"

# ---- 10e3. a narrower pick moves only skills an earlier pick installed, learned state intact ----
LP="references/learned-patterns.md"
H8="$T/home8"; printf '%s\n' n "self-learn,commit" "" | entry "$H8" --ask > "$T/entry-h8a.log" 2>&1
echo "LEARNED-MARK" >> "$H8/.claude/skills/self-learn/$LP"
printf '%s\n' n "commit" "" | entry "$H8" --ask > "$T/entry-h8b.log" 2>&1; check test "$?" = 0
check test ! -d "$H8/.claude/skills/self-learn"
backed_up() { grep -q LEARNED-MARK "$(ls -d "$H8"/.claude/kaizen-backups/skills/self-learn.bak-* | head -1)/$LP"; }
check backed_up
check bash -c '! ls -d "$1"/.claude/skills/*.bak-* >/dev/null 2>&1' _ "$H8"   # never a second loadable copy under skills/
H9="$T/home9"; mkdir -p "$H9/workspace"
HOME="$H9" CLAUDE_CONFIG_DIR="$H9/.claude" SELF_LEARN_HOME="$H9/.claude/self-learn" bash "$ROOT/install.sh" --yes --workspace "$H9/workspace" > "$T/h9.log" 2>&1
echo "LEARNED-MARK" >> "$H9/.claude/skills/self-learn/$LP"
printf '%s\n' n "commit" "" | entry "$H9" --ask > "$T/entry-h9.log" 2>&1
check grep -q LEARNED-MARK "$H9/.claude/skills/self-learn/$LP"   # no earlier pick named it: left in place

# ---- 10e4. systemd timer falls back to Europe/Kiev on old tzdata ----
tz_fallback() { local zi="$T/zi"; mkdir -p "$zi/Europe"; touch "$zi/Europe/Kiev"
  ( SRC="$ROOT"; PLUGIN_MODE=0; SL_HOME="$T/x"; HOPLY_TZ=""; . "$ROOT/lib/install-reminder.sh"
    TZDIR="$zi" reminder_render "$ROOT/templates/hoply-day.timer" "$T/kiev.timer" )
  grep -q '17:15:00 Europe/Kiev$' "$T/kiev.timer"; }
check tz_fallback

# ---- 10f. npm package: only the whitelisted tree ----
if command -v npm >/dev/null 2>&1; then
  npm pack "$ROOT/npm" --dry-run --json > "$T/npm-pack.json" 2>"$T/npm-pack.err" || true
  check jq -e '[.[0].files[].path] | (index("bin/jb-kaizen.js") != null) and (index("dist/install-entry.sh") != null) and (index("dist/skills/hoply-day/SKILL.md") != null) and (index("dist/.claude-plugin/plugin.json") != null)' "$T/npm-pack.json"
  check jq -e '[.[0].files[].path | select(test("^dist/(tests|docs|vscode)/|[.]bak-|^stage[.]js$"))] | length == 0' "$T/npm-pack.json"
  check test ! -d "$ROOT/npm/dist"                              # postpack cleaned up
fi
