#!/usr/bin/env bash
# Commit pending PR batches: advance the historical PR cursor and merge the
# openSeen (open-PR last-seen-updatedAt) map. Run only after PR analysis succeeded.
# Applies all pending pr-*.json (or one, if a path is given).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

apply_one() {
  local P="$1"
  [ -f "$P" ] || return 0
  # Refuse a truncated/invalid batch: an empty or error-shaped pending file yields a
  # null .repo, which would inject a garbage "" repo key into pagination.json while
  # advancing nothing. Leave the file in place so the failure stays visible.
  if ! jq -e 'type == "object" and (.repo | type == "string") and (.repo | length > 0)' >/dev/null 2>&1 <"$P"; then
    echo "SKIP invalid PR batch (no .repo): $P" >&2
    return 0
  fi
  local key; key="$(jq -r '.repo' "$P")"
  jq --arg k "$key" --slurpfile p "$P" '
    .repos[$k] = (.repos[$k] // {})
    | .repos[$k].prs = (.repos[$k].prs // {cursor:0, openSeen:{}})
    | .repos[$k].prs.cursor   = ([.repos[$k].prs.cursor, $p[0].newCursor] | max)
    | .repos[$k].prs.openSeen = ((.repos[$k].prs.openSeen // {}) + $p[0].openSeen)
    | .repos[$k].prs.updatedAt = (now|todate)
  ' "$SL_PAGI" | sl_atomic_write "$SL_PAGI"
  rm -f "$P"
  echo "advanced PR cursor for: $key"
}

if [ -n "${1:-}" ]; then
  apply_one "$1"
else
  shopt -s nullglob
  found=0
  for P in "$SL_PENDING_DIR"/pr-*.json; do apply_one "$P"; found=1; done
  [ "$found" -eq 0 ] && echo "no pending PR batches to advance"
fi
exit 0
