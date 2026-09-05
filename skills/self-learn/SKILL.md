---
name: self-learn
description: Self-improvement engine for a Claude Code setup. Reads where it left off (per-branch commit cursor + session cursor in persistent state), ingests the next batch of unprocessed git commits oldest-to-newest, recent session transcripts, PR review comments and per-project memories, then runs a multi-agent propose-and-verify analysis to refine your agents and skills for token/cycle/time efficiency with no quality trade-off - versioning and snapshotting every change. Use this whenever the user wants to "self-learn", "evolve the setup", "improve my agents/skills from recent work", "learn from the last sessions/commits", run a retrospective that actually edits the tooling, or types /self-learn. Resumable - each run continues from the last processed commit/session, never reprocessing the same history.
argument-hint: "[apply | propose | --batch N | --repos r1,r2 | status | rollback <id> <version>]"
allowed-tools: Read, Edit, Write, Grep, Glob, Bash, AskUserQuestion, Agent, Workflow
compatibility: Requires git, jq, bash, and the GitHub CLI for PR mining
---

# self-learn - resumable self-improvement engine

This skill makes your Claude Code setup learn from its own history. Each run picks up
exactly where the last one stopped (persistent cursors), studies a fresh batch of
real evidence - git commits, PR review comments, session transcripts, per-project
memories - and uses that evidence to improve your **agents** and **skills**:
tightening prompts, removing dead weight, encoding patterns that kept recurring, and
cutting token/cycle cost without lowering quality.

Three properties make it safe and worth running repeatedly:

- **Resumable.** Cursors live in `~/.claude/self-learn/`. Commits are read
  oldest-to-newest per branch with a global dedup set, so the same commit is never
  studied twice even when it appears on many branches. "From the very first commit to
  the latest, batch by batch" - and it remembers its place.
- **Versioned.** Every agent/skill is content-hashed and tracked in a manifest. Before
  any edit it is snapshotted to `snapshots/<id>/<version>/`, so every change is
  reversible.
- **Non-destructive by default.** The default mode is `propose`: it shows what it would
  change and why. It only writes to your agents/skills when invoked with `apply` (or
  after you confirm). This also makes the skill safe to test.

## State layout (`~/.claude/self-learn/` = your private config store)

Everything is **centralized** here - one place, versioned in your own private git
repo via `sync.sh`. Nothing is written into the individual projects; per-project
settings are entries in `registry.json`.

| File | Holds |
|------|-------|
| `registry.json` | every known repo/project: `repos[key]` = `{name, path, remote, enabled, config}` + scanned `roots[]` |
| `state.json` | `epoch` (run counter), knowledge-base `version`, `lastRunAt` |
| `config.json` | the installer's answers (roots, skipped repos, hook, nightly schedule, store remote, VS Code companions) - written by `install.sh`, read on every silent re-run |
| `pagination.json` | per-repo `branches[b].lastHash`, global `seen[]`, per-repo `prs.{cursor,openSeen}`, per-project session `lastTs`, per-memory-dir file hashes |
| `versions.json` | manifest: `items[id]` = `{version, hash, snapshot, history[]}` |
| `snapshots/<id>/<v>/` | pre-edit copies (the rollback source of truth) |
| `memory-snapshots/` | pre-compaction copies of each project's memory dir (Phase 2.7) |
| `routing/` | `routing-map.json` + `intent-lexicon.md` (Phase 2.6) |
| `journal/<epoch>-*.md` | one human-readable report per run |
| `pending/<repo>.json` | per-repo batch emitted by paginate, not yet advanced (crash-safety; gitignored) |

`id` format: `<scope>:<type>:<name>`, e.g. `global:agent:reviewer`, `project:<repo>:skill:sync-cdn`.

Override the store location with `SELF_LEARN_HOME` (default `~/.claude/self-learn`).

## Multi-repo: all your projects, centrally configured

self-learn spans **every** repo you work in - not just the current directory. The
registry is the project list; it lives in your private store and updates automatically.

- **Discover** (`scripts/discover.sh [roots...]`) scans your workspace roots (the ones the
  installer saved in `registry.json`; override per run via args or `SELF_LEARN_ROOTS`;
  default `$HOME/workspace`) for git repos and merges them
  into `registry.json`, enabled by default, preserving any existing per-repo config.
  It is idempotent and runs at the start of every full run, so a **new project on disk
  is picked up automatically** the next time self-learn runs.
