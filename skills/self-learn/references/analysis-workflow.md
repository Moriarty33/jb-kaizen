# Multi-agent analysis workflow (Phase 4)

This is the engine for Phase 4. It turns a batch of learnings (from commits, PR comments,
sessions and memories) plus the inventory of agents/skills into a set of verified, minimal
improvement proposals.

Pass two things in:

- `candidates` - array of `{id, type, path, status}` from `inventory.sh` (filter to
  `new` + `changed`, plus any `unchanged` item the learnings explicitly implicate).
- `learnings` - array of `{note, evidence}` where `evidence` points to a commit hash,
  a session path + line range, or a PR review comment (`<repo>#<pr> <path>:<line>`).

> **PR review comments are the highest-yield learnings for review/fix/planning agents.**
> A recurring class of reviewer finding (missing input validation, DTO/schema drift,
> dropped validation pipes, untyped responses, etc.) is direct evidence of what the
> **reviewer** agent should check, what the **fixer** should pre-empt, and what the
> **architect/critic** should bake into the plan up front. When a learning comes from PR
> comments, target the proposal at those agents specifically, and prefer "add this to the
> review checklist / plan criteria" over generic wording. Distinguish **bot** comments
> (noisy, weight low) from **human** reviewer comments (high signal).

> **Engine rule 1 - feed the workflow data as script literals, not via `args`.**
> Inline `args` objects have arrived at the pipeline as `undefined`. Build
> `candidates`/`learnings` directly as literals in the script body. If you must use `args`,
> guard it: `const A = typeof args === 'string' ? JSON.parse(args) : (args || {})`.

The pipeline runs each candidate through **propose -> adversarially verify** independently,
so a fast candidate finishes while a slow one is still being analyzed (no barrier).

