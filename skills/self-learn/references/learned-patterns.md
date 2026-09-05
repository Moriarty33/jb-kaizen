# Learned patterns (accumulated across runs)

This file is the skill's long-term memory of conclusions - distinct from the per-project
memory under `~/.claude/projects/*/memory/`. Phase 0 reads it so each run starts informed
instead of re-deriving the same findings. Append a dated entry per epoch; keep it terse.

> **Keep this file under ~200 KB** - measure with `wc -c`, never `du -h`. It is the Phase 0
> input every run depends on, and the Read tool fails at 256 KB. When it approaches 200 KB,
> rotate the oldest ~15 epochs verbatim into `learned-patterns-archive-<n>.md` and leave a
> pointer here. Do NOT reorder to newest-first - journals cite absolute line offsets.

## Default operating mode (seed - refine from your own runs)

- **Pass 2 (mechanical tool-call failures) carries a mature setup; Pass 1 (user corrections)
  goes quiet.** Run both, never manufacture a Pass-1 finding.
- **Zero is a claim about your literal, not about the corpus** until a positive control of
  the same class hits.
- **Every keep-vote worth shipping came with a `correction`.** Expect the verifiers'
  narrowed text to be what lands, not the proposal's.
- **Carrier reach first.** A rule added to a file that never loads on the failing path
  prevents nothing. Prove the body loads before proposing.
- **Close classes with numbers.** A class whose newest event predates the carrier fix that
  addresses it is CLOSED - say so in the journal and stop proposing against it.
- **Budget: 45 agents per Phase 4, 2-of-3 verify majority, propose and verify on the
  strongest tier you run.** Trim candidates, never verifiers.

## Epoch log

_(append one dated entry per epoch below: coverage, edits applied with evidence, classes
closed, what the next run should focus on)_
