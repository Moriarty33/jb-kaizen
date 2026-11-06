#!/usr/bin/env bash
# smoke.sh - end-to-end check of the extension in a throwaway HOME.
# Installs into a temp dir, then exercises every script against a synthetic workspace,
# a synthetic transcript store and a local bare "private remote". No network, no claude.
#
#   bash tests/smoke.sh          (exit 0 = all green)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export SELF_LEARN_HOME="$CLAUDE_CONFIG_DIR/self-learn"
unset SELF_LEARN_ROOTS SELF_LEARN_PROJECTS
mkdir -p "$HOME"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$*"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$*"; }
check() { if "$@" >/dev/null 2>&1; then ok "$*"; else fail "$*"; fi; }
gitc() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
. "$ROOT/tests/stubs.sh"

# ---- 0. syntax ----
for f in "$ROOT"/install.sh "$ROOT"/uninstall.sh "$ROOT"/lib/*.sh "$ROOT"/templates/*.sh "$ROOT"/skills/*/scripts/*.sh "$ROOT"/vscode/*.sh; do
  check bash -n "$f"
done
check python3 -m py_compile "$ROOT/hooks/skill-router.py"
check jq -e . "$ROOT/templates/routing-map.json"
check jq -e . "$ROOT/templates/night-guard-settings.json"

# ---- 0b. plugin manifests, hooks.json, setup skill, bootstrap syntax ----
VER="$(cat "$ROOT/VERSION")"; for m in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do check jq -e . "$ROOT/$m"; done
check jq -e --arg v "$VER" '.name=="kaizen" and .version==$v and (.repository|length>0)' "$ROOT/.claude-plugin/plugin.json"
MKT="$ROOT/.claude-plugin/marketplace.json"
check jq -e --arg v "$VER" '.name=="jb-kaizen"' "$MKT"
check jq -e '.owner.name|length>0' "$MKT"
check jq -e 'has("version")|not' "$MKT"          # the plugin entry owns the version; a root copy drifts
check jq -e '.plugins|length==1' "$MKT"
check jq -e '.plugins[0].name=="kaizen"' "$MKT"
check jq -e '.plugins[0].source=="./"' "$MKT"
check jq -e --arg v "$VER" '.plugins[0].version==$v' "$MKT"
HK="$ROOT/hooks/hooks.json"
check jq -e '.hooks.UserPromptSubmit[0].hooks[0].type=="command"' "$HK"
check jq -e '.hooks.UserPromptSubmit[0].hooks[0].command|test("CLAUDE_PLUGIN_ROOT")' "$HK"
check jq -e '.hooks.UserPromptSubmit[0].hooks[0].command|test("hooks/skill-router[.]py")' "$HK"
# every skill's frontmatter name must equal its directory (the spec requires it; renames break it silently)
skill_name_matches_dir() { for d in "$ROOT"/skills/*/; do n="$(basename "$d")"; grep -qx "name: $n" "$d/SKILL.md" || return 1; done; }
check skill_name_matches_dir
check test -f "$ROOT/skills/setup/SKILL.md"; check grep -q -- '--plugin --yes' "$ROOT/skills/setup/SKILL.md"; check bash -n "$ROOT/bootstrap.sh"; check test -x "$ROOT/bootstrap.sh"
check grep -q 'JB Kaizen' "$ROOT/skills/setup/SKILL.md"   # install.sh:157 prunes a stale ~/.claude/skills/setup only by this marker

# ---- 1. synthetic workspace: two repos, one with two branches ----
WS="$HOME/workspace"; mkdir -p "$WS"
for r in alpha beta; do
  mkdir -p "$WS/$r"; gitc -C "$WS/$r" init -q -b main
  for i in 1 2 3; do echo "$i" > "$WS/$r/f$i.txt"; gitc -C "$WS/$r" add .; gitc -C "$WS/$r" commit -qm "$r commit $i"; done
