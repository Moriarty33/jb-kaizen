#!/usr/bin/env bash
# Persist all self-learn config + state to your private repository so it is
# versioned, backed up, and synced across machines. The self-learn home
# ($SELF_LEARN_HOME, default ~/.claude/self-learn) IS the repo - everything lives
# there centrally (registry, cursors, version manifest, journal, snapshots).
#
# Usage:
#   sync.sh init <git-remote-url>   one-time: make SL_HOME a git repo + set remote
#   sync.sh                          commit any changes and push
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

cd "$SL_HOME"

if [ "${1:-}" = "init" ]; then
  REMOTE="${2:?usage: sync.sh init <git-remote-url>}"
  [ -d .git ] || git init -q
  # pending/ is transient crash-safety state - never push it.
  printf 'pending/\n' > .gitignore
  git remote remove origin 2>/dev/null || true
  git remote add origin "$REMOTE"
  git add -A
  git -c user.name="self-learn" -c user.email="self-learn@local" commit -q -m "init self-learn config store" || true
  git branch -M main
  git push -u origin main
  echo "self-learn store initialized and pushed to $REMOTE"
  exit 0
fi

[ -d .git ] || { echo "not initialized - run: sync.sh init <git-remote-url>" >&2; exit 1; }
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git add -A
if git diff --cached --quiet; then
  echo "no changes to sync"
else
  git -c user.name="self-learn" -c user.email="self-learn@local" \
    commit -q -m "self-learn: epoch $(jq -r '.epoch' "$SL_STATE") sync $(date -u +%FT%TZ)"
fi

# Integrate anything that landed on the remote since the last run (a merged PR, an edit
# from another machine) BEFORE pushing. Without this, one remote commit turns every
# subsequent nightly push into a non-fast-forward failure until someone pulls by hand.
# Rebase keeps the store history linear; the store is append-mostly so conflicts are rare,
# and a conflict aborts loudly rather than clobbering either side.
if git remote get-url origin >/dev/null 2>&1; then
  if ! git -c user.name="self-learn" -c user.email="self-learn@local" pull -q --rebase origin "$BRANCH"; then
    git rebase --abort 2>/dev/null || true
    echo "sync.sh: could not rebase onto origin/$BRANCH (conflict or unreachable remote) - resolve by hand in $SL_HOME, then rerun sync.sh" >&2
    exit 1
  fi
  if [ "$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 1)" -gt 0 ]; then
    git push -q origin "$BRANCH"
    echo "synced to remote"
  else
    echo "remote already up to date"
  fi
fi
