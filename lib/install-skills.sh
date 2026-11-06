#!/usr/bin/env bash
# install-skills.sh - the clone-install skill copy, sourced by install.sh (needs put, seed, run, say, step, sl_is_ours).

# Generic names a person may already own: ours only when SKILL.md carries the JB Kaizen marker.
KZ_MARKED_SKILLS="hoply-day commit review-code fix-pr-comments github"

skill_marked() { case " $KZ_MARKED_SKILLS " in *" $1 "*) return 0 ;; esac; return 1; }
skill_wanted() { case ",${SKILLS_CSV:-all}," in ,all,|*",$1,"*) return 0 ;; esac; return 1; }

# Every shippable skill name, comma-separated (setup is plugin-only: it needs CLAUDE_PLUGIN_ROOT).
skills_available() {
  local d out=""
  for d in "$SRC"/skills/*/; do
    d="$(basename "$d")"; [ "$d" = setup ] && continue
    out="${out:+$out,}$d"
  done
  printf '%s' "$out"
}

skills_installed_list() { case "${SKILLS_CSV:-all}" in all) skills_available ;; *) printf '%s' "$SKILLS_CSV" ;; esac; }

install_skills() {
  local sk name dest f rel old d
  if [ "$PLUGIN_MODE" -eq 1 ]; then step "Skills"; say "skip    delivered by the plugin"; return 0; fi
  step "Installing skills into $CLAUDE_DIR/skills"
  for name in $(skills_installed_list | tr ',' ' '); do
    [ -d "$SRC/skills/$name" ] || say "WARN    no skill named '$name' - skipped"
  done
  for sk in "$SRC"/skills/*/; do
    name="$(basename "$sk")"
    [ "$name" = setup ] && continue
    dest="$CLAUDE_DIR/skills/$name"
    if ! skill_wanted "$name"; then
      if [ -d "$dest" ] && { ! skill_marked "$name" || sl_is_ours "$dest"; }; then run rm -rf "$dest"; say "removed $dest (not chosen)"; fi
      continue
    fi
    if skill_marked "$name" && [ -d "$dest" ] && ! sl_is_ours "$dest"; then
      say "keep    $dest (your own $name skill; ours is skipped)"; continue
    fi
    while IFS= read -r f; do
      rel="${f#"$sk"}"
      case "$rel" in
        references/learned-patterns*.md|journal/*) seed "$f" "$dest/$rel" ;;
        *.bak-*) ;;
        *) put "$f" "$dest/$rel" ;;
      esac
    done < <(find "$sk" -type f | sort)
    [ "$DRY" -eq 1 ] || chmod +x "$dest"/scripts/*.sh 2>/dev/null || true
  done
  for old in loop-contract kaizen-setup setup; do   # renamed in 1.1.1/1.1.2; `setup` may be the user's own, so it goes only with our marker
    d="$CLAUDE_DIR/skills/$old"; [ -d "$d" ] && { [ "$old" != setup ] || sl_is_ours "$d"; } && { run rm -rf "$d"; say "removed $d (renamed)"; } || true
  done
}
