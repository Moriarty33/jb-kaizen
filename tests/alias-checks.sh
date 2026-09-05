# shellcheck shell=bash
# shellcheck disable=SC2154  # harness variables come from smoke.sh
# Short-alias checks, split out of smoke.sh to keep it under its line cap.
# Sourced from smoke.sh in section 2, after the first full install has run.

for a in kz-setup kz-learn kz-audit kz-balance; do
  check test -f "$CLAUDE_CONFIG_DIR/skills/$a/SKILL.md"
  check grep -qx 'disable-model-invocation: true' "$CLAUDE_CONFIG_DIR/skills/$a/SKILL.md"
  check grep -qx "name: $a" "$CLAUDE_CONFIG_DIR/skills/$a/SKILL.md"
done
check bash -c 'set -e; [ "$(ls -d "$1"/skills/kz-* | wc -l | tr -d " ")" = 4 ]; ! grep -rql Phase "$1"/skills/kz-*' _ "$CLAUDE_CONFIG_DIR"

# ---- 2b. --no-aliases round-trip: installs none, removes existing ----
check bash "$ROOT/install.sh" --no-aliases --yes --workspace "$WS"
check test ! -d "$CLAUDE_CONFIG_DIR/skills/kz-learn"
check jq -e '.aliases == false' "$SELF_LEARN_HOME/config.json"