done
gitc -C "$WS/alpha" checkout -qb feature; echo x > "$WS/alpha/feat.txt"; gitc -C "$WS/alpha" add .; gitc -C "$WS/alpha" commit -qm "feature work"
gitc -C "$WS/alpha" checkout -q main
# a fake global agent + a pre-existing settings.json with an unrelated hook
mkdir -p "$CLAUDE_CONFIG_DIR/agents"
printf -- '---\nname: reviewer\n---\nReview carefully.\n' > "$CLAUDE_CONFIG_DIR/agents/reviewer.md"
echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"echo other"}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"

# ---- 2. install (twice: second must be a no-op) ----
check bash "$ROOT/install.sh" --workspace "$WS" --no-hook --dry-run
check bash "$ROOT/install.sh" --workspace "$WS"
check test -f "$CLAUDE_CONFIG_DIR/skills/self-learn/SKILL.md"
check test -f "$CLAUDE_CONFIG_DIR/skills/self-learn/scripts/paginate.sh"
check test -f "$CLAUDE_CONFIG_DIR/skills/model-balance/SKILL.md"
check test -f "$CLAUDE_CONFIG_DIR/skills/loop-audit/SKILL.md"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/loop-contract"
check bash "$ROOT/install.sh" --workspace "$WS"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/loop-contract"
check test -f "$CLAUDE_CONFIG_DIR/lib/claude-retry.sh"
check test -f "$CLAUDE_CONFIG_DIR/hooks/skill-router.py"
check test -f "$CLAUDE_CONFIG_DIR/night-guard-settings.json"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/setup"  # plugin-only: it needs CLAUDE_PLUGIN_ROOT
mkdir -p "$CLAUDE_CONFIG_DIR/skills/setup"; printf -- '---\nname: setup\n---\nmine\n' > "$CLAUDE_CONFIG_DIR/skills/setup/SKILL.md"
check bash "$ROOT/install.sh" --yes --workspace "$WS"
check grep -q mine "$CLAUDE_CONFIG_DIR/skills/setup/SKILL.md"   # a user's own /setup survives the rename prune
rm -rf "$CLAUDE_CONFIG_DIR/skills/setup"
. "$ROOT/tests/alias-checks.sh"
for p in state.json registry.json pagination.json versions.json scripts/nightly-run.sh nightly-prompt.txt routing/routing-map.json routing/intent-lexicon.md .gitignore; do
  check test -f "$SELF_LEARN_HOME/$p"
done
check jq -e '[.hooks.UserPromptSubmit[].hooks[].command] | (index("echo other") != null) and (map(test("skill-router")) | any)' "$CLAUDE_CONFIG_DIR/settings.json"
check test "$(jq -r '.repos | length' "$SELF_LEARN_HOME/registry.json")" = "2"
before="$(find "$CLAUDE_CONFIG_DIR" -name '*.bak-*' | wc -l | tr -d ' ')"
check bash "$ROOT/install.sh" --workspace "$WS"
after="$(find "$CLAUDE_CONFIG_DIR" -name '*.bak-*' | wc -l | tr -d ' ')"
check test "$before" = "$after"   # idempotent: no new backups on an unchanged re-install
check test "$(jq '[.hooks.UserPromptSubmit[].hooks[].command | select(test("skill-router"))] | length' "$CLAUDE_CONFIG_DIR/settings.json")" = "1"

# ---- 2a. routing map migration: a stale loop-contract entry is renamed on re-install ----
RM="$SELF_LEARN_HOME/routing/routing-map.json"
cp "$RM" "$RM.seeded"                      # section 6 needs the real map back
echo '{"loop-contract":{"triggers":["x"]}}' > "$RM"
check bash "$ROOT/install.sh" --workspace "$WS"
check grep -q loop-audit "$RM"
check test "$(grep -c loop-contract "$RM")" = "0"
mv "$RM.seeded" "$RM"

S="$CLAUDE_CONFIG_DIR/skills/self-learn/scripts"

