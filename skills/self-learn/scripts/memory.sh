#!/usr/bin/env bash
# Memory-store housekeeping for the self-learn skill (Phase 2.7).
# The per-project memory store (~/.claude/projects/*/memory/) is itself high-signal,
# already-distilled evidence, but it grows unbounded and its MEMORY.md index is loaded
# into context every session. This helper lets Phase 2.7:
#   - scan    : classify every memory file + mark new/changed/unchanged vs a cursor,
#               so unchanged memories are never re-analyzed (mirrors the sessions cursor)
#   - backup  : copy the whole memory dir before any compaction (the rollback source)
#   - advance : record the current file->hash map so the next run skips unchanged files
# Compaction of MEMORY.md itself is done by the model (it needs judgement); this script
# only provides the deterministic scan/backup/cursor primitives.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
sl_init

SL_MEMSNAP="$SL_HOME/memory-snapshots"   # pre-compaction copies, per memory dir
mkdir -p "$SL_MEMSNAP"

# Emit the memory dirs to operate on: one if given, else every project's store.
mem_dirs() {
  if [ -n "${1:-}" ]; then printf '%s\n' "$1"; return; fi
  find "$HOME/.claude/projects" -maxdepth 2 -type d -name memory 2>/dev/null | sort
}

# Read `type:` out of a memory file's YAML frontmatter. Two conventions coexist and both
# are legitimate: /lessons-learned writes `feedback_*`-style FILENAMES, while the built-in
# memory tool writes a kebab-case slug and records the class as `metadata.type`. Keying on
# the filename alone made every memory of the second kind classify as `other`, so Phase 2.7
# silently reported "no feedback memories to distill" - a fail-open miss, measured at 9 of
# 38 real feedback memories on 2026-08-14. The `^`-anchor is load-bearing: it must not match
# the `node_type:` line these files carry directly above `type:`.
fm_type() {
  awk 'NR==1 && $0!="---" {exit}
       NR>1 && /^---[[:space:]]*$/ {exit}
       /^[[:space:]]*type:[[:space:]]*/ { sub(/^[[:space:]]*type:[[:space:]]*/,""); gsub(/[[:space:]"'"'"']/,""); print; exit }' "$1" 2>/dev/null
}

classify() {
  case "$1" in
    MEMORY.md)    echo index; return ;;
    feedback_*)   echo feedback; return ;;
    project_*)    echo project; return ;;
    reference_*)  echo reference; return ;;
    user_*)       echo user; return ;;
    estimation_*) echo estimation; return ;;
  esac
  case "$(fm_type "${2:-/nonexistent}")" in
    feedback)   echo feedback ;;
    project)    echo project ;;
    reference)  echo reference ;;
    user)       echo user ;;
    estimation) echo estimation ;;
    *)          echo other ;;
  esac
}

# scan [dir] -> JSON array: {dir,file,hash,status(new|changed|unchanged),class,indexed}
# `indexed` = whether MEMORY.md still references the file (false = orphan candidate).
cmd_scan() {
  local out='[]' md base h cur status cls indexed idx
  while IFS= read -r md; do
    [ -z "$md" ] && continue
    idx="$md/MEMORY.md"
    while IFS= read -r f; do
      base="$(basename "$f")"
      h="$(sl_hash_file "$f")"
      cur="$(jq -r --arg d "$md" --arg b "$base" '.memory[$d].files[$b] // ""' "$SL_PAGI")"
      status=unchanged
      [ -z "$cur" ] && status=new
      { [ -n "$cur" ] && [ "$cur" != "$h" ]; } && status=changed
      cls="$(classify "$base" "$f")"
      indexed=false
      { [ -f "$idx" ] && grep -qF "$base" "$idx"; } && indexed=true
      out="$(jq -c --arg d "$md" --arg b "$base" --arg h "$h" --arg s "$status" \
        --arg c "$cls" --argjson ix "$indexed" \
        '. += [{dir:$d,file:$b,hash:$h,status:$s,class:$c,indexed:$ix}]' <<<"$out")"
    done < <(find "$md" -maxdepth 1 -type f -name '*.md' | sort)
  done < <(mem_dirs "${1:-}")
  echo "$out"
}

# backup <dir> -> copies the whole memory dir to a timestamped snapshot, prints its path.
cmd_backup() {
  local md="${1:?usage: memory.sh backup <memory-dir>}"
  [ -d "$md" ] || { echo "no such memory dir: $md" >&2; exit 1; }
  local ts safe dest
  ts="$(date +%Y%m%dT%H%M%S)"
  safe="$(sl_safe_key "$md")"
  dest="$SL_MEMSNAP/$safe/$ts"
  mkdir -p "$dest"
  cp -R "$md"/. "$dest"/
  echo "$dest"
}

# advance <dir> -> record file->hash map so unchanged files are skipped next run.
cmd_advance() {
  local md="${1:?usage: memory.sh advance <memory-dir>}"
  local files='{}' base h
  while IFS= read -r f; do
    base="$(basename "$f")"; h="$(sl_hash_file "$f")"
    files="$(jq -c --arg b "$base" --arg h "$h" '. + {($b):$h}' <<<"$files")"
  done < <(find "$md" -maxdepth 1 -type f -name '*.md' | sort)
  jq --arg d "$md" --argjson f "$files" --arg t "$(date -u +%FT%TZ)" \
    '.memory = (.memory // {}) | .memory[$d] = {files:$f, lastRunAt:$t}' \
    "$SL_PAGI" | sl_atomic_write "$SL_PAGI"
  echo "advanced cursor for $md ($(jq 'length' <<<"$files") files)"
}

case "${1:-scan}" in
  scan)    shift 2>/dev/null || true; cmd_scan "${1:-}" ;;
  backup)  shift; cmd_backup "${1:-}" ;;
  advance) shift; cmd_advance "${1:-}" ;;
  *) echo "usage: memory.sh {scan [dir] | backup <dir> | advance <dir>}" >&2; exit 1 ;;
esac
