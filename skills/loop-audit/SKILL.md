---
name: loop-audit
description: >
  Designs or audits an unattended / scheduled agent loop before it is trusted to run
  unwatched. Pins down its 6-part contract (TRIGGER, SCOPE, ACTION, BUDGET, STOP, REPORT)
  and proves it cannot run away via three guardrails (iteration cap, no-progress detection,
  budget ceiling). Use when setting up a cron/launchd job or /loop, when a scheduled job spun
  without finishing or burned tokens for nothing, or when the user says "audit my nightly
  jobs", "is this loop safe to leave running", "harden the scheduled agents". Diagnoses
  only - never edits job scripts unless asked. Invoke with /loop-audit on a standalone install
  and /kaizen:loop-audit under the plugin. Also triggers on Ukrainian phrasings:
  "перевір нічні джоби".
argument-hint: "[job name | script path]  (no arg = audit all known scheduled jobs)"
allowed-tools: Read, Bash, Grep, Glob
compatibility: Designed for Claude Code
---

# loop-audit - make an unattended loop provably safe before you walk away

A loop that runs while you sleep needs more than a cron line. Before you `/schedule` or
`/loop` anything, pin down its contract and prove it cannot spin forever, burn budget, or
"succeed" while achieving nothing. After it exists, audit it against the same checklist.

This complements the runners, it does not replace them: your scheduler (launchd, cron,
systemd) fires the job, `/loop` runs interactive loops, and your job log or digest reads the
results. This skill is the design contract and the guardrail audit that sits in front of all
of them.

## The 6-part contract - answer all six, explicitly

| Part | Question | Smell of a bad answer |
|------|----------|-----------------------|
| TRIGGER | What fires it, how often? | "whenever" with no stated cadence |
| SCOPE | Exactly what may it touch (repos, branches, files, envs)? | "the workspace" / unbounded |
| ACTION | The single job per tick? | three jobs crammed into one loop |
| BUDGET | Hard ceiling per run: max sub-agents, tokens/$, wall-clock? See `references/subagent-guardrail-knobs.md` for the concrete flags/env-vars. | none, or "the platform defaults cover it" on an ultracode-mode loop (they don't - see reference) |
| STOP | Exit rules (see guardrails below)? | only the time trigger |
| REPORT | Where the outcome + a status marker lands? | "it logs somewhere" |

A loop with a TRIGGER and no STOP is a bug, not a feature.

## The three runaway guardrails - all three, every loop

1. **Iteration cap** - a hard `MAX_ITER`; never an unbounded `while true`.
2. **No-progress detection** - exit when the same error, an empty diff, or unchanged state
   repeats N times. Time and iteration caps alone do NOT catch a loop that looks busy but
   achieves nothing. This is the guardrail most setups are missing.
3. **Budget ceiling** - a per-run token / dollar / sub-agent limit; stop the moment it is crossed.

## Status markers - close the REPORT loop

Each run should emit an explicit terminal status, not just "it ran":
`DONE / BLOCKED / INCOMPLETE / SKIPPED / AUTH_FAIL / TRANSIENT_FAIL`. The REPORT reads the
marker, not a raw exit code. (The bundled `lib/claude-retry.sh` emits `RETRY-WRAPPER:` lines in
this vocabulary; new loops should emit the same so one digest can classify every job.)

## Background-session autopush (since Claude Code 2.1.212)

Since Claude Code 2.1.212, a "background session" (as opposed to headless `claude -p` print-mode)
commits and pushes by default to preserve work, opening a draft PR only when the task calls for one.
A loop that spawns background sessions inherits this default even if the loop's own contract
never mentions git. Verify per job:

1. Confirm the launchd `ProgramArguments` invoke `claude -p` (headless, no autopush) rather than
   a daemon-managed background session. `PlistBuddy -c "Print :ProgramArguments" <plist>` on the
   job's `~/Library/LaunchAgents/*.plist`.
2. If a job legitimately needs a background session (e.g. it forks a long sub-task), check the
   SCOPE line names the exact repo/branch it may push to, and REPORT captures the push/PR link
   so it surfaces in your job digest rather than landing unnoticed.

## Self-verification - something that can say no

"Half of loop engineering is design; the other half is something that can say no." Each tick:
act, then verify the state measurably changed (a test passed, a commit landed, a value was
written), then correct or exit. If verification fails twice on the same cause, mark `BLOCKED`
and stop - do not retry forever.

## Audit checklist - run this over an existing loop

For each scheduled / looping job, confirm:

- [ ] STOP condition exists and is not merely the time trigger
- [ ] Iteration cap present (no unbounded `while`)
- [ ] No-progress / repeat-N exit present
- [ ] Per-run budget ceiling present - concretely: `--max-budget-usd` set (mandatory if the loop
      runs at ultracode/high autonomy, since the count-based caps are not enforced there; see
      `references/subagent-guardrail-knobs.md`)
- [ ] SCOPE narrowed to named repos / branches / files / envs
- [ ] Emits an explicit terminal status marker the REPORT reads
- [ ] Skip-permissions / destructive flags only inside an isolated worktree or container
- [ ] State persisted so a crash resumes from the last checkpoint, not from scratch
- [ ] If the job can spawn a 2.1.212-or-newer "background session" (`/bg`, backgrounded
      `claude agents`, background `/fork`) rather than headless `claude -p`, confirm its autopush
      behavior is accounted for - either the job only ever runs headless (no autopush), or any
      push it makes is scoped and expected, not a silent side effect

## How to run

1. Resolve targets. With an argument, audit that job or script. With none, find the scheduled
   jobs: `launchctl list | grep -i claude` and the launchd plists under
   `~/Library/LaunchAgents/` (macOS), `systemctl --user list-timers` (Linux), `crontab -l`,
   plus any `scripts/*.sh` referenced by skills such as self-learn. `Grep` the scripts - do
   not dump them into context.
2. For each loop, fill in the 6-part contract from what the script actually does, then walk the
   audit checklist.
3. Report a matrix: `loop | missing guardrails | suggested fix`. Diagnose only - propose the fix,
   do not edit the job script unless the user asks.

## Output

A per-loop table of which contract parts and guardrails are present vs missing, the single
highest-risk gap per loop, and a one-line suggested fix. End with the count of loops audited and
how many are fully guarded.
