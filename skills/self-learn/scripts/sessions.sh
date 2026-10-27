#!/usr/bin/env bash
# List Claude Code session transcripts that are newer than the last-processed
# timestamp. Transcripts are the richest learning signal: they show what actually
# happened, what was corrected, where time was wasted.
#
# Each project working-dir has its OWN session cursor in pagination.json ->
# sessions[<encoded-dir>].lastTs. Reading only the CURRENT cwd would leave the
# richest transcripts (the projects you work in most) untracked and hand-mined
# every run; the --all / --dir modes below let a nightly run sweep and advance
# every project dir's cursor in one pass.
#
# Usage:
#   sessions.sh                          -> unprocessed sessions for the cwd project (JSON)
#   sessions.sh --dir <path>             -> ditto for a specific project working dir
#   sessions.sh --all                    -> JSON array, one entry per project dir with
#                                           unprocessed sessions (each scoped to its own cursor)
#   sessions.sh --advance <ts>           -> set the cwd project cursor to unix ts <ts>
#   sessions.sh --dir <path> --advance <ts> -> set a specific project's cursor
#   sessions.sh --all --advance          -> advance EVERY project dir's cursor to its own
#                                           newest session mtime (drains everything mined this run)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

PROOT="$HOME/.claude/projects"

# Claude Code encodes the project dir by replacing both "/" and "." with "-".
sl_encode() { printf '%s' "$1" | sed 's|[/.]|-|g'; }

# Emit the unprocessed-session JSON for one encoded project key.
sl_scan_one() {
  local enc="$1"; local pd="$PROOT/$enc"
  local last files maxts mt lines f cut_iso turn_ts new_turns
  last="$(jq -r --arg k "$enc" '.sessions[$k].lastTs // 0' "$SL_PAGI")"
  [ -d "$pd" ] || { jq -n --arg k "$enc" --argjson l "$last" '{project:$k,lastTs:$l,maxTs:$l,sessions:[]}'; return; }
  files="[]"; maxts="$last"
  for f in "$pd"/*.jsonl; do
    [ -e "$f" ] || continue
    mt="$(sl_mtime "$f")"
    [ "$mt" -le "$last" ] && continue
    [ "$mt" -gt "$maxts" ] && maxts="$mt"
    lines="$(wc -l < "$f" | tr -d ' ')"
    # mtime moves on metadata appends; the newest TURN is what says whether there is new signal.
    cut_iso="$(date -u -r "$last" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "1970-01-01T00:00:00Z")"
    turn_ts="$(jq -r 'select(.timestamp != null) | .timestamp' "$f" 2>/dev/null | sort | tail -1)"
    new_turns="$(jq -r --arg c "$cut_iso" 'select(.timestamp != null and .timestamp > $c) | .timestamp' "$f" 2>/dev/null | wc -l | tr -d ' ')"
    files="$(jq --arg p "$f" --argjson mt "$mt" --argjson ln "$lines" \
      --arg tt "${turn_ts:-}" --argjson nt "${new_turns:-0}" \
      '. + [{path:$p,mtime:$mt,lines:$ln,newestTurn:$tt,newTurns:$nt}]' <<<"$files")"
  done
  jq -n --arg k "$enc" --argjson last "$last" --argjson mx "$maxts" --argjson fl "$files" \
    '{project:$k,lastTs:$last,maxTs:$mx,sessions:($fl | sort_by(.mtime))}'
}

# Newest *.jsonl mtime under an encoded project key (for --all --advance).
sl_max_mtime() {
  local enc="$1"; local pd="$PROOT/$enc"
  local m=0 mt f
  [ -d "$pd" ] || { echo 0; return; }
  for f in "$pd"/*.jsonl; do
    [ -e "$f" ] || continue
    mt="$(sl_mtime "$f")"
    [ "$mt" -gt "$m" ] && m="$mt"
  done
  echo "$m"
}

sl_advance_one() {
  local enc="$1" ts="$2"
  jq --arg k "$enc" --argjson ts "$ts" \
    '.sessions[$k] = {lastTs:$ts, updatedAt:(now|todate)}' "$SL_PAGI" | sl_atomic_write "$SL_PAGI"
}

# ---- arg parse ----
MODE="cwd"; TARGET_DIR=""; ADVANCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     MODE="all"; shift ;;
    --dir)     MODE="dir"; TARGET_DIR="${2:?usage: --dir <path>}"; shift 2 ;;
    --advance) ADVANCE="${2:-__MAX__}"; shift; [ "${ADVANCE}" = "__MAX__" ] || shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---- advance ----
if [ -n "$ADVANCE" ]; then
  if [ "$MODE" = "all" ]; then
    n=0
    for pd in "$PROOT"/*/; do
      [ -d "$pd" ] || continue
      enc="$(basename "$pd")"
      mx="$(sl_max_mtime "$enc")"
      [ "$mx" -gt 0 ] || continue
      cur="$(jq -r --arg k "$enc" '.sessions[$k].lastTs // 0' "$SL_PAGI")"
      [ "$mx" -gt "$cur" ] || continue
      sl_advance_one "$enc" "$mx"; n=$((n+1))
    done
    echo "advanced $n project session cursors to their newest mtime"; exit 0
  fi
  [ "$ADVANCE" = "__MAX__" ] && { echo "usage: --advance <unix-ts> (or --all --advance)" >&2; exit 2; }
  enc="$(sl_encode "${TARGET_DIR:-$(pwd)}")"
  sl_advance_one "$enc" "$ADVANCE"
  echo "session cursor[$enc] -> $ADVANCE"; exit 0
fi

# ---- list ----
case "$MODE" in
  all)
    out="[]"
    for pd in "$PROOT"/*/; do
      [ -d "$pd" ] || continue
      enc="$(basename "$pd")"
      one="$(sl_scan_one "$enc")"
      [ "$(jq '.sessions | length' <<<"$one")" -gt 0 ] || continue
      out="$(jq --argjson o "$one" '. + [$o]' <<<"$out")"
    done
    jq 'sort_by(-(.maxTs))' <<<"$out"
    ;;
  dir)  sl_scan_one "$(sl_encode "$TARGET_DIR")" ;;
  *)    sl_scan_one "$(sl_encode "$(pwd)")" ;;
esac
