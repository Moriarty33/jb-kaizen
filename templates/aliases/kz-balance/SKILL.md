---
name: kz-balance
description: "Short alias for the model-balance skill: forwards to /kaizen:model-balance under the plugin, /model-balance on a clone install. Typed shortcut only - it carries no engine logic."
argument-hint: "[propose | apply | status]"
disable-model-invocation: true
---

# kz-balance - short alias for model-balance

Resolve the real skill directory:

```bash
. "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/skill-dir.sh" && sl_skill_dir model-balance
```

Read the `SKILL.md` in the directory it prints and follow it exactly, passing `$ARGUMENTS`
through unchanged. Every rule lives there; this file only saves typing.

If the command prints nothing and fails, model-balance is not installed: install it with
`/plugin install kaizen@jb-kaizen` or the clone installer, then retry.
