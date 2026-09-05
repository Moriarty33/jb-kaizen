#!/usr/bin/env bash
# Unattended nightly self-learn run. Installed to $SELF_LEARN_HOME/scripts/nightly-run.sh
# and fired by launchd (macOS) / systemd timer or cron (Linux) - see templates/.
#
# The scheduler gives a minimal environment, so PATH and HOME are set explicitly.
# Permission mode is "auto": safe actions are auto-approved, dangerous ones are gated by
# the classifier (not blindly skipped) - and the snapshot-before-edit discipline in the
# skill keeps every applied change reversible regardless.
#
# Tunables (env, all optional):
#   SELF_LEARN_HOME        store dir            (default ~/.claude/self-learn)
#   SELF_LEARN_WORKSPACE   cwd for the run      (default ~/workspace) - MUST exist
#   SELF_LEARN_MODEL       --model for the run  (default opus)
#   SELF_LEARN_BUDGET_USD  --max-budget-usd cap (default 40)
#   CLAUDE_RETRY_TIMEOUT   per-attempt wall-clock seconds (default 14400 = 4h)
set -uo pipefail

export HOME="${HOME:-$(cd ~ && pwd)}"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SL_HOME="${SELF_LEARN_HOME:-$HOME/.claude/self-learn}"
WORKSPACE="${SELF_LEARN_WORKSPACE:-$HOME/workspace}"
MODEL="${SELF_LEARN_MODEL:-opus}"
BUDGET="${SELF_LEARN_BUDGET_USD:-40}"

LOGDIR="$SL_HOME/logs"
mkdir -p "$LOGDIR"
STAMP="$(date +%Y-%m-%d_%H%M)"
LOG="$LOGDIR/nightly-$STAMP.log"
PROMPT_FILE="$SL_HOME/nightly-prompt.txt"

# Run from the workspace so repo discovery and relative work behave naturally.
# NEVER fall back to $HOME - that lets the agent traverse personal folders and, on macOS,
# triggers TCC access prompts at 3am.
cd "$WORKSPACE" 2>/dev/null || { echo "FATAL: workspace $WORKSPACE missing - aborting to avoid \$HOME traversal" >> "$LOG"; exit 1; }

{
  echo "=== self-learn nightly START: $(date) ==="
  echo "claude: $(command -v claude || echo MISSING)  node: $(command -v node || echo MISSING)  model: $MODEL  budget: \$$BUDGET"
  if ! command -v claude >/dev/null; then
    echo "FATAL: claude CLI not on PATH"; exit 127
  fi
  export CLAUDE_RETRY_TIMEOUT="${CLAUDE_RETRY_TIMEOUT:-14400}"
  . "$HOME/.claude/lib/claude-retry.sh"
  # File-access scope: trust only the workspace (cwd) + ~/.claude, and hard-deny personal
  # folders via night-guard-settings.json so no access prompt ever fires.
  # --max-budget-usd is the one hard spend ceiling that survives ultracode-mode fan-out.
  claude_retry "$(cat "$PROMPT_FILE")" \
    --model "$MODEL" \
    --permission-mode auto \
    --max-budget-usd "$BUDGET" \
    --add-dir "$HOME/.claude" \
    --settings "$HOME/.claude/night-guard-settings.json" \
    --output-format text
  rc=$?
  echo "=== self-learn nightly END: $(date) (exit $rc) ==="

  # Completion guard: the run is only real if a journal file was written today.
  # Catches the headless "stood by waiting for re-invoke" stall (exit 0 but no work done).
  TODAY="$(date +%Y-%m-%d)"
  if ls "$SL_HOME/journal/"*"-$TODAY.md" >/dev/null 2>&1; then
    echo "=== COMPLETION OK: journal for $TODAY exists ==="
  else
    echo "=== COMPLETION WARNING: no journal written for $TODAY - run did not finish the pipeline ==="
  fi
} >> "$LOG" 2>&1

# Keep the log dir tidy.
find "$LOGDIR" -name 'nightly-*.log' -mtime +30 -delete 2>/dev/null || true