```javascript
export const meta = {
  name: 'self-learn-analyze',
  description: 'Propose + verify token/cycle improvements for agents and skills from real evidence',
  phases: [{ title: 'Propose', model: 'opus' }, { title: 'Verify', model: 'opus' }],
}

const PROPOSAL = {
  type: 'object',
  properties: {
    id: { type: 'string' },
    proposals: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          summary: { type: 'string' },
          rationale: { type: 'string' },          // why - in plain terms
          evidence: { type: 'string' },           // commit hash, session:line, or repo#pr
          nearestExistingText: { type: 'string' },// closest related text found, quoted with file:line
          oldText: { type: 'string' },            // exact unique substring to replace ('' if pure addition)
          diff: { type: 'string' },               // the concrete edit
          tokenSaving: { type: 'string' },        // estimate, e.g. "~15% shorter prompt"
          cycleSaving: { type: 'string' },        // e.g. "removes a re-read loop"
          qualityGuard: { type: 'string' },       // why nothing regresses
          bump: { type: 'string', enum: ['patch', 'minor', 'major'] },
        },
        required: ['summary', 'rationale', 'evidence', 'nearestExistingText', 'oldText', 'diff', 'qualityGuard', 'bump'],
      },
    },
  },
  required: ['id', 'proposals'],
}

const VERDICT = {
  type: 'object',
  properties: {
    keep: { type: 'boolean' },
    reason: { type: 'string' },
    correction: { type: 'string' },   // verifier's corrected edit text when keep=true but the proposal over-reaches
  },
  required: ['keep', 'reason'],
}

// Build these as literals in the script body (see Engine rule 1). Prose values (notes,
// rationales) must be JSON-encoded, never hand-quoted - see Engine rule 12.
const candidates = [/* inline the real array here */]
const learnings = JSON.stringify([/* inline the real array here */])

// Hard agent ceiling for the whole phase (propose + verify). See "Phase-4 budget ceiling".
const MAX_AGENTS = 45
const VERIFIERS = 3                       // 2-of-3 majority
let budget = MAX_AGENTS - candidates.length   // propose agents are spent up front
let dropped = 0                          // proposals never verified because the cap ran out
const takeWithinBudget = (proposals) => {
  const out = []
  for (const p of proposals) {
    if (budget - VERIFIERS < 0) { dropped++; continue }
    budget -= VERIFIERS
    out.push(p)
  }
  return out
}

const results = await pipeline(
  candidates,

  // Stage 1: propose minimal improvements for ONE item, grounded in the learnings.
  (c) => agent(
    `Read the ${c.type} at ${c.path}. Here are learnings from recent commits, PR reviews and ` +
    `sessions: ${learnings}. Propose ONLY minimal, evidence-backed edits that reduce ` +
    `token use and/or wasted cycles WITHOUT lowering quality. The optimization rubric:\n` +
    `- cut redundant/duplicated instruction; prefer a bundled script over prose for any ` +
    `deterministic multi-step sequence the transcripts show being reinvented;\n` +
    `- remove steps that the transcripts show caused rework; front-load the decision that ` +
    `gates the most downstream work;\n` +
    `- NEVER drop a rule unless evidence shows it is dead or harmful; every proposal must ` +
    `cite its evidence and a qualityGuard explaining why nothing regresses;\n` +
    `- quote the nearest existing text you found (file:line) even when you conclude the rule ` +
    `is absent, and give oldText as an exact unique substring of the file.\n` +
    `If the item is already lean, return an empty proposals array - do not invent churn.`,
    // Engine rule 2: read-only agent. Only Phase 5 touches files (snapshot-then-Edit).
    { label: `propose:${c.id}`, phase: 'Propose', schema: PROPOSAL, agentType: 'Explore', model: 'opus' }
  ),

  // Stage 2: adversarially verify each proposal with a 2-of-3 majority; default to rejecting.
  (proposal, c) => parallel(takeWithinBudget(proposal?.proposals || []).map((p) => () =>
    parallel(Array.from({ length: VERIFIERS }, (_, i) => () =>
      agent(
        `Adversarially review this proposed edit to ${c.id}:\n${JSON.stringify(p)}\n` +
        `Try to REFUTE it. Open the file and check oldText is an exact unique substring and that ` +
        `nearestExistingText is quoted accurately. Reject (keep=false) if: it removes a rule ` +
        `without hard evidence, trades any quality for speed, overfits to a single commit, ` +
        `duplicates a rule already live in the file, or its token/cycle saving is negligible ` +
        `relative to the risk. Default to keep=false when unsure. If you keep it but the wording ` +
        `over-reaches, put the narrowed text in correction.`,
        { label: `verify:${c.id}#${i + 1}`, phase: 'Verify', schema: VERDICT, agentType: 'Explore', model: 'opus' }
      )
    )).then((votes) => ({ ...p, id: c.id, votes }))
  ))
)

const confirmed = results
  .flat()
  .filter(Boolean)
  .filter((p) => p.votes.filter((v) => v?.keep).length * 2 > p.votes.length)

