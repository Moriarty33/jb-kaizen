#!/usr/bin/env bash
# Emit the next batch of UNPROCESSED commits, oldest-first, per branch.
#
# Two-phase by design: paginate.sh only PROPOSES a batch (and writes it to
# pending.json). The cursor is not advanced until advance.sh runs. This way a
# crash or aborted analysis never silently skips commits - you re-run and get
# the same batch again.
#
# Usage: paginate.sh [--repo PATH] [BATCH_PER_BRANCH=40] [MAX_TOTAL=200]
#        With no --repo, uses the current working directory's repo.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

REPO_ARG=""
if [ "${1:-}" = "--repo" ]; then REPO_ARG="$2"; shift 2; fi
BATCH="${1:-40}"
MAX_TOTAL="${2:-200}"

if [ -n "$REPO_ARG" ]; then
  REPO_ROOT="$(git -C "$REPO_ARG" rev-parse --show-toplevel 2>/dev/null || true)"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$REPO_ROOT" ]; then echo '{"error":"not a git repository"}'; exit 0; fi
REPO_KEY="$(sl_repo_key "$REPO_ROOT")"

# Hashes already processed for this repo (dedups commits shared across branches,
# e.g. everything on main that also appears on feature branches).
seenfile="$(mktemp)"
jq -r --arg k "$REPO_KEY" '.repos[$k].seen // [] | .[]' "$SL_PAGI" > "$seenfile" || true

branches="$(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' refs/heads/)"

total=0
batches="[]"
newseen="[]"
for br in $branches; do
  [ "$total" -ge "$MAX_TOTAL" ] && break

  cursor="$(jq -r --arg k "$REPO_KEY" --arg b "$br" '.repos[$k].branches[$b].lastHash // ""' "$SL_PAGI")"
  if [ -n "$cursor" ] && git -C "$REPO_ROOT" cat-file -e "${cursor}^{commit}" 2>/dev/null; then
    range="${cursor}..${br}"
  else
    range="$br"   # no cursor (or rebased away) -> start from the very first commit
  fi

  cand="$(git -C "$REPO_ROOT" rev-list --reverse $range 2>/dev/null | grep -Fxv -f "$seenfile" || true)"
  [ -z "$cand" ] && continue

  remaining=$(( MAX_TOTAL - total ))
  take=$BATCH; [ "$take" -gt "$remaining" ] && take=$remaining
  # `head` closes the pipe after $take lines; on a large first-time backlog the
  # upstream sed/printf then take SIGPIPE (141), which `set -o pipefail` turns into
  # a fatal script exit. Tolerate it so big no-cursor repos paginate (epoch 11).
  picked="$(printf '%s\n' "$cand" | sed '/^$/d' | head -n "$take" || true)"
  cnt="$(printf '%s\n' "$picked" | sed '/^$/d' | grep -c . || true)"
  [ "${cnt:-0}" -eq 0 ] && continue
  newcursor="$(printf '%s\n' "$picked" | tail -n1)"

  commits="[]"
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    meta="$(git -C "$REPO_ROOT" show -s --format='%H%x1f%an%x1f%ad%x1f%s' --date=short "$h")"
    H="${meta%%$'\x1f'*}";    rest="${meta#*$'\x1f'}"
    AN="${rest%%$'\x1f'*}";   rest="${rest#*$'\x1f'}"
    AD="${rest%%$'\x1f'*}";   SU="${rest#*$'\x1f'}"
    stat="$(git -C "$REPO_ROOT" show --stat --format='' "$h" | tail -n1 | sed 's/^[[:space:]]*//')"
    commits="$(jq --arg h "$H" --arg an "$AN" --arg ad "$AD" --arg su "$SU" --arg st "$stat" \
      '. + [{hash:$h,author:$an,date:$ad,subject:$su,stat:$st}]' <<<"$commits")"
    newseen="$(jq --arg h "$H" '. + [$h]' <<<"$newseen")"
  done <<< "$picked"

  # Dedup WITHIN this run too: commits picked for an earlier branch must not be
  # re-picked for a later branch that shares history (e.g. everything on main).
  printf '%s\n' "$picked" >> "$seenfile"

  batches="$(jq --arg b "$br" --arg c "$newcursor" --argjson cm "$commits" \
    '. + [{branch:$b,newCursor:$c,commits:$cm}]' <<<"$batches")"
  total=$(( total + cnt ))
done
rm -f "$seenfile"

out="$(jq -n --arg k "$REPO_KEY" --argjson b "$batches" --argjson ns "$newseen" --argjson t "$total" \
  '{repo:$k,totalCommits:$t,batches:$b,newSeen:$ns}')"
printf '%s\n' "$out" > "$SL_PENDING_DIR/$(sl_safe_key "$REPO_KEY").json"
printf '%s\n' "$out"
