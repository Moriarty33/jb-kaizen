---
name: kz-audit
description: "Short alias for the loop-audit skill: forwards to /kaizen:loop-audit under the plugin, /loop-audit on a clone install. Typed shortcut only - it carries no engine logic."
argument-hint: "[job name | script path]  (no arg = audit all known scheduled jobs)"
disable-model-invocation: true
---

# kz-audit - short alias for loop-audit

Resolve the real skill directory:

```bash
. "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/skill-dir.sh" && sl_skill_dir loop-audit
```

Read the `SKILL.md` in the directory it prints and follow it exactly, passing `$ARGUMENTS`
through unchanged. Every rule lives there; this file only saves typing.

If the command prints nothing and fails, loop-audit is not installed: install it with
`/plugin install kaizen@jb-kaizen` or the clone installer, then retry.
