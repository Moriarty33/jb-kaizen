# shellcheck shell=bash
# shellcheck disable=SC2154  # harness variables come from smoke.sh
# Plugin-mode and plugin-cache checks, split out of smoke.sh to keep it under its line cap.
# Sourced from smoke.sh after sections 0-2d have set up $ROOT/$T/$WS/$S and the harness helpers.

# ---- 2e. plugin mode: nothing copied, nothing registered, store still built ----
H2="$T/home2"; mkdir -p "$H2/workspace"; cp -R "$WS"/. "$H2/workspace"/
plugin_install() { HOME="$H2" CLAUDE_CONFIG_DIR="$H2/.claude" SELF_LEARN_HOME="$H2/.claude/self-learn" \
  bash "$ROOT/install.sh" --plugin --yes --workspace "$H2/workspace" --no-schedule; }   # check takes an argv
no_clone_hook() { [ ! -f "$H2/.claude/settings.json" ] || ! grep -q skill-router "$H2/.claude/settings.json"; }
route() { echo "{\"prompt\":\"$1\"}" | python3 "$ROOT/hooks/skill-router.py"; }
plugin_install > "$T/plugin-install.log" 2>&1 || true; check plugin_install   # log: readable diagnosis
for s in self-learn model-balance loop-audit setup; do check test ! -d "$H2/.claude/skills/$s"; done   # plugin delivers the real skills
for a in kz-setup kz-learn kz-audit kz-balance; do check test -f "$H2/.claude/skills/$a/SKILL.md"; done   # aliases install in BOTH modes (SPEC A2)
check test ! -f "$H2/.claude/hooks/skill-router.py"; check no_clone_hook
for p in state.json registry.json config.json routing/routing-map.json scripts/nightly-run.sh; do check test -f "$H2/.claude/self-learn/$p"; done
check test -f "$H2/.claude/lib/skill-dir.sh"; check test "$(jq -r '.repos | length' "$H2/.claude/self-learn/registry.json")" = "2"
bak="$(find "$H2/.claude" -name '*.bak-*' | wc -l | tr -d ' ')"; check plugin_install
check test "$bak" = "$(find "$H2/.claude" -name '*.bak-*' | wc -l | tr -d ' ')"   # idempotent re-install
# U2: assert on the router's OUTPUT (it exits 0 even when broken) + a negative control; case 3 unsets SELF_LEARN_HOME, so the ~/.claude default must resolve in plugin mode too
check grep -q 'self-learn' <<<"$(SELF_LEARN_HOME="$H2/.claude/self-learn" route 'please learn from the last sessions')"
check test -z "$(SELF_LEARN_HOME="$H2/.claude/self-learn" route 'thanks')"
check grep -q 'self-learn' <<<"$(unset SELF_LEARN_HOME; HOME="$H2" route 'learn from the last sessions')"

# ---- 2f. sl_skill_dir resolution: env var, claude dir, newest cache, not found ----
FX="$T/fx"; FXK="$FX/cache/plugins/cache/m/kaizen"
mkdir -p "$FX/env-skill" "$FX/cfg/skills/self-learn" "$FX/none" "$FXK/1.0.0/skills/self-learn" "$FXK/1.9.0/skills/self-learn"
touch -t 200001010101 "$FXK/1.9.0/skills/self-learn"; touch -t 203001010101 "$FXK/1.0.0/skills/self-learn"  # newest by mtime, not by version
check bash -c 'set -euo pipefail; . "$1/lib/skill-dir.sh"; echo OK' _ "$ROOT"; . "$ROOT/lib/skill-dir.sh"
sd() { SELF_LEARN_SKILL_DIR="${2:-}" CLAUDE_CONFIG_DIR="$1" sl_skill_dir; }; sd_env() { [ "$(sd "$FX/cfg" "$FX/env-skill")" = "$FX/env-skill" ]; }
sd_cfg()   { [ "$(sd "$FX/cfg")" = "$FX/cfg/skills/self-learn" ]; }
sd_cache() { [ "$(sd "$FX/cache")" = "$FXK/1.0.0/skills/self-learn" ]; }; sd_none() { ! sd "$FX/none"; }
for f in sd_env sd_cfg sd_cache sd_none; do check "$f"; done