# ---- 2b. wizard: piped answers, saved config, silent re-run, toggling a repo ----
# Answer order (config exists): keep? deps? roots toggle hook nightly [time] remote launcher graphify-watch proceed
CFG="$SELF_LEARN_HOME/config.json"
check test -f "$CFG"
check test "$(jq -r '.roots[0]' "$CFG")" = "$WS"
printf '%s\n' n n "" "" y y 04:30 "" n n y > "$T/ans"          # dry-run: nightly at 04:30 renders, nothing saved
out="$(bash "$ROOT/install.sh" --wizard --dry-run < "$T/ans")"
check grep -q 'nightly job at 04:30' <<<"$out"
check grep -q '1/7  Dependencies' <<<"$out"
check test "$(jq -r '.schedule.enabled' "$CFG")" = "false"
printf '%s\n' n n "" 2 y n "" n n y > "$T/ans"                # real: repo #2 (beta) off, hook on, no nightly
check bash "$ROOT/install.sh" --wizard < "$T/ans"
check test "$(jq -r '.disabledRepos[0]' "$CFG")" = "$WS/beta"
check test "$(jq -r '.repos[] | select(.name=="beta") | .enabled' "$SELF_LEARN_HOME/registry.json")" = "false"
check test "$(jq -r '.repos[] | select(.name=="alpha") | .enabled' "$SELF_LEARN_HOME/registry.json")" = "true"
out="$(bash "$ROOT/install.sh" < /dev/null)"                    # no flags, no terminal: silent, from the saved config
if grep -q 'Setup wizard' <<<"$out"; then fail "silent re-run asked questions"; else ok "silent re-run from config.json"; fi
check test "$(jq -r '.repos[] | select(.name=="beta") | .enabled' "$SELF_LEARN_HOME/registry.json")" = "false"
printf '%s\n' n n "" 2 y n "" n n y > "$T/ans"                # wizard again: toggle beta back on
check bash "$ROOT/install.sh" --wizard < "$T/ans"
check test "$(jq -r '.disabledRepos | length' "$CFG")" = "0"
check test "$(jq -r '.repos[] | select(.name=="beta") | .enabled' "$SELF_LEARN_HOME/registry.json")" = "true"
printf '%s\n' y > "$T/ans"                                     # "keep it and just upgrade" short-circuits the questions
out="$(bash "$ROOT/install.sh" --wizard < "$T/ans")"
if grep -q '2/7' <<<"$out"; then fail "keep-config still asked the questions"; else ok "keep saved config"; fi
check bash "$ROOT/install.sh" --yes --no-hook                   # flags beat the saved config and are remembered
check test "$(jq -r '.hook' "$CFG")" = "false"
check bash "$ROOT/install.sh" --yes
check test "$(jq -r '.hook' "$CFG")" = "false"
check bash "$ROOT/install.sh" --yes --hook
check test "$(jq -r '.hook' "$CFG")" = "true"
check bash "$ROOT/install.sh" --yes --workspace "$WS,$HOME/nowhere"   # several roots; a missing one only warns
check test "$(jq -r '.roots | length' "$CFG")" = "2"
check bash "$ROOT/install.sh" --yes --workspace "$WS"

# ---- 2c. VS Code companions through a fake `code` CLI ----
mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\necho "$@" >> "%s"\n' "$T/code.log" > "$T/bin/code"; chmod +x "$T/bin/code"
check env PATH="$T/bin:$PATH" bash "$ROOT/install.sh" --yes --vscode all
check grep -q -- '--install-extension .*claude-launcher-[0-9.]*\.vsix --force' "$T/code.log"
check grep -q -- 'graphify-watch-[0-9.]*\.vsix' "$T/code.log"
check test "$(jq -r '.vscode.graphifyWatch' "$CFG")" = "true"
mkdir -p "$T/nobin"                                             # a PATH without `code`: remembered, warned, not fatal
for t in bash git jq python3 sed grep find sort paste tr awk cat cp cmp mkdir basename dirname date head tail wc mktemp mv touch rm chmod id uname env cut ls; do
  p="$(command -v "$t" 2>/dev/null || true)"; [ -n "$p" ] && ln -sf "$p" "$T/nobin/$t"