return { confirmed, skippedForBudget: dropped }
```

## How the main skill uses the result

`confirmed` is the apply-list for Phase 5. In `propose` mode, render each entry as a
human diff with its rationale, evidence, savings, and quality guard, and ask the user
which to apply. In `apply` mode, for each: `snapshot.sh <id> <bump>` then `Edit` the file,
preferring a verifier's `correction` text over the original proposal when one was supplied.

> **Engine rule 3 - adjudicate every "confirmed", don't auto-apply the list.** Even with a
> 2-of-3 majority, the verifiers' dissent is often the correct signal: a minority flag has
> caught a *second* hardcode the majority missed, and "confirmed" items have referenced config
> fields that did not exist. Read each confirmed proposal against its own evidence before
> snapshotting. Reject anything whose rationale admits "no evidence of rework", or that
> references a field/path you cannot verify exists.

## Phase-4 budget ceiling (HARD - loop-audit guardrail)

**Never launch more than 45 agents in one Phase 4** (propose + verify combined). The script
above enforces it with a counter; count before you launch anyway. If the candidate list would
exceed the ceiling, TRIM THE CANDIDATES, never the verify majority. Without a cap, nightly
runs have been measured at 54-111 agent transcripts and a 5x cost spread night to night.

Trim order when over budget (highest-value work survives):
1. Candidates unchanged since the last epoch (`inventory.sh` says `unchanged`) - drop first.
2. Candidates already improved within the last 3 epochs - drop next.
3. Never drop: a candidate named by a Phase-2.7 feedback distillation, or one cited by a
   PR review theme from Phase 1b.

Carry the dropped candidates forward in the journal as the next run's head of queue, so the
ceiling defers work rather than losing it.

## Scaling the analysis to the user's intent

- "quick learn" or a small batch -> a single verifier per proposal is enough.
- "be thorough" / large batch / many repos -> run multiple propose passes per candidate with
  different lenses (token-cost lens, cycle-cost lens, missing-rule lens) and union the
  proposals before the verify stage; keep the 2-of-3 verifier majority.

Keep the verify stage strict regardless of scale - the entire value of this skill is that
it never trades quality for speed. The **2-of-3 verifier majority + human adjudication** is
the proven default for a thorough run, not just the large-batch option.

## Hard-won engine rules (do not relearn these)

1. **Feed data as literals, not `args`.** Inline `args` reached the pipeline as `undefined`.
2. **Analysis agents are read-only (`agentType: 'Explore'`).** A propose agent with write
   tools once auto-applied an edit before its snapshot. Only Phase 5 touches files.
3. **Adjudicate every confirmed proposal.** Verifier dissent is often right; the majority can
   both over-confirm churn and under-fix a real leak. Re-read evidence before applying.
4. **Project-agnostic only for global items.** Never bake one project's branch/language/
   ticket-prefix/bot/deploy convention into a global agent or skill - that belongs in the
   project's own config.
5. **No-evidence = no edit.** Pre-agent / third-party git history yields project facts but
   zero agent-behavior signal; it justifies no tooling change on its own.
6. **Pin the model on both stages explicitly** (`model` on the `phases` entries AND on each
   `agent()` call) - an unset `model` silently inherits the session model. Keep verify on the
   strongest tier you run: the adversarial verify stage is what kills fabricated evidence and
   false premises, and it is the larger stage. Propose can run a cheaper tier if an A/B on
   your own runs shows it decision-equivalent.
7. **FREEZE every carrier file for the whole Phase-4 window.** Land Phase 2.6/2.7/2.8 edits
   strictly BEFORE the launch or strictly AFTER the return - never while the workflow runs.
   Verifiers adjudicate the live tree, so a concurrent edit turns a real finding into a false
   "already-live duplicate" rejection.
8. **Require `nearestExistingText` and `oldText` in the propose schema.** Prose telling the
   agent to "verify absence" fails; a required output slot catches it, and the quote is what
   lets a verifier isolate the real delta. Verifiers check `oldText` byte-for-byte.
9. **Enforce the agent ceiling with a counter in the script, not arithmetic before launch.**
   JS is single-threaded, so a decremented budget is safe across concurrently-scheduled
   stage-2 calls.
10. **A user naming a skill is NOT evidence the skill executed.** Before writing a proposal
    against a carrier, grep the cited transcript for the actual `Skill{skill:"<name>"}`
    invocation or a read of its SKILL.md.
11. **Carrier reach decides whether an edit can prevent anything.** Before adding a rule to a
    skill or agent, prove its body actually loads on the path where the failure happens
    (grep transcripts for its SKILL.md read, or the job script that pipes it in). A rule in a
    file that never loads prevents nothing. Note that a global `CLAUDE.md` reaches top-level
    sessions but is not attached to subagent or workflow-agent transcripts.
12. **JSON-encode prose; never hand-quote it into the script.** An apostrophe closes a
    single-quoted literal, a backtick opens a template literal, and each costs a full
    re-author of the script mid-run. Build every prose value as data and paste the
    `JSON.stringify(...)` output.
13. **Dedupe on target, not on `(file, summary)`.** Many confirmed proposals collapse to the
    same few edits; count distinct targets when reporting, and merge overlapping diffs before
    applying.
