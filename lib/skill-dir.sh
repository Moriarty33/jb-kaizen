#!/usr/bin/env bash
# sl_skill_dir [skill-name] - resolve the on-disk directory for a self-learn skill.
# Default skill-name is "self-learn". Prints the resolved path on stdout and nothing
# else; returns non-zero (printing nothing) when no candidate exists.
#
# Calling convention for `set -euo pipefail` callers:
#   X="$(sl_skill_dir)" || { echo "self-learn: skill dir not found" >&2; exit 1; }
#
# Resolution order (first match wins):
#   1. $SELF_LEARN_SKILL_DIR, when set and a directory (only for the "self-learn" skill)
#   2. ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/<name>, when it is a directory
#   3. newest match of ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/kaizen/*/skills/<name>
#   4. otherwise return 1, printing nothing

sl_skill_dir() {
  local name c d p
  name="${1:-self-learn}"
  c="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

  if [ "$name" = "self-learn" ] && [ -n "${SELF_LEARN_SKILL_DIR:-}" ] && [ -d "${SELF_LEARN_SKILL_DIR:-}" ]; then
    printf '%s\n' "$SELF_LEARN_SKILL_DIR"
    return 0
  fi

  if [ -d "$c/skills/$name" ]; then
    printf '%s\n' "$c/skills/$name"
    return 0
  fi

  # Newest plugin-cache match without a pipeline: an inherited `set -o pipefail` would turn
  # `ls | head -1` into a SIGPIPE failure once the cache grows; `-nt` needs no external command.
  set -- "$c"/plugins/cache/*/kaizen/*/skills/"$name"
  [ -d "$1" ] || return 1
  d=""
  for p in "$@"; do
    [ -d "$p" ] || continue
    if [ -z "$d" ] || [ "$p" -nt "$d" ]; then d="$p"; fi
  done
  [ -n "$d" ] || return 1
  printf '%s\n' "$d"
}

# sl_kaizen_skill_dirs - print every kaizen plugin-cache skill directory, one per line.
sl_kaizen_skill_dirs() {
  local c d; c="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  for d in "$c"/plugins/cache/*/kaizen/*/skills/*/; do
    [ -d "$d" ] || continue; printf '%s\n' "${d%/}"
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then sl_skill_dir "$@"; fi
:
