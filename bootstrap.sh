#!/usr/bin/env bash
# curl -fsSL <raw-url>/bootstrap.sh | bash - clones or updates ~/.jb-kaizen, then install-entry.sh asks its two questions.
set -euo pipefail

JB_KAIZEN_REPO="${JB_KAIZEN_REPO:-https://github.com/Moriarty33/jb-kaizen.git}"
JB_KAIZEN_DIR="${JB_KAIZEN_DIR:-$HOME/.jb-kaizen}"
JB_KAIZEN_BRANCH="${JB_KAIZEN_BRANCH:-main}"

say()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

if ! command -v git >/dev/null 2>&1; then
  echo "git is required but not found on PATH" >&2
  exit 1
fi

if [ -d "$JB_KAIZEN_DIR/.git" ]; then
  step "Updating existing clone at $JB_KAIZEN_DIR"
  git -C "$JB_KAIZEN_DIR" diff --quiet || {
    echo "$JB_KAIZEN_DIR has local changes - refusing to reset; move it aside or set JB_KAIZEN_DIR" >&2
    exit 1
  }
  say "fetching $JB_KAIZEN_BRANCH from $JB_KAIZEN_REPO"
  git -C "$JB_KAIZEN_DIR" remote set-url origin "$JB_KAIZEN_REPO"
  git -C "$JB_KAIZEN_DIR" fetch --depth 1 origin "$JB_KAIZEN_BRANCH"
  git -C "$JB_KAIZEN_DIR" checkout -q "$JB_KAIZEN_BRANCH"
  git -C "$JB_KAIZEN_DIR" reset --hard "origin/$JB_KAIZEN_BRANCH"
else
  step "Cloning $JB_KAIZEN_REPO into $JB_KAIZEN_DIR"
  git clone --depth 1 --branch "$JB_KAIZEN_BRANCH" "$JB_KAIZEN_REPO" "$JB_KAIZEN_DIR"
fi

step "Handing off to install-entry.sh"
# Under `curl | bash` stdin is the script itself, so the two questions read the terminal instead.
if [ ! -t 0 ] && [ -t 1 ] && (exec 3</dev/tty) 2>/dev/null; then
  exec bash "$JB_KAIZEN_DIR/install-entry.sh" "$@" < /dev/tty
fi
exec bash "$JB_KAIZEN_DIR/install-entry.sh" "$@"