done
out="$(PATH="$T/nobin" bash "$ROOT/install.sh" --yes)"
check grep -q 'code CLI not found' <<<"$out"
check bash "$ROOT/install.sh" --yes --vscode none
check test "$(jq -r '.vscode.claudeLauncher' "$CFG")" = "false"
for e in claude-launcher graphify-watch; do
  check test -f "$ROOT/vscode/$e/$e-$(jq -r .version "$ROOT/vscode/$e/package.json").vsix"
done

# ---- 2d. discover.sh: --list touches nothing; no args -> the roots saved in the registry ----
check test "$(bash "$S/discover.sh" --list "$WS" | wc -l | tr -d ' ')" = "2"
SELF_LEARN_HOME="$T/sl-list" bash "$S/discover.sh" --list "$WS" >/dev/null
check test ! -e "$T/sl-list"
mkdir -p "$HOME/other/gamma"; gitc -C "$HOME/other/gamma" init -q -b main
echo 1 > "$HOME/other/gamma/f"; gitc -C "$HOME/other/gamma" add .; gitc -C "$HOME/other/gamma" commit -qm gamma
mkdir -p "$T/sl-roots"; printf '{"roots":["%s"],"repos":{}}\n' "$HOME/other" > "$T/sl-roots/registry.json"
check grep -q "under \[$HOME/other\], 1 newly registered" <<<"$(SELF_LEARN_HOME="$T/sl-roots" bash "$S/discover.sh")"

# ---- 2e-2i. plugin mode, sl_skill_dir resolution, bootstrap.sh, plugin-cache inventory/snapshot/model-balance ----
. "$ROOT/tests/plugin-checks.sh"

# ---- 3. state / paginate / advance (two-phase cursors, cross-branch dedup) ----
check bash "$S/state.sh" status
out="$(bash "$S/paginate.sh" --repo "$WS/alpha" 40 200)"
check test "$(jq '.totalCommits' <<<"$out")" = "4"                 # 3 on main + 1 feature-only
check test "$(jq '[.batches[].commits[].hash] | length' <<<"$out")" = "4"   # no commit listed twice across branches
check test "$(jq '[.batches[].commits[].hash] | unique | length' <<<"$out")" = "4"
check test "$(bash "$S/state.sh" status | jq '.pendingBatches')" = "1"
check bash "$S/advance.sh"
check test "$(bash "$S/paginate.sh" --repo "$WS/alpha" 40 200 | jq '.totalCommits')" = "0"   # drained
echo new > "$WS/alpha/new.txt"; gitc -C "$WS/alpha" add .; gitc -C "$WS/alpha" commit -qm "one more"
check test "$(bash "$S/paginate.sh" --repo "$WS/alpha" 40 200 | jq '.totalCommits')" = "1"   # resumes exactly
check bash "$S/advance.sh"
check test "$(bash "$S/pr-paginate.sh" --repo "$WS/beta" | jq -r '.skipped')" = "not a github remote"
check bash "$S/register.sh" "$WS/beta" beta-renamed
check test "$(jq -r '.repos[] | select(.name=="beta-renamed") | .enabled' "$SELF_LEARN_HOME/registry.json")" = "true"

# ---- 4. inventory / snapshot / rollback source ----
cd "$WS/alpha"
inv="$(bash "$S/inventory.sh")"
check test "$(jq -r '.[] | select(.id=="global:agent:reviewer") | .status' <<<"$inv")" = "new"
check test "$(jq -r '.[] | select(.id=="global:skill:self-learn") | .type' <<<"$inv")" = "skill"
check bash "$S/snapshot.sh" global:agent:reviewer minor
check test "$(jq -r '.items["global:agent:reviewer"].version' "$SELF_LEARN_HOME/versions.json")" = "0.1.0"
check test -f "$SELF_LEARN_HOME/snapshots/global_agent_reviewer/0.1.0/reviewer.md"
check test "$(bash "$S/inventory.sh" | jq -r '.[] | select(.id=="global:agent:reviewer") | .status')" = "unchanged"
echo "Also check tests." >> "$CLAUDE_CONFIG_DIR/agents/reviewer.md"
check test "$(bash "$S/inventory.sh" | jq -r '.[] | select(.id=="global:agent:reviewer") | .status')" = "changed"

