#!/usr/bin/env bash
# Inventory every agent and skill (global + project) with a content hash, and
# tag each as new / changed / unchanged relative to the version manifest.
# Pure read - never mutates state. Output: JSON array.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
items="[]"

add() { # id scope type name path hash
  items="$(jq --arg id "$1" --arg sc "$2" --arg ty "$3" --arg nm "$4" --arg pa "$5" --arg ha "$6" \
    '. + [{id:$id,scope:$sc,type:$ty,name:$nm,path:$pa,hash:$ha}]' <<<"$items")"
}

# Global agents
for f in "$HOME"/.claude/agents/*.md; do
  [ -e "$f" ] || continue; n="$(basename "$f" .md)"
  add "global:agent:$n" global agent "$n" "$f" "$(sl_hash_file "$f")"
done
# Project tag namespaces project-scoped ids so two projects' same-named items
# (two projects each shipping a reviewer.md) do not collide on one id.
PROJ_TAG="$(basename "$PROJECT_ROOT")"
# Project agents (may be nested)
if [ -d "$PROJECT_ROOT/.claude/agents" ]; then
  while IFS= read -r f; do
    n="$(basename "$f" .md)"
    add "project:$PROJ_TAG:agent:$n" project agent "$n" "$f" "$(sl_hash_file "$f")"
  done < <(find "$PROJECT_ROOT/.claude/agents" -name '*.md')
fi
# Global skills
for d in "$HOME"/.claude/skills/*/; do
  [ -f "${d}SKILL.md" ] || continue; n="$(basename "$d")"
  add "global:skill:$n" global skill "$n" "${d%/}" "$(sl_hash_dir "$d")"
done
# Project skills
if [ -d "$PROJECT_ROOT/.claude/skills" ]; then
  for d in "$PROJECT_ROOT"/.claude/skills/*/; do
    [ -f "${d}SKILL.md" ] || continue; n="$(basename "$d")"
    add "project:$PROJ_TAG:skill:$n" project skill "$n" "${d%/}" "$(sl_hash_dir "$d")"
  done
fi

jq -n --argjson items "$items" --slurpfile v "$SL_VERS" '
  $items | map(. + {
    version: ($v[0].items[.id].version // null),
    status: (if   ($v[0].items[.id] == null)        then "new"
             elif ($v[0].items[.id].hash != .hash)  then "changed"
             else "unchanged" end)
  })'
