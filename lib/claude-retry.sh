#!/usr/bin/env bash
# claude-retry.sh - run a headless `claude -p` turn with a wall-clock budget and bounded
# retries, for unattended jobs (launchd / cron / systemd timers).
#
#   source ~/.claude/lib/claude-retry.sh
#   claude_retry "<prompt>" [extra claude args...]
#
# Env:
#   CLAUDE_RETRY_TIMEOUT   seconds per attempt before the turn is killed (default 14400 = 4h)
#   CLAUDE_RETRY_MAX       attempts (default 3)
#   CLAUDE_RETRY_BACKOFF   seconds before attempt 2 (default 30; doubles each retry)
#   CLAUDE_BIN             claude executable (default: `claude` on PATH)
#
# Exit codes: 0 = a turn completed; 124 = every attempt timed out; 77 = auth failure
# (not retried - a token will not heal in 30s); other = the last claude exit code.
#
# Output markers (grep-able from the job log; loop-contract style status vocabulary):
#   RETRY-WRAPPER: OK after N attempt(s)
#   RETRY-WRAPPER: timeout - attempt i/N killed after Ts (hung/runaway turn)
#   RETRY-WRAPPER: failure (rc=..., timeout=0|1, attempt i/N, auth=0|1) - retrying in Ss
#   RETRY-WRAPPER: AUTH_FAIL - not retrying
#   RETRY-WRAPPER: TRANSIENT_EXHAUSTED after N attempts
#
# Portable: bash 3.2 (macOS) - no `timeout`, `mapfile` or `declare -A`.

claude_retry() {
  local prompt="$1"; shift
  local max="${CLAUDE_RETRY_MAX:-3}"
  local budget="${CLAUDE_RETRY_TIMEOUT:-14400}"
  local backoff="${CLAUDE_RETRY_BACKOFF:-30}"
  local bin="${CLAUDE_BIN:-claude}"
  local attempt=1 rc timed_out auth errfile pid elapsed

  errfile="$(mktemp)"
  while :; do
    timed_out=0; auth=0
    # Run the turn in the background and poll it against the wall-clock budget so a hung
    # turn cannot pin the job forever. stderr is teed to a file for the auth classifier.
    # Job control (set -m) gives the turn its own process group, so the timeout kill
    # below reaches the CLI *and* every child it spawned (subagents, helpers) - a bare
    # kill of the top pid would orphan children that keep the job's pipes open.
    set -m
    "$bin" -p "$prompt" "$@" 2> >(tee "$errfile" >&2) &
    pid=$!
    set +m
    # Poll instead of a sleeping watchdog: no background helper, so nothing is left behind
    # holding the caller's pipes, and the kill happens from this shell. 5s granularity is
    # irrelevant against an hours-long budget.
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$elapsed" -ge "$budget" ]; then
        kill -TERM -- "-$pid" 2>/dev/null; sleep 5; kill -KILL -- "-$pid" 2>/dev/null
        break
      fi
      sleep 5; elapsed=$(( elapsed + 5 ))
    done
    wait "$pid" 2>/dev/null; rc=$?
    if [ "$rc" -eq 143 ] || [ "$rc" -eq 137 ]; then
      timed_out=1; rc=124
      echo "RETRY-WRAPPER: timeout - attempt $attempt/$max killed after ${budget}s (hung/runaway turn)"
    fi
    if [ "$rc" -eq 0 ]; then
      echo "RETRY-WRAPPER: OK after $attempt attempt(s)"
      rm -f "$errfile"; return 0
    fi
    if grep -qiE 'not logged in|authentication|invalid api key|401 Unauthorized|OAuth token' "$errfile" 2>/dev/null; then
      auth=1
    fi
    if [ "$auth" -eq 1 ]; then
      echo "RETRY-WRAPPER: AUTH_FAIL - not retrying (rc=$rc, attempt $attempt/$max)"
      rm -f "$errfile"; return 77
    fi
    if [ "$attempt" -ge "$max" ]; then
      echo "RETRY-WRAPPER: TRANSIENT_EXHAUSTED after $attempt attempts (last rc=$rc, timeout=$timed_out)"
      rm -f "$errfile"; return "$rc"
    fi
    echo "RETRY-WRAPPER: failure (rc=$rc, timeout=$timed_out, attempt $attempt/$max, auth=$auth) - retrying in ${backoff}s"
    sleep "$backoff"
    backoff=$(( backoff * 2 ))
    attempt=$(( attempt + 1 ))
  done
}
