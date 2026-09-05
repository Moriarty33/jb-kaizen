#!/usr/bin/env bash
# install-deps.sh - the dependency table for install.sh: what each tool is for, whether it
# is required, and how to install it on this machine. Sourced, not executed.
#
#   deps_report          one status line per tool; exit 1 when a required tool is missing
#   deps_offer_install   (wizard) per missing tool: explain, then ask to install it now
#
# Adding a tool = one line in DEPS. Recipes are picked from what the machine has: Homebrew
# (macOS / Linuxbrew), apt-get (Debian/Ubuntu, via sudo), then the tool's own installer.
# Order matters: a tool that needs another (claude -> npm, graphify -> uv) comes after it.

# name ^ required ^ what it is for ^ brew ^ apt ^ own installer ^ needs   ("-" = none)
DEPS='
git^yes^reads the commit history of every registered repo^git^git^-^-
jq^yes^every state file in the store is JSON^jq^jq^-^-
python3^yes^the routing hook and the transcript scan^python^python3^-^-
node^no^npm installs the claude CLI; rebuilds the VS Code companions^node^nodejs npm^-^-
claude^run^Claude Code CLI - the engine runs inside it^-^-^npm install -g @anthropic-ai/claude-code^npm
gh^no^GitHub CLI - mines PR review comments (Phase 1b)^gh^gh^-^-
uv^no^Python tool manager - the one-line way to install graphify^uv^-^curl -LsSf https://astral.sh/uv/install.sh | sh^-
graphify^no^knowledge graph per repo: agents query a scoped subgraph instead of grepping; brings the /graphify skill^-^-^uv tool install graphifyy && graphify install --platform claude^uv
code^no^VS Code CLI - installs the two editor companions^--cask visual-studio-code^-^-^-
'

dep_present() { command -v "$1" >/dev/null 2>&1; }

# The install command for this machine, or nothing when no recipe applies.
dep_install_cmd() {
  local brew="$1" apt="$2" own="$3"
  if [ "$brew" != "-" ] && dep_present brew; then echo "brew install $brew"
  elif [ "$apt" != "-" ] && dep_present apt-get; then echo "sudo apt-get install -y $apt"
  elif [ "$own" != "-" ]; then echo "$own"
  fi
}

deps_report() {
  local name req why brew apt own needs missing=0
  while IFS='^' read -r name req why brew apt own needs; do
    [ -n "$name" ] || continue
    if dep_present "$name"; then say "ok      $name"; continue; fi
    case "$req" in
      yes) say "MISSING $name (required) - $why"; missing=1 ;;
      run) say "WARN    $name not on PATH - $why; install it before the first run" ;;
      *)   say "absent  $name (optional) - $why" ;;
    esac
  done <<< "$DEPS"
  return "$missing"
}

# Reads the table on fd 3 so the yes/no prompts still read the user's answers from stdin.
deps_offer_install() {
  local name req why brew apt own needs cmd any=0
  while IFS='^' read -r name req why brew apt own needs <&3; do
    [ -n "$name" ] || continue
    dep_present "$name" && continue
    any=1
    say ""; say "$name - $why"
    if [ "$needs" != "-" ] && ! dep_present "$needs"; then say "  needs $needs first - skipped"; continue; fi
    cmd="$(dep_install_cmd "$brew" "$apt" "$own")"
    [ -n "$cmd" ] || { say "  no recipe for this OS - install it by hand"; continue; }
    yes_no "  Install now with: $cmd" y || continue
    if [ "$DRY" -eq 1 ]; then say "  [dry-run] $cmd"; continue; fi
    if eval "$cmd"; then hash -r; say "  installed $name"; else say "  install failed - carry on and install $name by hand"; fi
  done 3<<< "$DEPS"
  [ "$any" -eq 1 ] || say "nothing missing"
}
