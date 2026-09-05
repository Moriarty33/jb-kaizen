#!/usr/bin/env bash
# Commit pending batches: move each branch cursor forward and record processed
# hashes. Applies ALL per-repo pending files (or one, if a path is given).
# Run this ONLY after the analysis for the batch succeeded.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

apply_one() {
  local P="$1"
  [ -f "$P" ] || return 0
  local key; key="$(jq -r '.repo' "$P")"
  jq --arg k "$key" --slurpfile p "$P" '
    .repos[$k] = (.repos[$k] // {branches:{},seen:[]})
    | reduce $p[0].batches[] as $b (.;
        .repos[$k].branches[$b.branch] =
          ((.repos[$k].branches[$b.branch] // {}) + {lastHash:$b.newCursor, updatedAt:(now|todate)}))
    | .repos[$k].seen = ((.repos[$k].seen // []) + $p[0].newSeen | unique)
  ' "$SL_PAGI" | sl_atomic_write "$SL_PAGI"
  rm -f "$P"
  echo "advanced cursors for: $key"
}

if [ -n "${1:-}" ]; then
  apply_one "$1"
else
  shopt -s nullglob
  found=0
  for P in "$SL_PENDING_DIR"/*.json; do
    # Skip PR pending batches (pr-*.json) - those have .prs, not .batches, and are
    # consumed by pr-advance.sh. Feeding them here makes jq iterate over null and the
    # atomic write truncates pagination.json (the cursor store). Commit batches only.
    case "$(basename "$P")" in pr-*) continue ;; esac
    apply_one "$P"; found=1
  done
  [ "$found" -eq 0 ] && echo "nothing pending to advance"
fi
exit 0
