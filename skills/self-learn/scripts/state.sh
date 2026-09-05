#!/usr/bin/env bash
# State overview + epoch management.
#   state.sh status       -> compact JSON: where am I, what's tracked
#   state.sh bump-epoch    -> increment the learning epoch, stamp lastRunAt
#   state.sh set-version X -> set the knowledge-base semver
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

cmd="${1:-status}"
case "$cmd" in
  status)
    pending_count=$(find "$SL_PENDING_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
    jq -n \
      --slurpfile s "$SL_STATE" --slurpfile p "$SL_PAGI" --slurpfile v "$SL_VERS" \
      --slurpfile r "$SL_REGISTRY" --argjson pend "${pending_count:-0}" \
      '{
        epoch: $s[0].epoch,
        version: $s[0].version,
        lastRunAt: $s[0].lastRunAt,
        registeredRepos: ($r[0].repos | length),
        repos: ($p[0].repos | to_entries | map({key:.key, branches:((.value.branches//{})|keys|length), seen:((.value.seen//[])|length)})),
        sessionsTracked: ($p[0].sessions | length),
        itemsTracked: ($v[0].items | length),
        pendingBatches: $pend
      }'
    ;;
  bump-epoch)
    jq '.epoch = (.epoch + 1) | .lastRunAt = (now|todate)' "$SL_STATE" | sl_atomic_write "$SL_STATE"
    jq -r '.epoch' "$SL_STATE"
    ;;
  set-version)
    v="${2:?usage: state.sh set-version X.Y.Z}"
    jq --arg v "$v" '.version = $v' "$SL_STATE" | sl_atomic_write "$SL_STATE"
    echo "version -> $v"
    ;;
  *)
    echo "unknown command: $cmd" >&2; exit 1 ;;
esac