- **Register a new project immediately** (`scripts/register.sh <path> [name]`) when you
  don't want to wait for the next sweep - e.g. right after `git init` on a new project.
- **Per-repo config** is central: `registry.json -> repos[key].config` (`{batch, maxTotal}`)
  and `repos[key].enabled`. Disable a repo you don't want studied; nothing is ever
  written into the project itself.
- **Bot-comment filtering** (Phase 1b): `pr-paginate.sh` flags bot comments so they don't
  pollute the human-signal count. Beyond GitHub's `user.type=="Bot"`, it catches universal
  CI/bot login patterns (`*[bot]`, `dependabot`, `github-actions`, `reviewdog`, `copilot`)
  and the reviewdog inline-report marker. CI accounts that post as a plain *user*
  (e.g. a coverage/quality bot) go in `registry.json -> .botLogins` (global) or
  `repos[key].config.botLogins` (per-repo) - never hardcoded in the script.
- **Sync to your private repo** (`scripts/sync.sh`): the store IS a git repo. One-time
  `sync.sh init <git-remote-url>` points it at your private remote; thereafter `sync.sh`
  pulls (rebase), commits and pushes after each run so config + memory are backed up and
  shared across machines. Pushing is your call - run init with the remote you choose.
  **The store contains your project names, paths and distilled feedback - keep that
  remote private.**

## Arguments (`$ARGUMENTS`)

- empty or `propose` -> full run, **propose only** (no edits to agents/skills)
- `apply` -> full run and apply approved improvements (snapshot first, then edit)
- `status` -> print current epoch/version/cursors and exit (just runs `state.sh status`)
- `--batch N` -> commits per branch this run (default 40, total cap 200)
- `--repos r1,r2` -> also analyze these registered repos (default: current repo only)
- `rollback <id> <version>` -> restore an item from its snapshot and exit

