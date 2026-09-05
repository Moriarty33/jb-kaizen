#!/usr/bin/env bash
# install_summary - print the final "Done" report at the end of install.sh.
# Reads the caller's install-run variables (SL_HOME, PLUGIN_MODE, SKILL_DIR,
# CLAUDE_DIR, WITH_HOOK, SCHEDULE, SCHED_TIME, VSCODE_LAUNCHER, VSCODE_GRAPHIFY,
# $0) and calls the caller's step/say/yn_default helpers - meant to be sourced,
# never run standalone.

install_summary() {
  local sl; sl="/self-learn"; [ "$PLUGIN_MODE" -eq 1 ] && sl="/kaizen:self-learn"
  step "Done"
  cat <<EOF
  Config:   $SL_HOME/config.json   (re-run the questions: $0 --wizard)
  Skills:   $([ "$PLUGIN_MODE" -eq 1 ] && echo "$SKILL_DIR  (delivered by the plugin)" || echo "$CLAUDE_DIR/skills/{self-learn,model-balance,loop-contract}")
  Store:    $SL_HOME   (epoch $(jq -r .epoch "$SL_HOME/state.json" 2>/dev/null || echo 0), $(jq -r '[.repos[] | select(.enabled)] | length' "$SL_HOME/registry.json" 2>/dev/null || echo 0) repos studied)
  Hook:     $(if [ "$PLUGIN_MODE" -eq 1 ]; then echo "delivered by the plugin"; elif [ "$WITH_HOOK" = 1 ]; then echo "$CLAUDE_DIR/hooks/skill-router.py"; else echo "skipped"; fi)
  Nightly:  $([ "$SCHEDULE" = 1 ] && echo "scheduled at $SCHED_TIME" || echo "not scheduled (re-run with --schedule)")
  VS Code:  claude-launcher=$(yn_default "$VSCODE_LAUNCHER") graphify-watch=$(yn_default "$VSCODE_GRAPHIFY")

  Next:
    1. In any project:   claude  ->  $sl status      (where am I?)
    2. First real pass:  $sl                          (propose only - nothing is edited)
    3. Apply what you like:  $sl apply
    4. New project later:    it joins on the next run; or right away: $SKILL_DIR/scripts/register.sh <path>
EOF
}