# ---- 5. sessions / corpus / memory on a synthetic transcript store ----
P="$CLAUDE_CONFIG_DIR/projects"
enc="$(printf '%s' "$WS/alpha" | sed 's|[/.]|-|g')"
mkdir -p "$P/$enc/sub1/subagents" "$P/$enc/memory" "$P/engine1"
echo '{"type":"user","message":"hello"}' > "$P/$enc/s1.jsonl"
echo '{"type":"tool_result","is_error":true,"content":"fatal: not a git repository"}' > "$P/$enc/sub1/subagents/agent-1.jsonl"
echo '{"type":"user","message":"NON-INTERACTIVE RUN CONTRACT nightly self-learn"}' > "$P/engine1.jsonl"
mkdir -p "$P/engine1/subagents"; echo '{"type":"x","content":"fatal: engine echo"}' > "$P/engine1/subagents/a.jsonl"
cat > "$P/$enc/memory/MEMORY.md" <<'EOF'
# Memory
- feedback_always_run_tests.md
EOF
echo "Always run tests before review." > "$P/$enc/memory/feedback_always_run_tests.md"
printf -- '---\nnode_type: memory\ntype: feedback\n---\nUse pending reviews.\n' > "$P/$enc/memory/use-pending-reviews.md"
check test "$(bash "$S/sessions.sh" --dir "$WS/alpha" | jq '.sessions | length')" = "1"
check bash "$S/sessions.sh" --all --advance
check test "$(bash "$S/sessions.sh" --dir "$WS/alpha" | jq '.sessions | length')" = "0"
corpus="$(SELF_LEARN_PROJECTS="$P" bash "$S/corpus.sh" --out "$T/corpus.txt")"
check test "$(wc -l < "$T/corpus.txt" | tr -d ' ')" = "2"          # s1 + nested subagent; engine + its child excluded
check grep -q 'canary:      2/2' <<<"$corpus"
check test "$(xargs grep -lF 'fatal:' < "$T/corpus.txt" | wc -l | tr -d ' ')" = "1"
scan="$(bash "$S/memory.sh" scan "$P/$enc/memory")"
check test "$(jq -r '.[] | select(.file=="use-pending-reviews.md") | .class' <<<"$scan")" = "feedback"
check test "$(jq -r '.[] | select(.file=="use-pending-reviews.md") | .indexed' <<<"$scan")" = "false"
check test "$(jq -r '.[] | select(.file=="feedback_always_run_tests.md") | .status' <<<"$scan")" = "new"
bk="$(bash "$S/memory.sh" backup "$P/$enc/memory")"
check test -f "$bk/MEMORY.md"
check bash "$S/memory.sh" advance "$P/$enc/memory"
check test "$(bash "$S/memory.sh" scan "$P/$enc/memory" | jq -r '.[] | select(.file=="feedback_always_run_tests.md") | .status')" = "unchanged"
check bash "$S/state.sh" bump-epoch
check test "$(jq -r .epoch "$SELF_LEARN_HOME/state.json")" = "1"

# ---- 6. routing hook ----
hook="$CLAUDE_CONFIG_DIR/hooks/skill-router.py"
check grep -q 'self-learn' <<<"$(echo '{"prompt":"please learn from the last sessions"}' | python3 "$hook")"
check grep -q 'self-learn' <<<"$(echo '{"prompt":"solf learn now"}' | python3 "$hook")"
check test -z "$(echo '{"prompt":"/self-learn status"}' | python3 "$hook")"
check test -z "$(echo '{"prompt":"thanks"}' | python3 "$hook")"
check test -z "$(echo 'not json' | python3 "$hook")"

