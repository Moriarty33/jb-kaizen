#!/usr/bin/env bash
# Discover every local git repo under the configured roots and merge them into
# the central registry. Idempotent: existing entries keep their config, new repos
# are added enabled-by-default. This is what makes "all my projects, including new
# ones" work - run it at the start of every self-learn run (and a new project on
# disk is picked up automatically the next time).
#
# Config lives centrally in the registry (in your private self-learn repo), NOT
# scattered into each project. Per-project settings are entries under .repos[key].
#
# Usage: discover.sh [--list] [root1 root2 ...]
#   roots:  args > SELF_LEARN_ROOTS (comma-separated) > registry.json .roots (what the
#           installer's wizard chose) > $HOME/workspace
#   --list: print the repo paths that would be registered and exit; touches nothing
#           (install.sh's wizard uses this to show what it found).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

LIST=0
[ "${1:-}" = "--list" ] && { LIST=1; shift; }

roots=()
if [ "$#" -gt 0 ]; then
  roots=("$@")
elif [ -n "${SELF_LEARN_ROOTS:-}" ]; then
  IFS=, read -r -a roots <<< "$SELF_LEARN_ROOTS"
elif [ -f "$SL_REGISTRY" ] && [ "$(jq -r '.roots | length' "$SL_REGISTRY" 2>/dev/null || echo 0)" -gt 0 ]; then
  while IFS= read -r r; do roots+=("$r"); done < <(jq -r '.roots[]' "$SL_REGISTRY")
else
  roots=("$HOME/workspace")
fi

if [ "$LIST" -eq 1 ]; then sl_find_repos "${roots[@]}"; exit 0; fi
sl_init

# Persist the roots in the registry so the set is reproducible across machines.
roots_json="$(printf '%s\n' "${roots[@]}" | jq -R . | jq -s .)"
jq --argjson r "$roots_json" '.roots = ($r | unique)' "$SL_REGISTRY" | sl_atomic_write "$SL_REGISTRY"

added=0; seen=0
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  # Canonical root (symlinks resolved) - the same one paginate.sh and register.sh derive, so a
  # repo reached through a symlink never gets a second registry entry and a second cursor.
  repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "$repo")"
  seen=$((seen+1))
  remote="$(git -C "$repo" remote get-url origin 2>/dev/null || echo "")"
  key="${remote:-$repo}"
  name="$(basename "$repo")"
  exists="$(jq -r --arg k "$key" '.repos[$k] // empty | length' "$SL_REGISTRY")"
  jq --arg k "$key" --arg n "$name" --arg p "$repo" --arg rm "$remote" '
    .repos[$k] = ((.repos[$k] // {enabled:true, config:{batch:40,maxTotal:200}, addedAt:(now|todate)})
      + {name:$n, path:$p, remote:$rm, lastSeenAt:(now|todate)})
  ' "$SL_REGISTRY" | sl_atomic_write "$SL_REGISTRY"
  [ -z "$exists" ] && added=$((added+1))
done < <(sl_find_repos "${roots[@]}")

echo "discovered: $seen repos under [${roots[*]}], $added newly registered"
jq -r '.repos | to_entries | map(select(.value.enabled)) | length as $n | "registry now holds \($n) enabled repos"' "$SL_REGISTRY"
