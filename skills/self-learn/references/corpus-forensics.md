# Pass-2 corpus forensics - why `scripts/corpus.sh` exists

Read this before trusting any Pass-2 number. Every rule here was paid for by a wrong result that
read as a clean one.

## The three traps the script encodes

- **`find`, never a one-level glob.** Subagent and workflow-agent transcripts live *nested* under
  `<session-id>/subagents/...`, and that is where agent tool-failures actually happen. A shallow
  `~/.claude/projects/*/*.jsonl` glob silently hides ~90% of the corpus (measured: 328 files vs
  3,569 for `find`). `**/*.jsonl` works in zsh but needs `shopt -s globstar` in bash - prefer `find`.
- **Exclude engine runs by SESSION ID AS A PATH COMPONENT** (`<id>.jsonl` *and* `<id>/**`), never by
  sniffing a file's header. Only the top-level file carries the header; its nested children carry
  none, and those children are exactly where prior analysis agents echo every literal you grep for.
  A header filter leaves ~60% of a "clean" corpus contaminated.
- **No GNU-isms on macOS** (BSD userland, bash 3.2): no `xargs -a`, `mapfile`, `timeout`, or
  `declare -A`. `xargs -a` is the dangerous one - BSD xargs rejects it, grep then scans ZERO files,
  and the pipeline still exits 0, so the load-bearing pass fails open.

## Three judgement rules the script cannot make for you

- **If every high-yield literal returns zero, suspect the pipeline, not the corpus** - confirm with a
  direct `grep -c` on one known transcript before believing any zero. A *single* zero is weaker
  still: before reading it as absence, run a **positive control** - a literal of the same class that
  MUST hit - and grep the **encoding the artefact actually uses**, not the prose you expect
  (e.g. a loaded `CLAUDE.md` ships as `{"attachment":{"type":"nested_memory",...}}`, not as
  `Contents of .../CLAUDE.md`). A zero measures your literal until a positive control proves it
  measures the fact.
- **Count the block EVENT, not the message text.** Any transcript that read or drafted a hook
  script carries its block message verbatim, so filter to `is_error` results containing
  `PreToolUse:Bash hook error` (the `is_error` filter is load-bearing). Likewise, if a class's
  distinct top-level-session count is < 1/3 of its file count it is still subagent-inflated -
  report sessions, not files. And a share of the class is not a disproportion: divide by the
  population that could have produced it (for a Bash-guard class, the transcripts matching
  `"name":"Bash"`) before blaming one agent kind.
- **Date the class before proposing - the Pass-2 corpus is ALL-TIME, not an epoch window**
  (`--since` filters file *mtime*, not event date). Newest event:
  `xargs grep -hF '<literal>' < /tmp/sl-corpus.txt | grep -o '"timestamp":"[0-9-]*' | sort -u | tail -1`.
  If it predates the carrier change that **addresses this class** - a named line you confirmed is in
  the file now and absent from the prior `snapshots/<id>/<version>`; a `versions.json` bump alone is
  not evidence - the class is **CLOSED, not open**.
