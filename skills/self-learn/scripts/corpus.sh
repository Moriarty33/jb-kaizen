#!/usr/bin/env bash
# corpus.sh - build the Phase-2 session corpus with self-contamination removed.
#
# WHY THIS IS A SCRIPT AND NOT PROSE: the recipe was hand-composed at Phase 2 and got
# wrong three separate times, each time reading as a clean corpus. The three traps it
# encodes:
#   1. find, not a one-level glob. Subagent/workflow transcripts are NESTED under
#      <session-id>/subagents/..., and a shallow glob hides ~91% of the corpus.
#   2. Exclude engine sessions by SESSION ID AS A PATH COMPONENT - both <id>.jsonl and
#      <id>/** - never by sniffing the top-level file's header. Nested children carry no
#      header, so header-sniffing leaves every past run's subagents in the corpus.
#      Measured once: header-sniff left 2373 of 2468 files; path exclusion left 925. The
#      hole was 1448 engine transcripts = 61% of the supposedly-clean corpus.
#   3. Consume the list with `< file` redirection, never `xargs -a` (a GNU-ism; BSD/macOS
#      xargs rejects it, grep then scans ZERO files and the pipeline still exits 0, so
#      every literal reports a false "0 hits" and the load-bearing pass fails open).
#
# Usage:
#   bash corpus.sh                       # write the clean corpus list, print a summary
#   bash corpus.sh --out /tmp/c.txt      # choose the output path (default /tmp/sl-corpus.txt)
#   bash corpus.sh --exclude <id>        # also exclude this session id (repeatable; use for
#                                        # the CURRENT session, which has no header yet)
#   bash corpus.sh --since '2026-08-01'  # only transcripts modified since this date
#
# Then consume it:  xargs grep -lF 'literal' < /tmp/sl-corpus.txt
set -uo pipefail

PROJECTS="${SELF_LEARN_PROJECTS:-$HOME/.claude/projects}"
OUT=/tmp/sl-corpus.txt
SINCE=""
EXTRA_IDS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --exclude) EXTRA_IDS+=("$2"); shift 2 ;;
    *) echo "corpus.sh: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ALL="$WORK/all.txt"; IDS="$WORK/ids.txt"; PAT="$WORK/pat.txt"

# 1. every transcript, nested ones included
if [ -n "$SINCE" ]; then
  find "$PROJECTS" -name '*.jsonl' -newermt "$SINCE" > "$ALL"
else
  find "$PROJECTS" -name '*.jsonl' > "$ALL"
fi

# 2. engine-run session ids, detected from the OPENING prompt only (first 5 records).
#    A wider scan mis-flags any session that merely discusses these skills. Add your own
#    unattended jobs' opening-prompt markers via SELF_LEARN_ENGINE_MARKERS (an extended
#    regex alternation) so their transcripts are excluded too.
ENGINE_RE='NON-INTERACTIVE RUN CONTRACT|nightly self-learn|<<autonomous-loop'
[ -n "${SELF_LEARN_ENGINE_MARKERS:-}" ] && ENGINE_RE="$ENGINE_RE|$SELF_LEARN_ENGINE_MARKERS"
: > "$IDS"
find "$PROJECTS" -maxdepth 2 -name '*.jsonl' | while IFS= read -r f; do
  if head -5 "$f" | grep -qE "$ENGINE_RE"; then
    basename "$f" .jsonl >> "$IDS"
  fi
done
for id in ${EXTRA_IDS+"${EXTRA_IDS[@]}"}; do echo "$id" >> "$IDS"; done
sort -u "$IDS" -o "$IDS"

# 3. exclude each id as a PATH COMPONENT: its own file AND everything nested beneath it
awk '{ print "/"$1"/"; print "/"$1".jsonl" }' "$IDS" > "$PAT"
if [ -s "$PAT" ]; then
  grep -vF -f "$PAT" "$ALL" > "$OUT"
else
  cp "$ALL" "$OUT"
fi

TOTAL=$(wc -l < "$ALL" | tr -d ' ')
CLEAN=$(wc -l < "$OUT" | tr -d ' ')
NIDS=$(wc -l < "$IDS" | tr -d ' ')

# 4. fail-open canary: prove the consume pipeline actually scans files before any zero is
#    believed. '"type"' appears in every well-formed transcript line.
CANARY=0
if [ "$CLEAN" -gt 0 ]; then
  CANARY=$(xargs grep -lF '"type"' < "$OUT" 2>/dev/null | wc -l | tr -d ' ')
fi

echo "corpus:      $OUT"
echo "all:         $TOTAL"
echo "engine ids:  $NIDS  (excluded with their nested subagent transcripts)"
echo "clean:       $CLEAN  (excluded $((TOTAL - CLEAN)))"
echo "canary:      $CANARY/$CLEAN files matched '\"type\"'"
if [ "$CLEAN" -gt 0 ] && [ "$CANARY" -eq 0 ]; then
  echo "CANARY FAILED - the consume pipeline scanned nothing. Do NOT believe any zero from this corpus." >&2
  exit 1
fi
