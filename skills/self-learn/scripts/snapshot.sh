#!/usr/bin/env bash
# Snapshot an agent/skill BEFORE editing it, and bump its version in the manifest.
# This is the safety net: every change is reversible from snapshots/<id>/<version>.
#
# Usage: snapshot.sh <id> [major|minor|patch]   (default: patch)
#        id is the inventory id, e.g. "global:agent:reviewer"
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

ID="${1:?usage: snapshot.sh <id> [major|minor|patch]}"
BUMP="${2:-patch}"

row="$("$DIR/inventory.sh" | jq -c --arg id "$ID" '.[] | select(.id==$id)')"
if [ -n "$row" ]; then
  path="$(jq -r '.path' <<<"$row")"
  hash="$(jq -r '.hash' <<<"$row")"
  type="$(jq -r '.type' <<<"$row")"
else
  # Not an inventory item (inventory covers skills/agents only). Config files and store
  # state are edited more often than either, so accept an explicit path for them rather
  # than leaving those edits with no snapshot.
  # known store-owned ids resolve themselves; an explicit $3 / SL_SNAPSHOT_PATH still wins.
  case "$ID" in
    global:store:learned-patterns) known="$SL_HOME/learned-patterns.md" ;;
    global:config:claude-md)       known="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" ;;
    global:rules:*)                known="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rules/${ID#global:rules:}.md" ;;
    *)                             known="" ;;
  esac
  path="${3:-${SL_SNAPSHOT_PATH:-$known}}"
  [ -n "$path" ] && [ -e "$path" ] || {
    echo "unknown id: $ID (pass a path as \$3 or SL_SNAPSHOT_PATH to snapshot a non-inventory item)" >&2
    exit 1
  }
  if [ -d "$path" ]; then type=skill; else type=file; fi
  hash="$(sl_hash_path "$path" 2>/dev/null || shasum -a 256 "$path" 2>/dev/null | cut -d" " -f1)"
fi

cur="$(jq -r --arg id "$ID" '.items[$id].version // "0.0.0"' "$SL_VERS")"
IFS=. read -r MA MI PA <<<"$cur"
case "$BUMP" in
  major) MA=$((MA+1)); MI=0; PA=0 ;;
  minor) MI=$((MI+1)); PA=0 ;;
  *)     PA=$((PA+1)) ;;
esac
nv="$MA.$MI.$PA"

safe="$(printf '%s' "$ID" | tr '/:' '__')"
dest="$SL_SNAP/$safe/$nv"
mkdir -p "$dest"
if [ "$type" = skill ]; then cp -R "$path"/. "$dest"/; else cp "$path" "$dest"/; fi

jq --arg id "$ID" --arg v "$nv" --arg h "$hash" --arg p "$path" --arg d "$dest" '
  .items[$id] = {
    version:$v, hash:$h, path:$p, snapshot:$d, updatedAt:(now|todate),
    history: ((.items[$id].history // []) + [{version:$v,hash:$h,at:(now|todate),snapshot:$d}])
  }' "$SL_VERS" | sl_atomic_write "$SL_VERS"

echo "$ID -> v$nv  (snapshot: $dest)"
