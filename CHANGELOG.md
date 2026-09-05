# Changelog

All notable changes to this extension are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

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
