---
name: kz-setup
description: "Short alias for the setup skill: forwards to /kaizen:setup under the plugin, and points clone or bootstrap installs at the terminal wizard. Typed shortcut only - it carries no engine logic."
disable-model-invocation: true
---

# kz-setup - short alias for setup

Resolve the real skill directory:

```bash
. "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/lib/skill-dir.sh" && sl_skill_dir setup
```

If it prints a path, read the `SKILL.md` there and follow it exactly, passing `$ARGUMENTS`
through unchanged. Every rule lives there; this file only saves typing.

If it prints nothing and fails, this is a clone or bootstrap install, where `setup` ships
plugin-only. Tell the user to configure through the terminal wizard instead - `./install.sh
--wizard` in their `jb-kaizen` checkout (`~/.jb-kaizen` for the bootstrap path) - and that the
answers it writes live in `${SELF_LEARN_HOME:-~/.claude/self-learn}/config.json`. Change nothing.
