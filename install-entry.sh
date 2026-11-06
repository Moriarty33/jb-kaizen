#!/usr/bin/env bash
# install-entry.sh - the one-line installer behind npx, brew and curl: two questions, then install.sh does the rest.
# shellcheck disable=SC2034  # answer variables are read by the sourced lib/ files and install.sh
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SL_HOME="${SELF_LEARN_HOME:-$CLAUDE_DIR/self-learn}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
MARKETPLACE="${JB_KAIZEN_MARKETPLACE:-Moriarty33/jb-kaizen}"
HOPLY_URL=""; ASK=0; ASSUME_YES=0; HOPLY_ONLY=0; HOPLY_SKIP=0; HOPLY_STDIN=0; PASS=()

usage() {
  cat <<'EOF'
jb-kaizen - JB Kaizen for Claude Code, with the Hoply day review.

  jb-kaizen                      two questions: the recommended set [Y/n] (n = type the skills
                                 you want), then your Hoply token (Enter skips); defaults for the rest
  jb-kaizen --yes                recommended set, no questions, Hoply skipped
  jb-kaizen --hoply              only connect Hoply (asks for the token, hidden)
  jb-kaizen --hoply-token-stdin  read the token from stdin instead of asking (scripts)
  jb-kaizen --no-hoply           never ask about Hoply
  jb-kaizen --hoply-url URL      another Hoply MCP endpoint, e.g. http://localhost:3000/mcp
  jb-kaizen --ask                ask the questions even without a terminal (answers from stdin)
  jb-kaizen --version | --help

Any other flag goes to install.sh (install.sh --help lists them), e.g. --workspace ~/code.
Needs Claude Code (claude on PATH), git, jq and python3.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    "--yes"|-y) ASSUME_YES=1; shift ;;
    "--ask") ASK=1; shift ;;
    "--hoply") HOPLY_ONLY=1; shift ;;
    "--no-hoply") HOPLY_SKIP=1; shift ;;
    "--hoply-token-stdin") HOPLY_STDIN=1; shift ;;
    "--hoply-url") HOPLY_URL="${2:?--hoply-url needs a URL}"; shift 2 ;;
    "--version"|-V) cat "$SRC/VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) PASS+=("$1"); shift ;;
  esac
done
if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then ASK=1; fi
if [ "$ASSUME_YES" -eq 1 ]; then ASK=0; fi

say()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
PLUGIN_MODE=0
. "$SRC/lib/install-skills.sh"
. "$SRC/lib/install-recommended.sh"
. "$SRC/lib/install-hoply.sh"

if ! command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Claude Code is not installed (no `claude` on PATH). Install it, then run this again:
  curl -fsSL https://claude.ai/install.sh | bash        (or: npm install -g @anthropic-ai/claude-code)
  docs: https://code.claude.com/docs/en/setup
EOF
  exit 1
fi

step "JB Kaizen $(cat "$SRC/VERSION")"
if [ "$HOPLY_ONLY" -eq 0 ]; then
  if [ "$ASK" -eq 1 ]; then rec_ask; fi
  if [ "$REC_MODE" = plugin ] && [ -d "$CLAUDE_DIR/skills/self-learn" ]; then
    REC_MODE="clone"; say "a clone install is already here - upgrading it in place (the plugin is not added)"
  fi
  case "$REC_MODE" in
    plugin)
      entry_plugin_install
      # shellcheck disable=SC2046  # the flag set is plain words
      bash "$SRC/install.sh" --plugin --yes $(rec_plugin_flags) ${PASS[@]+"${PASS[@]}"} ;;
    clone) bash "$SRC/install.sh" --yes ${PASS[@]+"${PASS[@]}"} ;;
    pick)
      case ",$REC_SKILLS," in *,self-learn,*) ;; *) export SELF_LEARN_SKILL_DIR="$SRC/skills/self-learn" ;; esac
      # shellcheck disable=SC2046
      bash "$SRC/install.sh" --yes $(rec_pick_flags) ${PASS[@]+"${PASS[@]}"} ;;
  esac
fi

if [ "$HOPLY_SKIP" -eq 0 ]; then
  if [ "$HOPLY_STDIN" -eq 1 ]; then hoply_step stdin || exit $?
  elif [ "$ASK" -eq 1 ]; then hoply_step ask
  elif [ "$HOPLY_ONLY" -eq 1 ]; then echo "--hoply asks for the token: run it in a terminal, or pipe it with --hoply-token-stdin" >&2; exit 2
  fi
fi
hoply_summary