# ---- 2g. bootstrap.sh against a local clone (file://, so the real shallow fetch runs) ----
H3="$T/home3"; mkdir -p "$T/src" "$H3/workspace"; cp -R "$WS"/. "$H3/workspace"/
for p in install.sh install-entry.sh uninstall.sh bootstrap.sh VERSION .claude-plugin hooks lib skills templates; do cp -R "$ROOT/$p" "$T/src/"; done
gitc -C "$T/src" init -q -b main; gitc -C "$T/src" add -A; gitc -C "$T/src" commit -qm "bootstrap fixture"
bootstrap_run() { HOME="$H3" CLAUDE_CONFIG_DIR="$H3/.claude" SELF_LEARN_HOME="$H3/.claude/self-learn" \
  JB_KAIZEN_REPO="file://$T/src" JB_KAIZEN_DIR="$H3/.jb-kaizen" \
  bash "$ROOT/bootstrap.sh" --yes --workspace "$H3/workspace" --no-schedule --no-hook; }
bootstrap_run > "$T/bootstrap.log" 2>&1 || true; check bootstrap_run; check test -f "$H3/.jb-kaizen/install.sh"; check test -f "$H3/.claude/self-learn/state.json"
head3="$(git -C "$H3/.jb-kaizen" rev-parse HEAD)"; check bootstrap_run   # second run: fetch + reset,
check test "$head3" = "$(git -C "$H3/.jb-kaizen" rev-parse HEAD)"        # ... onto the same commit

# ---- 2h. a HOME that only ever saw the plugin cache: inventory, snapshot, model-balance ----
H4="$T/home4"; C4="$H4/.claude"; K4="$C4/plugins/cache/m/kaizen"; mkdir -p "$K4" "$H4/proj" "$T/bin"; gitc -C "$H4/proj" init -q -b main
for v in 1.0.0 1.1.0; do cp -R "$T/src" "$K4/$v"; done                  # two cached versions, one plugin
mkdir -p "$K4/1.1.0/skills/cache-skill"; printf -- '---\nname: cache-skill\nmodel: haiku\n---\nPinned in the cache.\n' > "$K4/1.1.0/skills/cache-skill/SKILL.md"
CCUSAGE='{"weekly":[{"period":"2026-W36","totalCost":3,"modelBreakdowns":[{"modelName":"opus","cost":2},{"modelName":"sonnet","cost":1}]}]}'   # ccusage stub: no network in a smoke run
printf '#!/usr/bin/env bash\necho %s\n' "'$CCUSAGE'" > "$T/bin/npx"; chmod +x "$T/bin/npx"
cache_run() { local rel="$1"; shift; ( cd "$H4/proj" && HOME="$H4" CLAUDE_CONFIG_DIR="$C4" SELF_LEARN_HOME="$C4/self-learn" PATH="$T/bin:$PATH" bash "$K4/1.1.0/skills/$rel" "$@" ); }
inv4() { cache_run self-learn/scripts/inventory.sh; }; snap4() { cache_run self-learn/scripts/snapshot.sh plugin:skill:self-learn; }
stats4() { cache_run model-balance/scripts/collect-stats.sh --json "$T/stats.json"; }
check test ! -f "$C4/lib/skill-dir.sh"; check inv4; check snap4          # no ~/.claude/lib to fall back on
check test -z "$(inv4 | jq -r '.[].id' | sort | uniq -d)"; check test "$(inv4 | jq -r '[.[]|select(.id=="plugin:skill:self-learn")]|length')" = "1"   # two versions, one row per skill
stats4 > "$T/stats.log" 2>&1 || true; check stats4; check test -s "$T/stats.json"
check grep -qE 'cache-skill/SKILL[.]md:[0-9]+:model: haiku' "$T/stats.log"   # section 4 scans the cache

# ---- 2i. collect-stats.sh --json with no ccusage on PATH: must not write an empty stats file ----
stats_nostub() { ( cd "$H4/proj" && HOME="$H4" CLAUDE_CONFIG_DIR="$C4" SELF_LEARN_HOME="$C4/self-learn" PATH=/usr/bin:/bin bash "$K4/1.1.0/skills/model-balance/scripts/collect-stats.sh" --json "$T/stats-nostub.json" ); }
check stats_nostub; check test ! -e "$T/stats-nostub.json"
