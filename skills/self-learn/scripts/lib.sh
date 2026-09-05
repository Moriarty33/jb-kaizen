#!/usr/bin/env bash
# Shared paths + state bootstrap for the self-learn skill.
# State lives OUTSIDE the skill dir so reinstalling/editing the skill never wipes
# learned progress, and so the same memory is shared across every project.
set -euo pipefail

SL_HOME="${SELF_LEARN_HOME:-$HOME/.claude/self-learn}"
SL_STATE="$SL_HOME/state.json"        # epoch + knowledge-base version
SL_PAGI="$SL_HOME/pagination.json"    # per-repo/branch commit cursors + session cursor
SL_VERS="$SL_HOME/versions.json"      # version manifest for every agent/skill
SL_SNAP="$SL_HOME/snapshots"          # immutable copies taken before any edit
SL_JOURNAL="$SL_HOME/journal"         # one markdown report per run
SL_REGISTRY="$SL_HOME/registry.json"  # every known repo/project + per-repo config
SL_PENDING_DIR="$SL_HOME/pending"     # per-repo emitted batches, consumed by advance

sl_init() {
  mkdir -p "$SL_HOME" "$SL_SNAP" "$SL_JOURNAL" "$SL_PENDING_DIR"
  [ -f "$SL_STATE" ] || printf '{"epoch":0,"version":"0.1.0","createdAt":"%s","lastRunAt":null}\n' "$(date -u +%FT%TZ)" > "$SL_STATE"
  [ -f "$SL_PAGI" ]  || echo '{"repos":{},"sessions":{}}' > "$SL_PAGI"
  [ -f "$SL_VERS" ]  || echo '{"items":{}}' > "$SL_VERS"
  [ -f "$SL_REGISTRY" ] || echo '{"roots":[],"repos":{}}' > "$SL_REGISTRY"
}

# Filesystem-safe token for a repo key (origin URL or path).
sl_safe_key() { printf '%s' "$1" | tr '/:@. ' '_____'; }

# Stable identity for a repo: prefer the origin URL so the same repo cloned to
# two paths shares one cursor; fall back to the working-tree path.
sl_repo_key() {
  local root="$1"
  git -C "$root" remote get-url origin 2>/dev/null || echo "$root"
}

# Portable sha256 (macOS ships shasum, most Linux images ship sha256sum; accept either).
sl_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi
}
sl_hash_file() { sl_sha256 < "$1" | awk '{print $1}'; }

# Portable file mtime as unix seconds (BSD stat on macOS, GNU stat on Linux).
sl_mtime() {
  # GNU stat first: on Linux `stat -f` is *filesystem* status and would succeed with junk.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

# A skill is a directory; hash the sorted contents so any file change is detected.
sl_hash_dir() {
  find "$1" -type f -not -name '.DS_Store' | sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(sl_hash_file "$f")" "$f"
  done | sl_sha256 | awk '{print $1}'
}

sl_atomic_write() { # <target-json-file>  reads new content from stdin
  local target="$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  # Refuse to clobber a target with empty or invalid JSON - a failed upstream jq
  # (e.g. iterating over null) emits nothing, which would otherwise truncate the
  # cursor store. Better to abort the write and keep the last good state.
  if [ ! -s "$tmp" ] || ! jq -e . "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    echo "sl_atomic_write: refusing to write empty/invalid JSON to $target" >&2
    return 1
  fi
  mv "$tmp" "$target"
}

# Every git working tree under the given roots, one path per line, sorted. Never descends
# into dependency dirs (node_modules, vendor, .terraform). Shared by discover.sh and the
# installer's wizard so both see exactly the same set.
sl_find_repos() {
  local root
  for root in "$@"; do
    [ -d "$root" ] || continue
    find "$root" \( -name node_modules -o -name vendor -o -name .terraform \) -prune -o -name .git -type d -print 2>/dev/null \
      | sed 's|/\.git$||' | sort
  done
}
