# Model x Effort routing rubric

The two dials on every Claude call: **intelligence** (which model) and **effort** (reasoning
depth: low / medium / high / xhigh / max). This rubric says which pair fits which work, so
cheaper/faster tiers carry everything that does not need the expensive ones.

## Intelligence tiers (cheapest -> strongest)

| Model | Use for | Never for |
|-------|---------|-----------|
| **haiku** | mechanical: renames, codemods, boilerplate, log/grep parsing, lint/build gate reading, simple extraction, high-volume cheap classification | anything needing judgment, review verdicts, synthesis |
| **sonnet** | typical UI/feature/test implementation, doc writing, standard code review, most builders/fixers | deep architecture, adversarial verification, cross-cutting synthesis |
| **opus** | architecture, perf/concurrency, hard integrations, adversarial verify, final synthesis, orchestrator judgment | mechanical or well-specified work (this is the #1 waste) |

If your plan exposes a tier above opus, treat it as a separate lever: it usually bills against
its own weekly bucket, so moving work onto it relieves the all-models cap but is rarely a $
saving per token. Decide from your own `ccusage` numbers and your plan's limits, and record the
decision here so a future run does not re-derive it.

## Pricing

Look up current per-token prices at https://platform.claude.com/docs/en/about-claude/pricing
before relying on any $ estimate - rates change, and introductory rates expire. Record the
snapshot you used (date + table) in the run's digest so the estimate is auditable.

## Effort ladder (match to task, not to "importance")

- **low** - deterministic, well-specified, mechanical. (haiku gates, codemods)
- **medium** - typical implementation and review.
- **high** - multi-file reasoning, non-trivial review/QA, synthesis.
- **xhigh** - adversarial verification, hardest reviews, many-constraint architecture.
- **max** - rare; deepest analysis only (e.g. the nightly self-learn analysis pass).

Effort is orthogonal to model: a haiku codemod is `low`, an opus adversarial verify is `xhigh`.
Raising effort on a mechanical task buys nothing but latency and tokens.

## Decision procedure

For each routing site (a `--model` flag, a skill `model:` pin, a workflow `agent({model,effort})`
call, an agent's default, or the session default):

1. Classify the task class it runs (mechanical / typical / drafting-or-orchestration / hard-reasoning).
2. Pick the **cheapest** tier that meets the quality bar for that class (table above).
3. Pick the **lowest** effort that meets it (ladder above).
4. Quantify: from ccusage, estimate $ and latency delta of the change.
5. Confidence: HIGH only if the task class is unambiguous and the change is reversible.

## Anti-patterns to flag

- Opus on mechanical / well-specified work (renames, log parsing, web search, health digests).
- `max`/`xhigh` effort on boilerplate.
- haiku/low on adversarial verification, final synthesis, or architecture (under-provisioning -> rework, which costs MORE).
- A whole workflow pinned to one tier (e.g. every stage opus) instead of tiered per stage.

## Evidence discipline

Every recommendation cites specific routing sites (file:line) and ccusage numbers, states the
task class, the current vs proposed (model, effort), the estimated $/latency saving, and a
confidence. Never overfit one project's needs onto another. Under-provisioning that causes
rework is a *regression*, not a saving - weigh quality first.
