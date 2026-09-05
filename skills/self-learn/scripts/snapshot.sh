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
[ -z "$row" ] && { echo "unknown id: $ID" >&2; exit 1; }
path="$(jq -r '.path' <<<"$row")"
hash="$(jq -r '.hash' <<<"$row")"
type="$(jq -r '.type' <<<"$row")"

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
