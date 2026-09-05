#!/usr/bin/env bash
# Register a single project into the central registry. Use this when you create a
# new project and want it enrolled immediately (rather than waiting for the next
# discover.sh sweep). Config is stored centrally - nothing is written into the
# project itself.
#
# Usage: register.sh <path-to-repo> [name] [--disabled]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

REPO="${1:?usage: register.sh <path-to-repo> [name] [--disabled]}"
NAME="${2:-$(basename "$REPO")}"
ENABLED=true
[ "${3:-}" = "--disabled" ] && ENABLED=false

ROOT="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$ROOT" ] && { echo "not a git repo: $REPO" >&2; exit 1; }
remote="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "")"
key="${remote:-$ROOT}"

jq --arg k "$key" --arg n "$NAME" --arg p "$ROOT" --arg rm "$remote" --argjson en "$ENABLED" '
  .repos[$k] = ((.repos[$k] // {config:{batch:40,maxTotal:200}, addedAt:(now|todate)})
    + {name:$n, path:$p, remote:$rm, enabled:$en, lastSeenAt:(now|todate)})
' "$SL_REGISTRY" | sl_atomic_write "$SL_REGISTRY"

echo "registered: $NAME  ($key)  enabled=$ENABLED"
