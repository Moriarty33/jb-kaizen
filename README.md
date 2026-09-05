<p align="center">
  <img src="docs/assets/banner.png" alt="JB Kaizen for Claude Code - your setup gets better every night" width="100%">
</p>

<h1 align="center">JB Kaizen for Claude Code</h1>

<p align="center">
  <b>A nightly job that reads what you and Claude actually did today, then rewrites your skills and agents so tomorrow costs fewer tokens, fewer retries and less of your attention.</b>
</p>

<p align="center">
  <a href="#install"><img alt="install" src="https://img.shields.io/badge/install-one%20command-7dd3fc?style=flat-square"></a>
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-c4b5fd?style=flat-square"></a>
  <img alt="platforms" src="https://img.shields.io/badge/macOS%20%7C%20Linux-bash%203.2%2B-86efac?style=flat-square">
  <a href="README.uk.md"><img alt="Українською" src="https://img.shields.io/badge/README-українською-fcd34d?style=flat-square"></a>
</p>

---

Claude Code gets its behaviour from files you own: `~/.claude/skills/*/SKILL.md`, `~/.claude/agents/*.md`,
`CLAUDE.md`, per-project memory. They only get better when you sit down and edit them - which is exactly the
kind of chore that never happens. **JB Kaizen** turns that chore into a loop:

1. **Every night** a scheduled `claude -p` run wakes up, reads the *new* evidence since last time - git commits,
   PR review comments, session transcripts, per-project memories - never re-reading history it already processed.
2. It **mines** that evidence for what went wrong mechanically (tool calls that failed and were silently worked
   around), what you corrected, what reviewers keep flagging, and which skill you *meant* but Claude did not pick.
3. A **multi-agent propose → adversarially-verify** workflow turns findings into minimal, evidence-cited edits.
   Every edit needs a 2-of-3 verifier majority; anything that trades quality for speed is rejected.
4. Each surviving edit is **snapshotted, versioned and applied**, and a journal entry explains what changed and why.
   Rolling back is one command.

Run it for a month and the compounding is visible: the reviewer stops missing the same class of bug, the
routing hook sends "check in logs why it happened" to the right skill on the first try, the tokens per task go
down, and you spend the morning on work instead of on re-explaining yourself.

> Extracted from a private setup that ran this loop for **66 consecutive epochs** (June - September 2026) over
> ~70 repositories. Everything project-specific was stripped; every hard-won engine rule stayed.

## How it works

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/how-it-works.en.dark.svg">
  <img alt="How it works: evidence flows into the self-learn engine, which changes skills, agents, the routing map and the journal" src="docs/assets/diagrams/how-it-works.en.light.svg" width="1000">
</picture>

### The nightly run, end to end

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/nightly-run.en.dark.svg">
  <img alt="The nightly run, end to end: timer, nightly-run.sh, claude-retry.sh, claude -p, private store, private remote" src="docs/assets/diagrams/nightly-run.en.light.svg" width="1000">
</picture>

### Why it is safe to leave running

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/guarantees.dark.svg">
  <img alt="Why it is safe to leave running: two-phase cursors, snapshot before edit, unattended guardrails" src="docs/assets/diagrams/guarantees.light.svg" width="1000">
</picture>

- **Evidence or it doesn't ship.** Every edit cites the commit, PR comment or session line that motivates it.
- **Reversible always.** `snapshots/<id>/<version>/` is the source of truth; `/self-learn rollback <id> <version>` restores it.
- **Non-destructive by default.** `/self-learn` proposes; `/self-learn apply` (or the nightly prompt) applies.
- **Lean.** Metadata into context, full diffs and transcripts to `/tmp` and `grep`. The tool that hunts token waste
  is not itself a token sink.

### The feedback → skill loop (Phase 2.7)

Per-project memory is the highest-signal input and the most expensive one: `MEMORY.md` loads into *every* session.
Kaizen treats each feedback memory as a bug report against a skill:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/diagrams/feedback-loop.dark.svg">
  <img alt="Feedback memory to skill: encoded, partial or cross-cutting, then archived with a pointer" src="docs/assets/diagrams/feedback-loop.light.svg" width="1000">
</picture>

Either the skill learns the rule, or the memory proves the skill already knows it. Either way it stops being
loaded verbatim forever.

## Install

