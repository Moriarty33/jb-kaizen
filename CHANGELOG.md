# Changelog

All notable changes to this extension are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

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
