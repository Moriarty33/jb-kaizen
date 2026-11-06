# Safety & privacy

## What the engine reads

- Git history of repos under your workspace root(s) - commit metadata up front, diffs only on demand into `/tmp`.
- Pull-request review comments for GitHub remotes, through the `gh` CLI you already authenticated.
- Claude Code session transcripts under `~/.claude/projects/` whose decoded cwd is inside the workspace or `~/.claude`.
- Per-project memory under `~/.claude/projects/*/memory/`.
- Your agents and skills under `~/.claude/agents`, `~/.claude/skills` and `<repo>/.claude/`.

## What it writes

- Your agents and skills (only after a snapshot; interactively only with `apply`).
- Memory index compaction (backup first, archive + pointer, never delete).
- The private store: cursors, manifest, snapshots, routing map, journal.
- Nothing inside a project repository.

## What it never touches

The deny-list in `night-guard-settings.json` is enforced by Claude Code's permission layer, independent of the
prompt: `~/Downloads`, `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Music`, `~/Movies`, `~/Videos`, `~/Library`,
`~/Public`, `~/.ssh`, `~/.aws`, `~/.gnupg`, plus `rm -rf`, `git push --force`, `git reset --hard`.

The nightly job refuses to start unless the workspace directory exists, so it can never fall back to running
in `$HOME`.

## Where your data goes

Nowhere, unless you point the store at a remote. If you do, the remote receives: project names and local
paths, PR numbers and review *themes*, distilled feedback, snapshots of your skills and agents, and the
journal. Treat it like a dotfiles repo with notes - **private**.

The engine sends nothing anywhere else. Transcripts are read locally with `grep`; diffs go to `/tmp`.

## Reversibility

- `versions.json` + `snapshots/<id>/<version>/` hold every pre-edit copy: `/self-learn rollback <id> <version>`.
- `memory-snapshots/<dir>/<timestamp>/` holds every pre-compaction memory directory.
- `install.sh` backs up every file it overwrites as `<file>.bak-<stamp>` and never overwrites learned state.
- `sync.sh` never force-pushes; a rebase conflict aborts and leaves the store untouched.

## Spend controls

- `--max-budget-usd` on the headless call (default 40; `SELF_LEARN_BUDGET_USD`).
- 45-agent ceiling inside Phase 4, enforced by a counter in the workflow script.
- Wall-clock per attempt (default 4 h) with process-group kill; at most 3 attempts.

## Things to know before enabling the nightly job

1. It runs with `--permission-mode auto`: safe actions are auto-approved, dangerous ones are gated by the
   classifier. The snapshot discipline is the second line of defence.
2. It uses your Claude subscription or API key like any other session. Check `ccusage` after the first
   week and tune `SELF_LEARN_BUDGET_USD` / `SELF_LEARN_MODEL`.
3. Read the first few journal entries. The engine is conservative by design, but it is editing the files
   that shape how Claude works for you - the journal is how you stay in the loop.

## The Hoply pairing

- **Sign-in.** The installer adds Hoply as a plain HTTP MCP server (no header) and runs `claude mcp login hoply`,
  which opens the browser to sign in with your Hoply account (OAuth with PKCE); Claude Code stores and refreshes
  that sign-in itself. Nothing is ever asked for in the chat: anything typed in a session is stored in its
  transcript. `uninstall.sh --hoply` runs `claude mcp logout hoply` and removes the server entry.
- **CI token.** Only `--token` / `HOPLY_TOKEN` (never asked interactively): shape-checked (`hpt_` + 43 letters
  and digits), written to `~/.config/hoply/token` (file 0600, folder 0700) and sent only through
  `~/.config/hoply/headers.sh` (0700) as the server's `headersHelper`, so it never lands in `~/.claude.json`.
  Prefer the env var: a `--token` value shows in the process list. Revoke it in Hoply - Connectors.
- **What Hoply sees.** Only MCP tool calls. The server is added at user scope, so every Claude Code session can
  reach its tools, not only `hoply-day`; Claude Code asks before each write tool, and `claude mcp remove hoply -s user`
  (or `uninstall.sh --hoply`) takes it away. Nothing from your sessions, transcripts or the self-learn store is
  sent; Claude does the wording locally.
- **Untrusted text.** Meeting titles, notes, project and repo names come from other people and other tools; the
  skill treats them as data, never as instructions, and writes only after an explicit yes to the printed list.
- **The nudge** is stdlib Python, reads only local files, never touches the network, and degrades to silence on
  any error, so it can never block a prompt. The OS reminder only shows a notification, once per workday.
  `--no-hoply-reminder` (config `hoply.reminder=false`) removes the reminder and mutes the nudge as well.
