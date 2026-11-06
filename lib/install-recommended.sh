#!/usr/bin/env bash
# install-recommended.sh - question 1 of the one-line installer and the answer sets it maps to; sourced by install-entry.sh.
# shellcheck disable=SC2034  # answer variables are read by the sourced lib/ files and install.sh

REC_FRESH_FLAGS="--schedule 03:07 --hook --aliases --vscode none --hoply-reminder"
REC_MODE="plugin"; REC_SKILLS=""

# ask VAR "question" - reads stdin (piped answers drive it in tests); returns 1 on EOF.
entry_ask() {
  local __var="$1" __in=""
  printf '  %s ' "$2"
  if IFS= read -r __in; then printf -v "$__var" '%s' "$__in"; return 0; fi
  echo; printf -v "$__var" '%s' "$__in"; [ -n "$__in" ]
}

# "Commit, /kaizen:github ,x" -> "commit,github"; unknown names are reported on stderr and dropped.
rec_valid_skills() {
  local raw name out="" available; available=",$(skills_available),"
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ',' ' ')"
  for name in $raw; do
    name="${name#/}"; name="${name#kaizen:}"
    case "$available" in
      *",$name,"*) case ",$out," in *",$name,"*) ;; *) out="${out:+$out,}$name" ;; esac ;;
      *) echo "  unknown skill: $name" >&2 ;;
    esac
  done
  printf '%s' "$out"
}

rec_ask() {
  local ans="" picked=""
  say "Recommended: the kaizen plugin with every skill ($(skills_available | sed 's/,/, /g')),"
  say "nightly learning at 03:07, the routing hook, the /kz-* aliases and the workday Hoply reminder."
  entry_ask ans "Install the recommended set? [Y/n]" || true
  case "$ans" in n|N|no|No|NO) ;; *) REC_MODE="plugin"; return 0 ;; esac
  REC_MODE="pick"
  while :; do
    entry_ask picked "Type the skills you want, comma separated:" || { echo "no skills chosen - nothing was installed" >&2; exit 1; }
    REC_SKILLS="$(rec_valid_skills "$picked")"
    [ -n "$REC_SKILLS" ] && return 0
    say "none of those is a skill here; pick from: $(skills_available | sed 's/,/, /g')"
  done
}

# A picked set is a clone install of just those skills; the rest follows from what was picked.
rec_pick_flags() {
  local has_learn=0 has_day=0
  case ",$REC_SKILLS," in *,self-learn,*) has_learn=1 ;; esac
  case ",$REC_SKILLS," in *,hoply-day,*) has_day=1 ;; esac
  printf '%s' "--skills $REC_SKILLS --vscode none"
  if [ "$has_learn" = 1 ]; then printf ' %s' --schedule 03:07 --hook --aliases; else printf ' %s' --no-schedule --no-hook --no-aliases; fi
  if [ "$has_day" = 1 ]; then printf ' %s' --hoply-reminder; else printf ' %s' --no-hoply-reminder; fi
}

# A saved config.json means an upgrade: keep its answers rather than re-imposing the recommended ones.
rec_plugin_flags() { [ -f "$SL_HOME/config.json" ] || printf '%s' "$REC_FRESH_FLAGS"; }

entry_plugin_install() {
  local listed
  step "Claude Code plugin kaizen@jb-kaizen"
  listed="$("$CLAUDE_BIN" plugin marketplace list 2>/dev/null || true)"
  case "$listed" in
    *jb-kaizen*) say "keep    marketplace jb-kaizen" ;;
    *) "$CLAUDE_BIN" plugin marketplace add "$MARKETPLACE" | sed 's/^/  /' ;;
  esac
  listed="$("$CLAUDE_BIN" plugin list 2>/dev/null || true)"
  case "$listed" in
    *kaizen@jb-kaizen*) say "keep    kaizen@jb-kaizen (newer version: claude plugin update kaizen@jb-kaizen)" ;;
    *) "$CLAUDE_BIN" plugin install kaizen@jb-kaizen --scope user | sed 's/^/  /' ;;
  esac
}
