---
name: kz-learn
description: "Short alias for the self-learn skill: forwards to /kaizen:self-learn under the plugin, /self-learn on a clone install. Typed shortcut only - it carries no engine logic."
argument-hint: "[apply | propose | --batch N | --repos r1,r2 | status | rollback <id> <version>]"
disable-model-invocation: true
---

# kz-learn - short alias for self-learn

Resolve the real skill directory:

```bash
. "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/skill-dir.sh" && sl_skill_dir self-learn
```

Read the `SKILL.md` in the directory it prints and follow it exactly, passing `$ARGUMENTS`
through unchanged. Every rule lives there; this file only saves typing.

If the command prints nothing and fails, self-learn is not installed: install it with
`/plugin install kaizen@jb-kaizen` or the clone installer, then retry.
