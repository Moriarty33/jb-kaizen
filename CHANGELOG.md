# Changelog

All notable changes to this extension are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [1.2.0] - 2026-11-06

One line installs it all, and JB Kaizen pairs with [Hoply](https://hoply.work) for a daily time review.

### Added
- One-line installers: `npx -y jb-kaizen`, `brew install moriarty33/tap/jb-kaizen && jb-kaizen`, and
  the existing `curl ... bootstrap.sh | bash`. All three run `install-entry.sh`, which asks at most two
  questions: the recommended set [Y/n] (n = type the skills you want, comma separated; that is a clone
  install of just those skills, since a plugin always delivers all of its skills), then the Hoply token
  (hidden, Enter skips). Flags: `--yes`, `--hoply`, `--hoply-token-stdin`, `--no-hoply`, `--hoply-url`, `--ask`.
- `hoply-day` skill: reads the day from the Hoply MCP server (entries, meetings, GitHub sessions,
  proposals, sync state), lets the person confirm, fix or dismiss, and writes only after an explicit yes.
- The 17:15 Europe/Kyiv offer, on two channels sharing one stamp per day: the `hoply-day-nudge.py`
  hook (SessionStart and UserPromptSubmit, stdlib only, silent and offline unless due) and a workday
  desktop notification (launchd `StartInterval` 900 on macOS, a `Mon..Fri` systemd timer on Linux).
- Hoply token handling: `~/.config/hoply/token` (0600) read by a `headers.sh` helper (0700) that Claude
  Code runs per connection, so the token never lands in `~/.claude.json`.
- Four bundled general skills: `commit`, `review-code` (with `rules.md`), `fix-pr-comments`, `github`.
- `install.sh --skills LIST` and `--hoply-reminder / --no-hoply-reminder`, remembered in `config.json`
  (`skills`, `hoply.reminder`); `uninstall.sh --hoply` removes the MCP entry and `~/.config/hoply`.
- `npm/` package (`jb-kaizen`, bin `jb-kaizen`) and `brew/jb-kaizen.rb` formula for the tap.
- `/kaizen:setup` gains an eighth question (connect Hoply) and sends the token to the terminal, never the chat.

### Changed
- `bootstrap.sh` hands off to `install-entry.sh`; an existing clone install keeps upgrading in place.
- `install.sh --help` text moved to `lib/install-help.txt`, the skill copy to `lib/install-skills.sh`.

## [1.1.2] - 2026-09-05

Both invocation forms are supported from here on: the discoverable namespaced commands the
plugin gives for free, and short ones for daily typing.

### Added
- Short alias skills `/kz-setup`, `/kz-learn`, `/kz-audit` and `/kz-balance`, installed into
  `~/.claude/skills/` by `install.sh` in both the clone and the plugin mode. Claude Code has no
  `alias` field and a plugin skill is always `/<plugin>:<skill>`, so each alias is a personal
  forwarder skill of under 25 lines: it resolves its target with `sl_skill_dir` and follows that
  `SKILL.md`, carrying no engine logic of its own. They are `disable-model-invocation: true`, so
  Claude never auto-invokes an alias and they never compete with the real skills for triggering.
- `install.sh --aliases / --no-aliases`, remembered as `aliases: true|false` in
  `config.json` (default true). `--no-aliases` installs none and removes any previously
  installed alias directory, so switching the answer off actually takes them away.
  `uninstall.sh` removes all four.

### Changed
- **BREAKING**: the plugin's `kaizen-setup` skill is `setup` again - the command is
  `/kaizen:setup` (or the new `/kz-setup`), dropping the `kaizen:kaizen-` stutter. The skill
  stays plugin-only, so a bare `/setup` can never collide with a skill of your own.
- Both forms now appear side by side in the docs: `/kaizen:self-learn` and `/kz-learn`,
  `/kaizen:model-balance` and `/kz-balance`, `/kaizen:loop-audit` and `/kz-audit`,
  `/kaizen:setup` and `/kz-setup`. On a clone install the long forms stay unnamespaced
  (`/self-learn`, ...), and `/kz-setup` points at the terminal wizard, which is where clone and
  bootstrap installs configure.

### Fixed
- The rename prune in `install.sh` **and `uninstall.sh`** no longer deletes a
  `~/.claude/skills/setup` you wrote yourself: under that generic name a directory is removed only
  when its `SKILL.md` carries the JB Kaizen marker. The unambiguous pre-1.1.2 names
  (`loop-contract`, `kaizen-setup`) are still pruned unconditionally.
- `/kaizen:setup` now says the four short aliases are part of the install and accepts "no" for
  them, so the plugin-only route has the same opt-out as `./install.sh --no-aliases`.
- `uninstall.sh` takes the alias list from `lib/install-aliases.sh` instead of repeating it, so
  the two can no longer drift.

### Upgrade notes
- After `/plugin update`, use `/kaizen:setup` (not `/kaizen:kaizen-setup`) and finish with an
  installer run so the aliases land; on a clone install `./install.sh` prunes a stale
  `~/.claude/skills/kaizen-setup` left by 1.1.1.
- Keep the short commands out with `./install.sh --no-aliases`; the namespaced commands are
  unaffected either way.

## [1.1.1] - 2026-09-05

### Changed
- **BREAKING**: the `setup` skill is now `kaizen-setup` - `/kaizen:kaizen-setup` under the plugin
  (the skill is plugin-only; clone and bootstrap installs use the terminal wizard). The old bare
  `/setup` was generic enough to collide with a user's own skill and to trigger on unrelated prompts.
- **BREAKING**: the `loop-contract` skill is now `loop-audit` - `/kaizen:loop-audit`. No script or
  cross-skill reference depended on the old name; only typed invocations change.
- Skill frontmatter conventions: `compatibility` on every skill, `model: sonnet` on `model-balance`,
  `allowed-tools` and `argument-hint` on the Maestro skill, and third-person opening clauses in the
  descriptions.
- One multilingual policy across the skills: English triggers first, then a closing
  "Also triggers on Ukrainian phrasings" clause.
- `kaizen-setup` asks its seven questions in the language the user is writing in, instead of a
  hardcoded one.
- `self-learn` SKILL.md split under the 500-line guidance: Pass-2 corpus forensics moved to
  `references/corpus-forensics.md` and the Phase 2.7 rules to `references/memory-distillation.md`.
- `self-learn` `allowed-tools` drops the `Task*` entries that resolve to nothing.

### Added
- `repository` in `.claude-plugin/plugin.json`.

### Removed
- The root-level `version` in `.claude-plugin/marketplace.json`, which duplicated the plugin
  version and could drift from it.

### Upgrade notes
- After `/plugin update`, use `/kaizen:kaizen-setup` and `/kaizen:loop-audit`. On a clone or
  bootstrap install, `install.sh` prunes the renamed skill directories (`loop-contract`, `setup`)
  and migrates an existing routing map from `loop-contract` to `loop-audit` automatically.

## [1.1.0] - 2026-09-05

### Added
- Plugin packaging: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- `hooks/hooks.json` delivering the routing hook via `${CLAUDE_PLUGIN_ROOT}` - no `settings.json`
  edit needed under a plugin install.
- The `/kaizen:setup` skill: a non-interactive wizard for first install and reconfiguration through
  the plugin, where a skill's `Bash` call has no TTY for the interactive one.
- `bootstrap.sh`: one-command clone-or-update path that opens the same wizard.
- `lib/skill-dir.sh`: the one skill-dir resolution rule, shared by the nightly runner and the
  skill scripts.
- `claude plugin validate` in CI.

### Changed
- `install.sh --plugin`: skips what the plugin already delivers (skills copy, hook registration).
- The nightly prompt, the nightly runner, and the skill docs resolve the skill directory through
  `lib/skill-dir.sh` instead of hardcoding `~/.claude/skills/self-learn`.
- Skills appear as `/kaizen:self-learn`, `/kaizen:model-balance`, `/kaizen:loop-contract` and
  `/kaizen:setup` under the plugin.

### Upgrade notes
- `nightly-prompt.txt` and `routing/routing-map.json` are seeded, never overwritten, so existing
  installs keep their old text as-is. To pick up the new text, move
  `~/.claude/self-learn/nightly-prompt.txt` (and `routing/routing-map.json`) aside and re-run
  `install.sh`.
- A machine that already had a clone install and then installs the plugin ends up with **two**
  routing-hook registrations - the old `skill-router` entry in `~/.claude/settings.json` is still registered
  alongside the one the plugin delivers. `install.sh --plugin` warns about this; remove the old one
  with `./uninstall.sh`, or delete the `skill-router` entry from `~/.claude/settings.json` by hand.

## [1.0.0] - 2026-09-04

First public release. Extracted from a private setup that ran the engine nightly for
66 epochs (June - September 2026) across ~70 repositories.

### Added
- `self-learn` skill v0.16 lineage: resumable cursors over commits, PR reviews, session
  transcripts and per-project memories; snapshot-before-edit versioning; propose-by-default;
  2-of-3 adversarial verification with a hard 45-agent ceiling; crash-safe Phase-3.5
  checkpoint; routing-map maintenance; memory distillation & compaction.
- `model-balance` companion skill: model x effort routing audit from `ccusage` data.
- `loop-contract` companion skill: 6-part contract + three runaway guardrails for any
  unattended loop.
- `hooks/skill-router.py`: zero-cost `UserPromptSubmit` nudge driven by the learned routing map.
- `lib/claude-retry.sh`: bounded retries, wall-clock budget, process-group kill, auth-failure
  short-circuit, grep-able status markers.
- `install.sh` / `uninstall.sh`: idempotent, backup-first, launchd / systemd scheduling,
  private-store remote wiring.
- `install.sh` setup wizard, seven steps that each explain themselves: dependencies with
  per-tool install offers (brew / apt / npm / uv), repo roots, per-repo on/off, hook,
  nightly time, private remote, VS Code companions. Answers persist in `config.json`;
  precedence on every run is flags > saved config > defaults, and a run outside a
  terminal never asks.
- `vscode/` companions, source plus prebuilt `.vsix`: `claude-launcher` (rocket button
  that opens `claude` at the window root) and `graphify-watch` (keeps the graphify graph
  of the open folder current); `vscode/install-vscode.sh` installs them via the `code` CLI.
- `discover.sh --list` (dry listing for the wizard) and a roots fallback to the registry,
  so the roots chosen at install time drive every later run.
- `tests/smoke.sh` + CI on ubuntu and macos: installs into a throwaway HOME and exercises
  every script against synthetic repos, transcripts and a local bare remote.

### Changed (vs the private lineage)
- The READMEs and `docs/ARCHITECTURE.md` show designed SVG diagrams (light and dark, picked by
  `<picture>`) generated from `docs/diagrams/*.py`, instead of GitHub's default mermaid rendering;
  CI fails when the committed SVGs drift from their sources.
- `sync.sh` pulls with rebase before pushing, so a merged PR on the store remote no longer
  breaks every following nightly push.
- `lib.sh` gained portable `sl_mtime` / `sl_hash_file` (GNU + BSD userland).
- `discover.sh` registers the canonical root (`git rev-parse --show-toplevel`), the same key
  `paginate.sh` and `register.sh` derive, so a repo reached through a symlink no longer gets
  a second registry entry and a second cursor.
- `corpus.sh` engine-session markers are extensible via `SELF_LEARN_ENGINE_MARKERS`.
- `night-guard-settings.json` uses `Read(...)` / `Edit(...)` deny rules (the only kinds the
  file-permission checks match) and adds `.ssh` / `.aws` / `.gnupg` and destructive git commands.
- `nightly-run.sh` passes `--max-budget-usd` - the one spend ceiling that survives
  high-autonomy fan-out.
