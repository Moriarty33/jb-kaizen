#!/usr/bin/env bash
# model-balance: gather model/effort usage + config-routing sites into one report.
# READ-ONLY. Scope: ~/.claude + your workspace only (never personal folders).
# Add more job dirs to scan for model-flag sites via MODEL_BALANCE_EXTRA_DIRS="dir1 dir2".
# Usage: collect-stats.sh            -> human-readable report to stdout
#        collect-stats.sh --json OUT -> also write machine JSON to OUT
set -uo pipefail
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
JSON_OUT=""
[ "${1:-}" = "--json" ] && JSON_OUT="${2:-$C/skills/model-balance/stats.json}"

CC="$(npx ccusage@latest weekly --json 2>/dev/null)"

echo "############ MODEL-BALANCE STATS ############"
echo
echo "## 1. Spend distribution by model (ccusage, cost-equiv)"
echo "$CC" | jq -r '
  ([.weekly[].modelBreakdowns[]] | group_by(.modelName)
    | map({m:.[0].modelName, c:(map(.cost)|add)})) as $all
  | ([.weekly[].totalCost]|add) as $C
  | (.weekly[-1]) as $wk
  | ([$wk.totalCost]|add) as $WC
  | "  WEEK \($wk.period)  ($\(($WC*100|round)/100) total):"
    + ([$wk.modelBreakdowns[] | "\n    \(.modelName): $\((.cost*100|round)/100)  (\((.cost/$WC*1000|round)/10)%)"] | sort | join(""))
    + "\n  ALL-TIME  ($\(($C*100|round)/100) total):"
    + ([$all[] | "\n    \(.m): $\((.c*100|round)/100)  (\((.c/$C*1000|round)/10)%)"] | sort | join(""))
' 2>/dev/null || echo "  (ccusage unavailable)"

echo
echo "## 2. Top tier vs mid tier this week"
echo "$CC" | jq -r '
  (.weekly[-1].modelBreakdowns) as $w
  | (($w[]|select(.modelName|test("opus";"i")).cost) // 0) as $o
  | (($w[]|select(.modelName|test("sonnet";"i")).cost) // 0) as $s
  | (($w[]|select(.modelName|test("haiku";"i")).cost) // 0) as $h
  | "  opus $\(($o*100|round)/100)   sonnet $\(($s*100|round)/100)   haiku $\(($h*100|round)/100)"
  + "\n  -> opus on mechanical / well-specified work is the #1 waste; see the rubric."
' 2>/dev/null

echo
# No line in THIS file may contain the flag literal this section greps for (header or
# comment), or the live script matches itself; and snapshots/ holds historical copies of
# this file, which match the same way and multiply with every version. Both were reported
# as live routing sites (epoch 61: 7 lines printed, only 3 real). Keep the value pattern
# broad - narrowing it to a tier alternation silently drops real forms such as opusplan
# and default, which is the one direction this detector must never fail in.
echo "## 3. Explicit model-routing sites (LIVE only; snapshots excluded)"
# Kaizen's own plugin-cache skills too (not every third-party plugin's).
kaizen_dirs=()
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$C/lib/skill-dir.sh" ]; then . "$C/lib/skill-dir.sh"
elif [ -f "$DIR/../../../lib/skill-dir.sh" ]; then . "$DIR/../../../lib/skill-dir.sh"
fi
if command -v sl_kaizen_skill_dirs >/dev/null 2>&1; then
  while IFS= read -r d; do kaizen_dirs+=("$d"); done < <(sl_kaizen_skill_dirs)
fi
grep -rnE --include='*.sh' --exclude-dir=logs --exclude-dir=backups --exclude-dir=snapshots -e '--model[[:space:]=]+[a-z0-9-]+' \
  "$C/self-learn" "$C/lib" "$C/skills" \
  ${kaizen_dirs[@]+"${kaizen_dirs[@]}"} ${MODEL_BALANCE_EXTRA_DIRS:-} 2>/dev/null \
  | grep -vE '\.bak' | sed -E 's#^'"$C"'/#  <config>/#; s#^'"$HOME"'/#  ~/#' | head -40

echo
echo "## 4. Skill frontmatter model/effort pins"
grep -rnE '^(model|effort|reasoning|reasoningEffort):' "$C/skills"/*/SKILL.md \
  ${kaizen_dirs[@]+"${kaizen_dirs[@]/%//SKILL.md}"} 2>/dev/null \
  | sed -E 's#^'"$C"'/#  <config>/#; s#^'"$HOME"'/#  ~/#' | head -40
echo "  (agents/*.md declare NO model:/effort: - they inherit the invocation model; recommendations for them target the invocation site or add explicit frontmatter.)"

echo
echo "## 5. Workflow agent() model/effort choices (aggregate across recent scripts)"
grep -rhoE "(model|effort): ?'[a-z]+'" "$C/projects"/*/workflows/scripts/*.js 2>/dev/null \
  | tr -d "'" | sort | uniq -c | sort -rn | head -20
echo "  (counts show which tiers workflows actually pick - imbalance vs the rubric = a rebalance target.)"
echo
echo "############ END ############"

if [ -n "$JSON_OUT" ]; then
  echo "$CC" | jq -c '
    ([.weekly[].modelBreakdowns[]] | group_by(.modelName)
      | map({model:.[0].modelName, cost:(map(.cost)|add)})) as $all
    | ([.weekly[].totalCost]|add) as $C
    | (.weekly[-1]) as $wk | ([$wk.totalCost]|add) as $WC
    | {weekPeriod:$wk.period,
       weekByModel:[$wk.modelBreakdowns[]|{model:.modelName,cost:((.cost*100|round)/100),pctCost:((.cost/$WC*1000|round)/10)}]|sort_by(-.cost),
       allTimeByModel:[$all[]|{model:.model,cost:((.cost*100|round)/100),pctCost:((.cost/$C*1000|round)/10)}]|sort_by(-.cost)}' \
    > "$JSON_OUT.tmp" 2>/dev/null && [ -s "$JSON_OUT.tmp" ] && mv "$JSON_OUT.tmp" "$JSON_OUT" && echo "wrote $JSON_OUT" \
      || { rm -f "$JSON_OUT.tmp"; echo "  (ccusage unavailable - no JSON written)"; }
fi
exit 0
