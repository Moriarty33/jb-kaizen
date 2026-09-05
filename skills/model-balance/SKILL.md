---
name: model-balance
description: Analyzes model + effort usage across all Claude Code sessions and rebalances the two dials - intelligence (haiku/sonnet/opus) and effort (low/medium/high/xhigh/max) - so cheaper, faster tiers carry everything that does not need the expensive ones, saving cost and latency with no quality loss. Reads ccusage spend distribution + config routing sites (--model in job/skill scripts, skill frontmatter, workflow agent() calls) and flags over-provisioning (opus where sonnet/haiku suffices) and mis-provisioning. Hybrid apply - auto-applies high-confidence reversible config edits backup-first, defers risky ones to a journal for review. Runs manually and as Phase 2.8 inside self-learn. Use when the user says "balance the models", "optimize model usage", "which models am I overusing", "we could save cost/speed on models", "where can I save on models", or types /model-balance.
argument-hint: [propose | apply | status]
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, AskUserQuestion
model: sonnet
compatibility: Designed for Claude Code
---

# model-balance - intelligence x effort routing optimizer

Rebalances which model and which effort level each Claude Code routing site uses, driven by
real spend data, so the setup spends the least while keeping quality. The reference decision
matrix is [references/routing-rubric.md](references/routing-rubric.md) - read it first every run.

**Scope (hard rule):** read/write only within `~/.claude` and your workspace. Never touch
personal folders. Read-only except for the config edits you apply under the hybrid boundary below.

## Modes

- `/model-balance` or `propose` (default): analyze and produce the recommendations digest; apply nothing.
- `apply`: analyze, then apply under the hybrid boundary (auto-apply safe, journal the rest).
- `status`: show the last run's digest + what was applied/deferred, no new analysis.

## Procedure

SKILL DIR: resolve once - `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/model-balance` if it exists,
else the newest match of `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/kaizen/*/skills/model-balance`.
Every `<skill-dir>/…` path below means that directory. The skill is `/model-balance` on a
standalone install and `/kaizen:model-balance` under the plugin - same skill.

### 1. Collect (one read-only command)

```
bash <skill-dir>/scripts/collect-stats.sh
```

Gives: spend distribution by model (weekly + all-time, cost-equiv from `ccusage`), the explicit
`--model` routing sites in job/skill scripts, skill-frontmatter model/effort pins, and the tiers
workflows actually pick. This is the evidence base - do not re-derive it by hand. Add extra
job directories to scan via `MODEL_BALANCE_EXTRA_DIRS="dir1 dir2"`.

**Reading live usage:** `ccusage` gives cost-equiv $ and per-model distribution only - not the
plan's weekly-limit %. `/usage` is a client-side CLI command the model cannot call and its % is
not on disk, so when a run needs the live weekly-cap % lead by asking the user to run `/usage`
and paste it - don't spend turns saying "I can't". Derive a literal cap from what you have:
`cap_usd ≈ this_week_ccusage_cost / (pasted /usage %)`.

### 2. Classify each routing site

For every site the collector surfaces (a `--model` flag, a skill `model:` pin, a workflow
`agent({model,effort})` choice, an agent's inherited default, the session default), determine the
task class it runs and apply the rubric's decision procedure. Agents/*.md declare no model/effort -
a recommendation for them targets either their invocation site or an explicit frontmatter addition.

Optionally corroborate with session transcripts under `~/.claude/projects/*/` (in-scope only):
look for under-provisioning signals (retries, "that's wrong" corrections, re-runs) that mean a
cheaper tier already hurt quality - those sites should NOT be downgraded.

### 3. Rank recommendations

Each recommendation is a concrete diff: `site (file:line) - task class - current (model, effort)
-> proposed (model, effort) - est. $/latency saving - confidence`. Sort by (confidence x saving).

Typical standing candidates (verify against fresh data each run, do not hardcode): unattended
job scripts running `--model opus` for web-search / log-digest / summary work that sonnet or
haiku handles - high-confidence downgrades. `self-learn` on the strongest tier is defensible
(deep multi-agent analysis and adversarial verification) - leave unless evidence says otherwise.

### 4. Hybrid apply boundary

- **Auto-apply (backup-first, reversible only):** a single-line `--model` change in a job script,
  or a skill-frontmatter `model:`/`effort:` change, where the task class is unambiguous and
  confidence is HIGH. Back up the file first (`cp <f> <f>.bak-modelbalance-<date>`), edit, note it.
- **Defer to journal (never auto-apply):** anything touching the session default or interactive
  behavior; any under-provisioning (raising a tier) unless evidence shows current quality loss;
  changes to many sites at once; anything you are not HIGH-confident is reversible and safe.
- Never downgrade a site where transcripts show the cheaper tier already caused rework.

### 5. Write the digest

Write `<skill-dir>/journal/<date>.md`: the spend snapshot, applied changes
(with backup paths + est. saving), deferred candidates as `- [ ]` checkboxes for the user to
approve, and one line of "what next run should watch." When run as a self-learn phase, fold these
into the self-learn journal instead of a separate file.

## Non-negotiables

- Quality first: a downgrade that causes rework costs MORE - weigh it as a regression, not a saving.
- Evidence-backed only: cite file:line + ccusage numbers for every claim; no vibes.
- Reversible: every applied edit is backed up; list the exact revert command in the digest.
- Never overfit one project's routing onto another.