Requirements: [Claude Code](https://docs.claude.com/en/docs/claude-code) (CLI on `PATH`), `git`, `jq`, `python3`.
Optional: GitHub CLI `gh` (authenticated) for PR-review mining, `npx ccusage` for the model-balance phase.

```bash
git clone https://github.com/Moriarty33/jb-kaizen.git
cd jb-kaizen
./install.sh                                  # setup wizard: seven questions, Enter keeps the default
```

Each step says what it is for before it asks:

| Step | Asks | Why |
|------|------|-----|
| 1 Dependencies | install what is missing (`gh`, `node`, `uv`, `graphify`, `code`...) | each tool explains itself; `git`, `jq`, `python3` are required, the rest optional |
| 2 Roots | where your git repositories live | one or several directories; new repos under them join automatically |
| 3 Repositories | which of the found repos to study | toggle any off; nothing is written into the projects |
| 4 Routing hook | install the `UserPromptSubmit` nudge | one line when a learned phrasing matches, silent otherwise |
| 5 Nightly | run every night, and when | launchd / systemd --user / crontab line |
| 6 Private remote | back the store up | project names and paths live there: private repos only |
| 7 VS Code | `claude-launcher`, `graphify-watch` | see [Editor companions](#editor-companions) |

Answers are saved to `~/.claude/self-learn/config.json`, so upgrades and other machines re-run silently
(outside a terminal it never asks). `./install.sh --wizard` re-opens the questions; flags skip them for scripted
installs and are remembered: `--workspace DIRS`, `--schedule [HH:MM]`, `--store-remote URL`, `--hook/--no-hook`,
`--vscode LIST`, `--yes`. The install itself puts three skills, a routing hook, the retry library and a private
store in place, then registers every git repo under your roots. Re-running is safe: it upgrades in place, backs
up anything it overwrites, and never touches learned state.

Try it interactively first - nothing is edited in this mode:

```text
claude
> /self-learn status      # epoch 0, what is tracked, what is pending
> /self-learn             # full pass, propose only: shows the diffs it would make and why
> /self-learn apply       # same, but snapshot + apply the approved ones
```

Then let it run while you sleep:

```bash
./install.sh --schedule 03:07                                   # launchd on macOS, systemd --user on Linux
./install.sh --store-remote git@github.com:you/kaizen-store.git  # back the store up to a PRIVATE repo
```

`./install.sh --help` lists every flag; `./uninstall.sh` removes it all (the store stays unless `--purge-store`).

### What gets installed where

| Path | What |
|------|------|
| `~/.claude/skills/self-learn/` | the engine: `SKILL.md`, 14 bash scripts, references (workflow script, routing rubric, learned patterns) |
| `~/.claude/skills/model-balance/` | model × effort routing audit from `ccusage` data (Phase 2.8, optional) |
| `~/.claude/skills/loop-contract/` | design/audit any unattended loop: 6-part contract + three runaway guardrails |
| `~/.claude/hooks/skill-router.py` | `UserPromptSubmit` hook: one-line nudge toward a skill when your learned phrasings match, silent otherwise |
| `~/.claude/lib/claude-retry.sh` | bounded retries, wall-clock budget, process-group kill, auth-fail short-circuit |
| `~/.claude/night-guard-settings.json` | deny-list passed to the nightly run |
| `~/.claude/self-learn/` | **the private store**: cursors, registry, version manifest, snapshots, routing map, journal, nightly job |
| `~/.claude/self-learn/config.json` | your install answers: roots, skipped repos, hook, schedule, remote, VS Code choices |
| `~/.vscode/extensions/local.claude-launcher-*` | optional: rocket button that opens `claude` at the window root |
| `~/.vscode/extensions/local.graphify-watch-*` | optional: keeps the graphify graph of the open folder current |

## What a night looks like

A real journal entry (project names removed) from epoch 66 of the private lineage:

> **8 edits applied.** 0 of 33 verdicts voted keep as-proposed - all 33 supplied a *correction*, so every
> shipped line is a verifier's narrowed text. Two classes CLOSED with numbers and no edit.
>
> **Coverage:** 92 new commits / 9 repos · 47 PRs / 416 comments / 173 human · 1,312 transcripts scanned ·
> 217 memory files, 0 new feedback · 38 agents / 1.37M tokens / 0 errors / 527 s against the 45 ceiling.
>
> `review-code` 0.8 → 0.9: five reviewer-flagged rules, each narrowed so it fires on the defect and not on the
> correct pattern beside it ("a guard that can never fire", "a caught failure answered with 200", "a default
> that points at production"...). `fix-pr-comments` 0.2 → 0.3: suppressed review comments never become thread
> objects and were structurally invisible - 5 occurrences / 3 PRs; fixed with a deterministic re-processing
> gate. `routing-map.json` +5 keywords, each citing the session where a phrasing fired no hint.
>
> **Closed with numbers:** "the user keeps asking for terser output" - 129 regex hits, ~123 were skill text
> echoed into user-role records; genuine requests ≈ 6 across 4 sessions. Not a rule.

That last paragraph is the point: the engine spends as much effort *refuting* its own findings as producing them.

## Editor companions

Two small VS Code extensions ship in `vscode/` (MIT, source plus a prebuilt `.vsix`, installed through the `code`
CLI by wizard step 7 or `vscode/install-vscode.sh`). Both are optional; the engine does not depend on them.

- **claude-launcher** adds a rocket button to the editor title bar. One click opens an editor-area terminal at the
  window's root (the folder, or the directory holding the `.code-workspace` file) and runs
  `claude --permission-mode auto`. Every project is one click from a session, so more of your work lands in the
  transcripts the engine learns from.
- **graphify-watch** keeps a [graphify](https://pypi.org/project/graphifyy/) knowledge graph of the open folder
  current: native VS Code file watching, a debounced one-shot `graphify update` on code changes, the state in the
  status bar, a shrink guard with one automatic `--force` retry, and a lock so two windows never rebuild at once.
  With the graph current, agents answer "how does X relate to Y" from a scoped subgraph instead of grepping the
  tree. Needs `graphify`; wizard step 1 installs it with `uv tool install graphifyy` and adds the `/graphify` skill.

## Configuration

Everything lives in the store, never in your projects.

| Where | Knob |
|-------|------|
| `config.json` | the install answers; edit it or re-run `./install.sh --wizard` |
| `registry.json` | `repos[key].enabled`, `repos[key].config.{batch,maxTotal,botLogins}`, global `botLogins` |
| `nightly-prompt.txt` | the run contract - scope rules, phases, budget; edit freely |
| `scripts/nightly-run.sh` | `SELF_LEARN_MODEL`, `SELF_LEARN_BUDGET_USD`, `CLAUDE_RETRY_TIMEOUT`, `SELF_LEARN_WORKSPACE` |
| `routing/routing-map.json` | the learned phrasings the hook matches (any language, STT mishears included) |
| env `SELF_LEARN_HOME` / `SELF_LEARN_ROOTS` | move the store / override discovery roots for one run |

**New projects** need no setup: every run rescans your roots, `skills/self-learn/scripts/register.sh <path>` enrolls
one the moment you `git init` it, and `./install.sh --wizard` toggles any repo off.

## FAQ

**Will it edit my skills without asking?** Interactively, no - `/self-learn` proposes and stops. The nightly
prompt runs in `apply` mode by design (nobody is there to answer), but it only auto-applies edits that survived
a 2-of-3 adversarial majority *and* are reversible from a snapshot; anything gated (restructures, multi-skill
edits, unconfirmed archivals) is written to the journal for your next interactive session.

**What does it read?** Only `~/.claude` and the workspace it was started in. Sessions whose cwd is elsewhere are
skipped. The deny-list blocks personal folders, `.ssh`/`.aws`/`.gnupg` and destructive git commands at the
permission layer, not just in the prompt.

**What does it cost?** Bounded by `--max-budget-usd` (default 40) and the 45-agent ceiling. A thorough night in
the private lineage ran 30-40 agents and 1-3M tokens; a quiet one exits in minutes with "nothing new".

**Does it work on Linux?** Yes - bash 3.2+ / GNU or BSD userland, no `mapfile`, `timeout` or `declare -A`.
CI runs the smoke test on both `ubuntu-latest` and `macos-latest`.

**Where is my data?** In `~/.claude/self-learn`. If you point it at a remote, that remote holds your project
names, paths, PR themes and distilled feedback - **keep it private**.

**Can I run it for one repo only?** `/self-learn --repos <name>` or set `enabled: false` on the others.

## Development

```bash
bash tests/smoke.sh     # installs into a throwaway HOME and exercises every script (no network, no claude)
```

Layout: `skills/` (installed verbatim), `hooks/`, `lib/`, `templates/` (rendered into the store on install),
`docs/` (architecture, safety), `tests/`. Version in `VERSION`, history in `CHANGELOG.md`.

## Author

Built by **Bogdan Jaminski** - engineering manager, building agent workflows that pay for themselves.
GitHub [@Moriarty33](https://github.com/Moriarty33) · LinkedIn [bogdan-jaminski](https://www.linkedin.com/in/bogdan-jaminski/)

MIT © 2026 Bogdan Jaminski