# ---- 7. claude-retry with a fake claude: fail once, then succeed ----
FAKE="$T/fake-claude"; cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
n="$(cat "$FAKE_STATE" 2>/dev/null || echo 0)"; n=$((n+1)); echo "$n" > "$FAKE_STATE"
[ "$n" -ge 2 ] && { echo "done"; exit 0; }
echo "transient error" >&2; exit 1
EOF
chmod +x "$FAKE"; export FAKE_STATE="$T/fake.state"
. "$CLAUDE_CONFIG_DIR/lib/claude-retry.sh"
r="$(CLAUDE_BIN="$FAKE" CLAUDE_RETRY_BACKOFF=1 claude_retry "prompt" 2>/dev/null)"
check grep -q 'RETRY-WRAPPER: OK after 2 attempt' <<<"$r"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
r="$(CLAUDE_BIN="$FAKE" CLAUDE_RETRY_TIMEOUT=2 CLAUDE_RETRY_MAX=1 claude_retry "prompt" 2>/dev/null || true)"
check grep -q 'timeout - attempt 1/1' <<<"$r"
cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
echo "Not logged in" >&2; exit 1
EOF
r="$(CLAUDE_BIN="$FAKE" claude_retry "prompt" 2>/dev/null || true)"
check grep -q 'AUTH_FAIL' <<<"$r"

# ---- 8. sync: init to a local bare remote, then prove pull-before-push ----
BARE="$T/remote.git"; git init -q --bare "$BARE"; git -C "$BARE" symbolic-ref HEAD refs/heads/main
check bash "$S/sync.sh" init "$BARE"
CLONE="$T/clone"; git clone -q "$BARE" "$CLONE"
echo "merged from a PR" > "$CLONE/README.md"; gitc -C "$CLONE" add .; gitc -C "$CLONE" commit -qm "remote change"; git -C "$CLONE" push -q
check bash "$S/state.sh" bump-epoch
check bash "$S/sync.sh"                                             # would be non-fast-forward without the rebase
check test -f "$SELF_LEARN_HOME/README.md"
check test "$(git -C "$BARE" log --oneline main | wc -l | tr -d ' ')" = "3"
check grep -q 'remote already up to date' <<<"$(bash "$S/sync.sh")"

# ---- 9. nightly-run refuses a missing workspace; uninstall cleans up ----
r="$(SELF_LEARN_WORKSPACE="$T/nope" bash "$SELF_LEARN_HOME/scripts/nightly-run.sh" || true)"
check grep -q 'workspace' "$(ls -t "$SELF_LEARN_HOME"/logs/nightly-*.log | head -1)"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/loop-contract"
mkdir -p "$CLAUDE_CONFIG_DIR/skills/setup"; printf -- '---\nname: setup\n---\nmine\n' > "$CLAUDE_CONFIG_DIR/skills/setup/SKILL.md"
check bash "$ROOT/install.sh" --aliases --yes --workspace "$WS"
check test -d "$CLAUDE_CONFIG_DIR/skills/kz-setup"   # armed, so the post-uninstall check below is not vacuous
check jq -e '.aliases == true' "$SELF_LEARN_HOME/config.json"
check bash "$ROOT/uninstall.sh"
check grep -q mine "$CLAUDE_CONFIG_DIR/skills/setup/SKILL.md"   # a user's own /setup survives uninstall too
rm -rf "$CLAUDE_CONFIG_DIR/skills/setup"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/loop-contract"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/self-learn"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/kz-setup"
check test -d "$SELF_LEARN_HOME"
check jq -e '[.hooks.UserPromptSubmit[].hooks[].command] == ["echo other"]' "$CLAUDE_CONFIG_DIR/settings.json"
check bash "$ROOT/uninstall.sh" --purge-store
check test ! -d "$SELF_LEARN_HOME"


# ---- 10. Hoply pairing, the one-line installer, bundled skills ----
. "$ROOT/tests/hoply-checks.sh"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
