# Memory distillation & compaction - the Phase 2.7 rules

Load this when Phase 2.7 runs. `scripts/memory.sh` owns the deterministic scan/backup/cursor
primitives; everything below is the judgement the model has to make.

For each **changed/new memory with `class: feedback`** (whatever its filename), run the
distill-or-retire test:
- Identify the single skill/agent that *should* enforce the rule (e.g. a "PR review must be a
  pending review" memory -> `global:skill:review-pr`). Grep that target before concluding anything.
- **ENCODED** (target already enforces it): the memory is now redundant - mark it `archive`.
- **PARTIAL / MISSING**: emit a **learning** for Phase 4/5 - a minimal edit that makes the skill/agent enforce the rule. Once that edit lands (snapshot-first), the memory becomes redundant -> `archive` with a pointer to the new version.
- **CROSS_CUTTING** (applies to many skills, not one): its home is the global `CLAUDE.md`, not a single skill. Encode once there, then `pointer`.

A feedback memory is a *bug report against the skills* - either the skill learns the rule, or
the memory proves the skill already knows it. Either way the memory stops being needed
verbatim. **When every memory in a store names the same skill, that is not a memory problem -
it is an unencoded skill, and the store is doing the skill's job at global context cost.**

For each memory with **`class: project`**, judge lifecycle: if the linked work shipped (PR
**MERGED**, ticket **Done**, or the entry itself says merged/deployed/shipped) it is an
**archive** candidate; genuinely active work stays in the index. Do not guess - when a status
is unclear, keep it and note it in the journal.

**Compaction** (reversible, snapshot-first):
```bash
BK=$(bash scripts/memory.sh backup <dir>)   # full copy of the memory dir FIRST
```
Then: `mkdir -p <dir>/archive`; move each archived file into `<dir>/archive/`;
replace its `MEMORY.md` line with a one-line pointer (`- Title -> archived (encoded in <id> v<x>)`)
or drop the line entirely for shipped work; fix orphans (add a pointer or archive the file);
dedupe overlapping `reference_*` entries; rewrite `MEMORY.md` lean. **Never delete** - archive +
pointer only. Preserve every active-work and durable `reference_`/`user_` entry. Finally:
```bash
bash scripts/memory.sh advance <dir>         # move the memory cursor forward
```

**Apply boundary (hybrid).** Auto-apply, snapshot-first: (a) high-confidence feedback->skill
gap-fills, and (b) the reversible compaction above. **Defer to the journal** (do not auto-apply):
skill *restructures*, archival of a `project` memory whose status you could not confirm, and any
edit touching many skills at once. Evidence discipline: a feedback memory is only archived when
its rule is provably ENCODED in a named skill/agent *version* (cite it).
