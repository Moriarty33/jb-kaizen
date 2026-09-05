#!/usr/bin/env bash
# install-aliases.sh - the short alias skills (/kz-setup, /kz-learn, /kz-audit, /kz-balance).
#
# Aliases are thin personal skills: Claude Code has no `alias` field and a plugin skill is
# always `/<plugin>:<skill>`, so a short command can only exist as a directory in
# $CLAUDE_DIR/skills/. Each one forwards to the real skill and holds no engine logic.
#
# Sourced by install.sh (which provides put(), say(), step(), run(), SRC, CLAUDE_DIR, DRY and
# the ALIASES answer) and by uninstall.sh, which needs aliases_remove only and brings its own
# say/run; the fallbacks below cover a caller that brings neither. Never run standalone.

SL_ALIASES="kz-setup kz-learn kz-audit kz-balance"

# A skills/<name> dir is ours only when its SKILL.md carries the marker (a user may own /setup).
sl_is_ours() { grep -qs 'JB Kaizen' "$1/SKILL.md"; }

declare -F say  >/dev/null || say()  { printf '  %s\n' "$*"; }
declare -F step >/dev/null || step() { printf '\n==> %s\n' "$*"; }
declare -F run  >/dev/null || run()  { "$@"; }

# "/kz-setup, /kz-learn, ..." for the install summary.
aliases_list() {
  local a out=""
  for a in $SL_ALIASES; do out="${out:+$out, }/$a"; done
  printf '%s' "$out"
}

# Install them ($1 = the ALIASES answer), or remove any left over when the answer is now no.
aliases_apply() {
  local a
  if [ "${1:-${ALIASES:-1}}" = 1 ]; then
    step "Installing short aliases into $CLAUDE_DIR/skills"
    for a in $SL_ALIASES; do
      put "$SRC/templates/aliases/$a/SKILL.md" "$CLAUDE_DIR/skills/$a/SKILL.md"
    done
  else
    step "Short aliases"
    say "skip    --no-aliases (the namespaced commands still work)"
    aliases_remove
  fi
}

aliases_remove() {
  local a d
  for a in $SL_ALIASES; do
    d="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/skills/$a"
    [ -d "$d" ] || continue
    run rm -rf "$d"
    say "removed $d"
  done
}
