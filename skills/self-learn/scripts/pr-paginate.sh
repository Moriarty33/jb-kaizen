#!/usr/bin/env bash
# Emit the next batch of UNPROCESSED pull requests + their review comments for a
# GitHub repo. Two signals, both with their own cursor:
#   - historical backfill: PRs with number > cursor, oldest-first (number ascending)
#   - live open PRs: any OPEN pr whose updatedAt moved past what we last saw (new comments)
#
# PR review comments are the richest signal for improving reviewer / fixer / planning
# (architect, critic) agents - they show exactly what humans and bots flag and how it
# gets resolved.
#
# Two-phase like the commit paginator: this only PROPOSES a batch (writes pending);
# pr-advance.sh moves the cursor after analysis succeeds.
#
# Usage: pr-paginate.sh [--repo PATH] [BATCH=10] [MAX_COMMENTS_PER_PR=40]
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init
set +e +o pipefail   # tolerate gh/jq non-matches

REPO_ARG=""
if [ "${1:-}" = "--repo" ]; then REPO_ARG="$2"; shift 2; fi
BATCH="${1:-10}"
MAXC="${2:-40}"

ROOT="${REPO_ARG:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$ROOT" ] && { echo '{"error":"not a git repository"}'; exit 0; }
REPO_KEY="$(sl_repo_key "$ROOT")"

# Derive owner/repo from the origin URL (github only).
remote="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
nwo="$(printf '%s' "$remote" | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"
case "$remote" in *github.com*) : ;; *) echo "{\"repo\":\"$REPO_KEY\",\"skipped\":\"not a github remote\"}"; exit 0;; esac

cursor="$(jq -r --arg k "$REPO_KEY" '.repos[$k].prs.cursor // 0' "$SL_PAGI")"

# Bot-login denylist: machine accounts that post as a USER (not a GitHub App), so
# .user.type=="Bot" misses them - e.g. project CI bots emitting coverage/quality reports.
# Project-agnostic: read from registry config (global .botLogins + per-repo override);
# combined with universal login/body signatures below. (Epoch 15: 230 reviewdog/coverage
# comments from such accounts were polluting the human-signal count.)
botlogins="$(jq -c --arg k "$REPO_KEY" '(.botLogins // []) + (.repos[$k].config.botLogins // [])' "$SL_REGISTRY" 2>/dev/null)"
[ -z "$botlogins" ] && botlogins='[]'

# Full PR list (bounded), ascending by number.
list="$(gh pr list --repo "$nwo" --state all --limit 400 \
  --json number,state,title,author,baseRefName,headRefName,updatedAt 2>/dev/null \
  | jq 'sort_by(.number)')"
[ -z "$list" ] && { echo "{\"repo\":\"$REPO_KEY\",\"prs\":[],\"note\":\"gh returned nothing\"}"; exit 0; }

# Which PR numbers to process this run:
#  - historical: number > cursor, take BATCH (oldest first)
#  - open with new activity: OPEN and updatedAt > stored openSeen[number]
historical="$(jq -r --argjson c "$cursor" '[.[] | select(.number > $c and .state != "OPEN")] | sort_by(.number) | .[0:'"$BATCH"'][].number' <<<"$list")"
opennums="$(jq -r --slurpfile p "$SL_PAGI" --arg k "$REPO_KEY" '
  .[] | select(.state=="OPEN")
  | . as $pr | ($p[0].repos[$k].prs.openSeen[($pr.number|tostring)] // "") as $seen
  | select($pr.updatedAt > $seen) | $pr.number' <<<"$list")"

nums="$(printf '%s\n%s\n' "$historical" "$opennums" | grep -E '^[0-9]+$' | sort -un)"
[ -z "$nums" ] && { echo "{\"repo\":\"$REPO_KEY\",\"prs\":[],\"note\":\"nothing new\"}"; rm -f "$SL_PENDING_DIR/pr-$(sl_safe_key "$REPO_KEY").json"; exit 0; }

# Fetch one comment stream, with bounded retry. Returns 0 ONLY when the stream was
# genuinely READ (rc==0 AND the payload is a JSON array); sets FS_OUT / FS_ERR.
#
# `gh api` has TWO failure shapes and both must count as "not read":
#   1. HTTP error -> rc!=0, the API error object ({"message":...}) goes to STDOUT and
#      --jq is NOT applied, so the value is a non-array;
#   2. transport/network -> rc!=0 and stdout is EMPTY.
# Shape 2 is why the old `[ -z "$val" ] && val='[]'` short-circuit was unsafe: it mapped
# a total failure to "this PR had no comments", and the cursor then advanced past data
# that was never read - the epoch-11 silent-coverage-loss class, live in this file until
# epoch 38. A successful --jq call always prints an array, so empty stdout is
# unambiguously "never read". Key on rc FIRST, then type-check.
#
# Retry only TRANSIENT failures: 5xx/network. A 404, a rate-limit or bad credentials will
# not heal in 3 seconds, and retrying a rate-limited API is actively counterproductive.
# (Epoch 38: during a GitHub partial outage the reviews endpoint answered ~42% of calls,
# so 3 tries lifts it to ~80%; the inline endpoint was 0/12 and retry cannot save it.)
SL_PR_TRIES="${SL_PR_TRIES:-3}"

fetch_stream() {
  local ep="$1"
  local filt="$2"
  local try=1
  local raw rc msg
  FS_OUT=""; FS_ERR=""
  while :; do
    raw="$(gh api "$ep" --jq "$filt" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ] && jq -e 'type=="array"' >/dev/null 2>&1 <<<"$raw"; then
      FS_OUT="$raw"; return 0
    fi
    msg="$(jq -r '.message // empty' <<<"$raw" 2>/dev/null)"
    [ -z "$msg" ] && msg="no response from gh (rc=$rc)"
    case "$msg" in
      *"Not Found"*|*"rate limit"*|*"Bad credentials"*|*"Requires authentication"*|*"Must have"*)
        FS_ERR="$msg (permanent, not retried)"; return 1 ;;
    esac
    if [ "$try" -ge "$SL_PR_TRIES" ]; then FS_ERR="$msg (after $try tries)"; return 1; fi
    sleep "$try"
    try=$((try+1))
  done
}

prs="[]"; newcursor="$cursor"; openseen="{}"
for n in $nums; do
  meta="$(jq -c --argjson n "$n" '.[] | select(.number==$n)' <<<"$list")"
  state="$(jq -r '.state' <<<"$meta")"
  updated="$(jq -r '.updatedAt' <<<"$meta")"

  # Never silently degrade the top self-learn input: if any stream could not be READ,
  # abort this repo loudly so the cursor stays put and the next run re-reads the same PRs.
  # (A GitHub 503 on the comments endpoints once blanked four repos' PR streams and the
  # cursor moved past data that was never read -> the type-check + loud abort, then the
  # rc-aware detection and bounded retry for transient 5xx.)
  _fail() {
    echo "{\"repo\":\"$REPO_KEY\",\"error\":\"github api failed on PR #$n ($1): $2\",\"partial\":true}" >&2
    rm -f "$SL_PENDING_DIR/pr-$(sl_safe_key "$REPO_KEY").json"
    exit 3
  }

  fetch_stream "repos/$nwo/pulls/$n/comments" \
    '[.[] | {kind:"inline", createdAt:.created_at, path, line, user:.user.login, bot:(.user.type=="Bot"), body:(.body[0:2000])}]' \
    || _fail inline "$FS_ERR"
  inline="$FS_OUT"

  fetch_stream "repos/$nwo/issues/$n/comments" \
    '[.[] | {kind:"issue", createdAt:.created_at, user:.user.login, bot:(.user.type=="Bot"), body:(.body[0:2000])}]' \
    || _fail issuec "$FS_ERR"
  issuec="$FS_OUT"

  fetch_stream "repos/$nwo/pulls/$n/reviews" \
    '[.[] | select(.state=="CHANGES_REQUESTED" or .state=="APPROVED" or .state=="COMMENTED") | {kind:"verdict", createdAt:.submitted_at, state, user:.user.login, body:(.body[0:2000])}]' \
    || _fail reviews "$FS_ERR"
  reviews="$FS_OUT"

  # Flag bots beyond GitHub's .user.type=="Bot" (already applied above): config bot logins,
  # universal CI/bot login patterns, and the reviewdog inline-report HTML marker. These are
  # project-agnostic (no client name hardcoded; client CI accounts live in registry botLogins).
  comments="$(jq -n --argjson a "$inline" --argjson b "$issuec" --argjson c "$reviews" --argjson bl "$botlogins" \
    '($a + $b + $c)
     | map(.user as $u | .body as $bd | .bot = ((.bot // false)
         or (($u // "") | test("\\[bot\\]$|^dependabot|^github-actions|reviewdog|copilot"; "i"))
         or (($u != null) and (($bl | index($u)) != null))
         or (($bd // "") | test("__reviewdog__"))))
     | .[0:'"$MAXC"']')"

  prs="$(jq --argjson m "$meta" --argjson cm "$comments" \
    '. + [{number:$m.number, state:$m.state, title:$m.title, author:$m.author.login, base:$m.baseRefName, updatedAt:$m.updatedAt, commentCount:($cm|length), comments:$cm}]' <<<"$prs")"

  # historical cursor advances only for non-open (settled) PRs processed in order
  if [ "$state" != "OPEN" ] && [ "$n" -gt "$newcursor" ]; then newcursor="$n"; fi
  [ "$state" = "OPEN" ] && openseen="$(jq --arg k "$n" --arg v "$updated" '.[$k]=$v' <<<"$openseen")"
done

out="$(jq -n --arg k "$REPO_KEY" --arg nwo "$nwo" --argjson prs "$prs" \
  --argjson cur "$newcursor" --argjson os "$openseen" \
  '{repo:$k, nameWithOwner:$nwo, count:($prs|length), newCursor:$cur, openSeen:$os, prs:$prs}')"
printf '%s\n' "$out" > "$SL_PENDING_DIR/pr-$(sl_safe_key "$REPO_KEY").json"
# Print a lean view to stdout (drop full comment bodies); the pending file has everything.
jq '{repo, nameWithOwner, count, newCursor, prs:[.prs[]|{number,state,title,commentCount}]}' <<<"$out"