All scripts live in `scripts/` next to this file: resolve once - `$SELF_LEARN_SKILL_DIR` if set,
else `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/self-learn` if it exists, else the newest match of
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/*/kaizen/*/skills/self-learn` - giving
`<skill-dir>/scripts`. Invoke this
skill as `/self-learn` on a standalone install and `/kaizen:self-learn` under the plugin - same
skill. They are plain bash + `jq`; PR mining additionally needs the GitHub CLI (`gh`). Make them
executable on first run: `chmod +x <skill-dir>/scripts/*.sh` (the plugin cache already ships them
executable).

---

## Phase 0 - Orient ("where am I?")

The user's first question is always "what version am I, and where did I stop?". Answer it
before doing anything else.

0. Read `references/learned-patterns.md` - conclusions and the default operating mode
   from previous runs, so you start informed instead of re-deriving them. Also glance at
   `routing/intent-lexicon.md` so you start with the user's known phrasings loaded (Phase 2.6).
1. `bash scripts/state.sh status` - read epoch, version, tracked cursors, items.
2. If step 1 reported `pendingBatches > 0`, a previous run emitted batches into `pending/`
   but never advanced. Decide: re-use them (continue those batches) or discard
   (`rm ~/.claude/self-learn/pending/*.json`) and re-paginate. Default: continue them.
   If a `journal/<state.epoch + 1>-*.partial.md` is also present, that dead run already
   wrote down what it ingested (Phase 3.5) - read it instead of re-deriving coverage from
   `pending/`.
3. If `$ARGUMENTS` is `status`, print a short summary and stop here.
4. If `$ARGUMENTS` starts with `rollback`, run
   `cp` from `snapshots/<safe-id>/<version>/` back over the live path, report, and stop.

Report to the user in one compact block: current epoch, KB version, per-branch cursors,
how many sessions/commits are pending, and what this run will do.

## Phase 1 - Refresh registry + paginate commits (the unread history)

First refresh the project list so new repos are included:

```bash
bash scripts/discover.sh        # merges all workspace git repos into the registry
```

Then read the next batch of unprocessed commits, oldest-first per branch, for each
enabled repo. By default focus on the current repo plus the repos the user named; for a
broad run, iterate every enabled repo in the registry:

```bash
# current repo:
bash scripts/paginate.sh ${BATCH:-40} 200
# a specific registered repo:
bash scripts/paginate.sh --repo /path/to/repo ${BATCH:-40} 200
# all enabled repos:
for p in $(jq -r '.repos[] | select(.enabled) | .path' ~/.claude/self-learn/registry.json); do
  bash scripts/paginate.sh --repo "$p" 40 200
done
```

Each call writes `pending/<repo>.json` and prints the batch: per branch, the new commits
with `{hash, author, date, subject, stat}`. Do **not** load full diffs into context up
front - that explodes tokens. For the handful of commits that look behaviorally
significant (new patterns, refactors, reverts, fixes hinting at a recurring mistake),
pull the diff on demand to a temp file and grep it:

```bash
git -C <repo> show <hash> > /tmp/sl-<hash>.patch   # then Grep the temp file, don't cat it
```

Scale to intent: a quick run studies one repo; "learn across everything" iterates all
enabled repos. Mind the token budget - prefer a bounded set of repos per run and let the
cursors carry the rest to future runs. Rotate coverage so every repo advances over
successive runs; a repo that returns `totalCommits: 0` is drained, not skipped.

**Do not run `advance.sh` yet.** Cursors only move after analysis succeeds (Phase 5).

### Phase 1b - Paginate pull requests + review comments

Commits show what shipped; **PR review comments show what reviewers caught and how it was
resolved** - the single best signal for improving the reviewer, fixer, and planning
(architect, critic) agents. Page them with their own cursor:

```bash
# per repo (GitHub only - skips non-github remotes automatically):
bash scripts/pr-paginate.sh --repo /path/to/repo 10 40
# all enabled github repos:
for p in $(jq -r '.repos[] | select(.enabled) | .path' ~/.claude/self-learn/registry.json); do
  bash scripts/pr-paginate.sh --repo "$p" 10 40
done
```

It emits two streams with one cursor each (stored in `pagination.json -> repos[k].prs`):
- **historical backfill**: PRs with number greater than `prs.cursor`, oldest-first;
- **live open PRs**: any OPEN pr whose `updatedAt` moved past `prs.openSeen[number]` -
  this is how brand-new and still-open PRs get re-read when fresh comments land.

Each PR carries `{number, state, title, comments[]}` where comments include inline review
comments, issue comments, and review verdicts (CHANGES_REQUESTED / APPROVED), each tagged
with author and `bot` flag. The full bodies are in `pending/pr-<repo>.json`; stdout is a
lean view. Read the pending file selectively - mine the comments for recurring review
themes (what gets flagged repeatedly), weighting human comments above bot comments, not
individual nits.

The paginator is a foreground, blocking bash call - it returns with the batch. Never
background it or hand it to a PR-watching skill. If any comment stream could not be READ
(API error, outage) it aborts loudly and leaves the cursor in place so the next run
re-reads the same PRs - it never degrades silently to "this PR had no comments".

Advance PR cursors in Phase 5 with `bash scripts/pr-advance.sh` (separate from commit
`advance.sh`).

## Phase 2 - Ingest sessions (what actually happened)

```bash
bash scripts/sessions.sh                 # unprocessed *.jsonl for the cwd project
bash scripts/sessions.sh --dir <path>    # ... for one specific project working dir
bash scripts/sessions.sh --all           # ALL project dirs with unprocessed sessions (each its own cursor)
```

Every project working-dir has its OWN session cursor (`pagination.json -> sessions[<dir>]`).
For a broad run use `--all`: it sweeps every `~/.claude/projects/*/` and lists each dir's
unprocessed transcripts scoped to that dir's cursor. First `--all` scan is slow (no cursors
yet, counts every file); after the first `--all --advance` baseline, later runs only touch
new sessions and are fast.

**Scope rule for unattended runs:** decode each session to its cwd FIRST. If a session's
cwd is outside the roots you trust (your workspace + `~/.claude`), skip it entirely and log
`skipped: out-of-scope cwd` - never `cd` into it or read its files.

Session transcripts are the highest-signal input. Read selectively (`Read offset/limit` or
`grep` on the jsonl - these can be MBs). Run **two passes**; they have very different yields.

**Pass 1 - user corrections** (what the user pushed back on):

- repeated user corrections of the same kind (a missing rule -> candidate skill/agent edit)
- steps an agent did that the user undid or complained about (dead weight to remove)
- multi-step sequences the model reinvented each time (candidate bundled script)
- token/time sinks: re-reading files, redundant searches, oversized outputs

Pass 1 goes quiet once a setup matures - it can return no agent-behaviour defect for many
consecutive runs. Run it, but do not expect it to carry the run, and never manufacture a
finding to make it productive.

**Pass 2 - mechanical tool-call failures.** This is the load-bearing pass over a mature
setup. Grep the corpus for failures the model *worked around silently*, then join each
failure back to the command that caused it:

```bash
# the shapes that keep paying: is_error results, shell-dialect aborts, API rejections
grep -rl 'is_error":true' <corpus>        # then join tool_use_id -> the originating tool_use
# high-yield literals: 'fatal:'  'no matches found'  'read-only variable'  'command not found'
#                      'HTTP 422'  'not mergeable'  'unexpected parameter'  'InputValidationError'
```

**Build the corpus with `scripts/corpus.sh` - never compose it by hand.** Hand-composed
corpora read as clean and were wrong three separate times. The script encodes the three
traps and self-verifies:

```bash
bash scripts/corpus.sh --exclude <this-session-id>          # -> /tmp/sl-corpus.txt (+ summary)
bash scripts/corpus.sh --since '<date>' --exclude <id>      # only transcripts newer than <date>
xargs grep -lF '<literal>' < /tmp/sl-corpus.txt             # consume: `< file`, NEVER `xargs -a`
```

It prints `all / engine ids / clean / canary`. **The canary is the fail-open check** - it must be
`N/N`; if it reports 0 the consume pipeline scanned nothing and every literal will lie with a
false zero. Pass the current session id to `--exclude`: this run's own transcript has the engine
header, but its `wf_*` workflow children are written as it goes. If you run other unattended
Claude jobs, add their opening-prompt markers via `SELF_LEARN_ENGINE_MARKERS` so their
transcripts are excluded too.

The three traps the script encodes and the three judgement calls it cannot make for you are
in `references/corpus-forensics.md` - read it before trusting any Pass-2 count.

Count distinct **commands**, not matching error lines - counting lines turns a 30-day cross-tool
defect into a one-day incident. A failure whose `is_error` is *false* is the most valuable kind:
the model read a lost result as an empty one and moved on, so nothing ever looked broken.

Capture both passes as **learnings** (short, evidence-linked notes) - they drive Phase 4.

## Phase 2.6 - Routing & Intent (understand the user, not just the tooling)

The efficiency rubric does not capture whether Claude picked the RIGHT skill for what the
user meant. This phase does. From the SAME transcripts, mine routing signal - misroutes,
missed routes, rephrase loops, speech-to-text mishears, new-intent candidates - and maintain
the routing layer in the private store:

- `routing/routing-map.json` - machine map for the conditional UserPromptSubmit hook
  `~/.claude/hooks/skill-router.py` (nudges toward a skill only on keyword match, ~0 token
  cost, silent on explicit `/slash` commands and on no-match).
- `routing/intent-lexicon.md` - human rationale + the user's observed phrasings + STT-mishear
  table.

Add the user's real phrasings (in whatever language they dictate, plus STT variants) as
keywords; fix misroutes by repairing keywords or tightening competing skills' `description`
(snapshot first - the description is the native auto-trigger surface). Evidence-or-it-doesn't-ship:
every keyword cites the session that motivates it. Full rubric + verification snippet:
`references/routing-analysis.md`. Verify the hook still parses before advancing. Treat routing
quality as a first-class output of each run alongside token/cycle savings.

## Phase 2.7 - Memory distillation & compaction (close the feedback->skill loop)

The per-project memory store (`~/.claude/projects/*/memory/`) is the highest-signal input
of all: it is already-distilled user preference, with a `MEMORY.md` index that is loaded into
context **every session**. Two naming conventions coexist: a retrospective skill may write
`feedback_*`/`project_*`/`reference_*`/`user_*`/`estimation_*` FILENAMES, while the built-in
memory tool writes a kebab-case slug and puts the class in `metadata.type` frontmatter.
`scan` normalizes both into one `class` field - **always key this phase off `class`, never
off a `feedback_*` filename glob**, or every memory of the second kind is invisible and the
phase reports "nothing to distill" while real feedback sits unread. Left alone the store grows
unbounded and pays that context cost forever, while the rules it encodes stay *passive* -
loaded as reminders but never actually enforced by the skills that should own them. This phase
fixes both: it turns durable feedback into skill/agent behaviour (feeding Phase 4/5) and then
compacts what became redundant. Deterministic scan/backup/cursor primitives live in
`scripts/memory.sh`; the judgement is the model's.

```bash
bash scripts/memory.sh scan          # classify every memory file across all projects
bash scripts/memory.sh scan <dir>    # ... for one project's memory dir
```

`scan` emits, per file: `{class, status(new|changed|unchanged vs cursor), indexed}`. A
cursor (`pagination.json -> memory[<dir>]`) means unchanged memories are **not re-analyzed**
every run - only new/changed files and the index need work. `indexed:false` flags an orphan
(file with no `MEMORY.md` line, or a stale line whose file is gone).

The distill-or-retire test, the `project`-class lifecycle rules, the compaction procedure and
the apply boundary are in `references/memory-distillation.md` - read it when this phase runs.

## Phase 2.8 - Model & effort routing audit (optional, needs the `model-balance` skill)

If `<skill-dir>/../model-balance/SKILL.md` is installed, run its collector and classify
every routing site (`--model` flags in job/skill scripts, skill-frontmatter `model:`/`effort:`
pins, workflow `agent()` choices) against its rubric. Rebalance the two dials (intelligence +
effort) toward the cheapest tier that holds quality. Same hybrid apply boundary as Phase 2.7:
auto-apply only high-confidence, reversible single-site config edits (backup the file first);
defer the session default, any tier-raise not backed by observed rework, and any many-site
change to the journal with the revert command. Never downgrade a site where transcripts show
the cheaper tier already caused rework.

## Phase 3 - Inventory & version agents/skills

```bash
bash scripts/inventory.sh   # JSON: every agent/skill with hash + new|changed|unchanged
```

This is the catalog of what can be improved. `new` items were never tracked; `changed`
items drifted since last run (worth re-studying); `unchanged` are stable. You now have:
the evidence (Phases 1-2) and the targets (Phase 3).

### Phase 3.5 - Checkpoint the ingest (durable, BEFORE Phase 4 launches)

Phase 4 is the long turn and it is where unattended runs die: a `Connection closed
mid-response` at the Phase-4 launch, repeated over several nights, once recorded **nothing**
because the journal is only written in Phase 6 - the same batch was paginated four times and
analyzed zero times. So write the ingest down before you risk it, then launch Phase 4:

```
~/.claude/self-learn/journal/<epoch>-<date>.partial.md    # <epoch> = state epoch + 1
```

Contents: run posture (fresh vs crash-resume), what was ingested per repo / PR stream /
session dir with counts and ranges, the learnings collected so far, and anything already
applied in Phase 2.6/2.7/2.8.

The checkpoint is a note, not a result - four constraints keep it honest:

- **It must not look like success.** The nightly guard globs `journal/*-<date>.md`
  (`nightly-run.sh` in the store); `.partial.md` deliberately does not match, so a
  checkpointed-but-crashed run still logs COMPLETION WARNING. Never name it `<epoch>-<date>.md`.
- **It must not advance anything.** No `advance.sh`, no `pr-advance.sh`, no
  `sessions.sh --advance`, no `bump-epoch`. Phase 5 stays the only place cursors move - the
  checkpoint exists *because* the batch is still unprocessed.
- **It must not confuse the next run.** Say so in its first lines: cursors NOT advanced,
  analysis NOT run. Phase 0 step 2 reads it as the dead run's ingest digest, then this run
  overwrites it.
- **Phase 6 supersedes it.** Once the real `<epoch>-<date>.md` journal exists, delete every
  `*.partial.md` for that epoch - a stale partial beside a finished journal is the one way
  this rule can lie.

One write, at one point. Do not generalize it into a per-phase checkpoint - that would turn a
token-lean engine into a journal spammer.

## Phase 4 - Multi-agent analysis (the improvement engine)

This is where learning becomes change. The batch of learnings now includes the
feedback->skill distillations from Phase 2.7 (a redundant feedback memory is a proven
gap or a proven no-op). Run a multi-agent **Workflow** that, for each
candidate agent/skill, independently analyzes it against the batch of learnings and
proposes concrete, minimal improvements - then adversarially verifies each proposal so
nothing degrades quality. See `references/analysis-workflow.md` for a ready-to-adapt
workflow script, the exact optimization rubric and the hard agent-budget ceiling.

The rubric every proposal must satisfy (this is the whole point - speed/cost down, quality
held):

- **Fewer tokens**: cut redundant instruction, collapse repetition, prefer scripts over
  prose for deterministic steps, shrink oversized examples.
- **Fewer cycles**: remove steps that caused rework in the transcripts; front-load the
  decision that gates the most work; bundle reinvented helper scripts.
- **Same or higher quality**: no rule is dropped without evidence it caused harm or is
  dead. Each proposal cites the commit/session that motivates it. If a change trades any
  quality for speed, it is rejected.

Each surviving proposal is a diff against one item, with: target `id`, rationale (with
evidence pointer), expected token/cycle saving, and a "quality guard" note explaining why
nothing regresses.

**Never overfit one project's conventions onto another.** Branching model, language,
ticket prefixes, bots, deploy targets differ per project; those belong in each project's
own config / `CLAUDE.md`, never in a global agent or skill.

## Phase 5 - Apply (only with `apply`) + advance cursors

For each approved proposal, in this order:

1. `bash scripts/snapshot.sh <id> <major|minor|patch>` - snapshot + version bump FIRST.
   Use `minor` for behavior changes, `patch` for wording/token trims, `major` for
   restructures.
2. Apply the edit to the live agent/skill file with `Edit`.
3. If a recurring multi-step sequence was found, write the bundled script into the item's
   own `scripts/` and reference it from its SKILL.md (write-once, save every future run).
4. After writing skill edits to `~/.claude/skills/`, run `/reload-skills` to hot-reload the
   edited skills into the current session (context is preserved). Agent edits still require
   the agent to be re-spawned; only skill SKILL.md changes hot-reload. When a kaizen skill is
   delivered by the plugin it lives in `~/.claude/plugins/cache/…`, which `/plugin update`
   overwrites: record such an edit in the journal as an upstream change and never write it into
   the plugin cache.

In `propose` mode, stop before step 1-2 and present the diffs for the user to approve.

Once the batch is fully processed (whether applied or just proposed and acknowledged):

```bash
bash scripts/advance.sh                       # move commit cursors forward
bash scripts/pr-advance.sh                    # move PR cursors forward (Phase 1b)
bash scripts/sessions.sh --advance <maxTs>    # cwd project (maxTs from Phase 2 output)
bash scripts/sessions.sh --all --advance      # OR drain every project dir's cursor to its newest session
bash scripts/memory.sh advance <dir>          # move the memory cursor forward (Phase 2.7, per project dir)
bash scripts/state.sh bump-epoch              # increment epoch, stamp the run
```

## Phase 6 - Journal + sync

Write `~/.claude/self-learn/journal/<epoch>-<date>.md` summarizing: epoch, commits/sessions
consumed (ranges + counts), repos touched, items inspected, proposals (applied vs proposed),
token/cycle savings claimed, and what the **next** run should focus on. This is the
breadcrumb that makes the next "where am I?" instant. Append a terse dated entry to
`references/learned-patterns.md` with the conclusions worth carrying forward (keep that file
under ~200 KB; rotate the oldest entries into an archive file when it approaches the limit).

Then delete this epoch's Phase-3.5 checkpoint - the real journal supersedes it:

```bash
rm -f ~/.claude/self-learn/journal/<epoch>-*.partial.md
```

Then persist everything to the private store:

```bash
bash scripts/sync.sh    # pull --rebase, commit, push (no-op until `sync.sh init <remote>` was run once)
```

End your message to the user with the new epoch, version, repos covered, and a one-line
pointer to the journal entry.

## New-project flow

When a new project is created, it must join the list. Either is fine:

- automatic: the next full run calls `discover.sh`, which finds the new repo on disk; or
- immediate: `bash scripts/register.sh <path-to-new-repo>` right after `git init`;
- from the installer: `install.sh --wizard` lists every repo under your roots and lets you
  toggle any off - the answer lands in `config.json -> disabledRepos` and
  `registry.json -> repos[key].enabled`.

Its config defaults (`batch`, `maxTotal`, `enabled`) land in `registry.json` in your
private store - never in the project. To enroll a brand-new project the moment it is
scaffolded, run `register.sh` as the last scaffolding step.

---

## Operating principles

- **Evidence or it doesn't ship.** No edit to an agent/skill without a commit or session
  that justifies it. Self-improvement that isn't grounded in real history is just churn.
- **Reversible always.** Snapshot before edit. If unsure, propose, don't apply.
- **Lean context.** Metadata and stats into context; full diffs/transcripts to `/tmp` and
  grep. The skill that studies token waste must not be a token sink itself.
- **Two-phase cursors.** Never advance before analysis succeeds - a crashed run re-reads
  the same batch, it never skips it.
- **Unattended means unattended.** In a headless run there is no follow-up turn: never
  "stand by", never defer to a monitor, never ask a question. A gated change is recorded in
  the journal with the exact edit for the next interactive run, and the run keeps going.
