# Concrete Claude Code guardrail knobs (verified against v2.1.220, current as of 2026-07-31)

Claude Code re-tuned subagent fan-out controls three times between 2026-07-21 and 2026-07-24
(v2.1.217 -> v2.1.219). Use this table when filling in a loop's BUDGET row or auditing an
existing one - "a budget ceiling" is not itself an answer; one of these is.

| Control | Default | Set via | Since | Enforcement |
|---|---|---|---|---|
| Concurrent subagents | 20 | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` | v2.1.217 | Hard cap - **not enforced in sessions with ultracode active** |
| Subagents per session (total) | 200 | `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` | v2.1.212 | Hard cap - raisable without bound, cannot be turned off |
| Subagent spawn (nesting) depth | 3 | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` | v2.1.219 (was 1) | Hard cap - set to `1` to disable nesting entirely |
| Spend ceiling | none | `--max-budget-usd` (print-mode `-p` only) | pre-existing; **background-subagent enforcement bug fixed v2.1.217** | Hard cap - spawning fails with "Budget limit reached"; already-running background subagents are halted, not just blocked from spawning more |
| Network egress (sandboxed fleet) | prompt-on-first-contact | `sandbox.network.strictAllowlist` (settings.json) | v2.1.219 | Silent-deny for non-allowlisted hosts - subagents share the parent session's sandbox config, so this closes the network gap for the *whole* fanned-out fleet at once, not just the top-level session |
| Workflow concurrent agents | 16 (or fewer on low-core machines) | not configurable | Workflow tool | Hard runtime cap regardless of settings |
| Workflow total agents/run | 1000 | not configurable | Workflow tool | Hard runtime cap - backstop, not a target |
| Workflow size guideline | medium (<15 agents) | `workflowSizeGuideline` setting or `/config` | v2.1.219 (was unrestricted) | Advisory only - "sent to Claude as advice, not a cap" |

## The gotcha that matters most for this skill's audit

**None of the three subagent-count caps (concurrency/session-total/depth) are enforced in
sessions with `ultracode` active, and the large-workflow warning never fires there either.**
`/maestro` and any `/loop`/scheduled job explicitly run at high autonomy are exactly the
loops this skill exists to harden - and exactly the loops where the count-based caps quietly
do nothing. For those, the audit checklist's "Per-run budget ceiling present" item should be
read as "does this loop set `--max-budget-usd` explicitly", not "do the platform defaults
cover it" - they don't, for this case.

## Applying to the audit checklist

When `/loop-audit` checks "Per-run budget ceiling (tokens / $ / sub-agents) present" for a
scheduled job (self-learn or any other unattended job), grep the job's
invocation for `--max-budget-usd` and any of the three env vars above. Absence of
`--max-budget-usd` on an ultracode-mode loop is a P0 finding, not a P2 - the concurrency cap
that would normally be the backstop is silently off.
