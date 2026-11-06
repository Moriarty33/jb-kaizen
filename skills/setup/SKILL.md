---
name: setup
description: Configures JB Kaizen after `/plugin install kaizen@jb-kaizen` - the model is the wizard, since a skill's Bash call has no TTY for the interactive one. Asks the same seven questions the terminal wizard asks plus whether to connect Hoply, then runs one non-interactive install. Use on first install or to reconfigure - "change the nightly time", "change my workspace roots", "point the store at a remote", "add/remove a repository", "toggle the routing hook", "install/remove the VS Code companions", "connect Hoply". Invoke with `/kaizen:setup`; plugin installs only - clone and bootstrap use the terminal wizard.
allowed-tools: Bash, AskUserQuestion
compatibility: Designed for Claude Code
---

# setup - JB Kaizen, configured by the model instead of the terminal wizard

`install.sh` normally asks seven questions itself when run interactively (`[ -t 0 ]`). A Bash
call made by Claude from inside a skill has **no TTY**: forcing the interactive wizard
(`--wizard`) would make every question read EOF immediately, `ask_roots` would break out of
its retry loop at the first "not found" (`[ -t 0 ] || break`), and the user would silently get
defaults with no questions asked at all - the opposite of "one click, the wizard configures
everything".

So this skill never shells into the interactive wizard. **You ask the eight questions
yourself** with `AskUserQuestion`, then run `install.sh` exactly once, non-interactively, with
every answer passed as a flag.

## 1. Ask the eight questions

One `AskUserQuestion` call, all eight questions together, defaults pre-selected. Ask in the
language the user is writing in. The eight, with the meaning to show the user for each
(mirrors `extension/README.md`'s step table):

| # | Question | Means |
|---|----------|-------|
| 1 | Dependencies | install what is missing (`gh`, `node`, `uv`, `graphify`, `code`...) - `git`, `jq`, `python3` are required, the rest optional |
| 2 | Workspace roots | one or more directories where your git repositories live; new repos under them join automatically |
| 3 | Repositories | which of the repos found under those roots should be studied; anything toggled off is skipped |
| 4 | Routing hook | install the `UserPromptSubmit` nudge - one line when a learned phrasing matches a prompt, silent otherwise |
| 5 | Nightly run | run every night, and at what local time (launchd / systemd --user / crontab, whichever the OS uses) |
| 6 | Private remote | a PRIVATE git remote to back the store up to - it holds project names, paths and distilled feedback, never push it anywhere public |
| 7 | VS Code companions | install `claude-launcher` and/or `graphify-watch` (bundled, MIT, installed through the `code` CLI) |
| 8 | Hoply | connect Hoply for the 17:15 day review (`/kaizen:hoply-day`) and the workday reminder - yes or skip; sign-in in the browser, never a token (section 3b) |

The install also adds the four short aliases `/kz-setup`, `/kz-learn`, `/kz-audit`, `/kz-balance`
to `~/.claude/skills/`. If the user says they do not want them, append `--no-aliases` to the
install command below.

Pre-select sensible defaults (dependencies: yes if any missing; roots: `~/workspace` if it
exists and holds git repos; repositories: all studied; routing hook: on; nightly: off;
private remote: none; VS Code: off; Hoply: skip) so a user who just wants it working can accept every
default in one submission.

## 2. Resolve the plugin root

Same base every other plugin-mode path uses - `CLAUDE_CONFIG_DIR`, never a bare
`$HOME/.claude`:

```sh
C="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ROOT="${CLAUDE_PLUGIN_ROOT:-$(ls -td "$C"/plugins/cache/*/kaizen/*/ 2>/dev/null | head -1)}"
[ -f "$ROOT/install.sh" ] || {
  echo "cannot find the kaizen plugin root - reinstall with /plugin install kaizen@jb-kaizen"
  exit 1; }
```

`CLAUDE_PLUGIN_ROOT` is set by the plugin runtime itself whenever this skill is actually
invoked as a plugin skill; the `ls -td ... | head -1` fallback covers the rare case where it
is unset (e.g. this skill run standalone during development) by taking the newest cache
checkout. The `[ -f ... ]` guard also catches an empty `ROOT` - without it a missing match
would silently become `bash "/install.sh"`.

## 3. Run exactly one non-interactive command

Build the flags from the answers and run once, output redirected to a log:

```sh
bash "$ROOT/install.sh" --plugin --yes ${NO_ALIASES} --workspace <roots> \
  [--schedule HH:MM | --no-schedule] [--store-remote <url>] [--vscode all|none|claude-launcher,graphify-watch] \
  [--hook|--no-hook] \
  > /tmp/kaizen-setup.log 2>&1
tail -20 /tmp/kaizen-setup.log
```

- `<roots>` is the comma-separated list from question 2.
- `--schedule HH:MM` when question 5 was yes, `--no-schedule` when it was no.
- `--store-remote <url>` only when question 6 gave a URL; omit it entirely when the user
  skipped or cleared it.
- `--vscode` takes the companion list from question 7: `all`, `none`, or a comma-separated
  subset of `claude-launcher,graphify-watch`. `install.sh` matches those tokens only - any
  other word (`yes`) means none.
- `${NO_ALIASES}` is empty by default; set it to `--no-aliases` only when the user said no to
  the short aliases.
- Question 4 maps to `--hook` / `--no-hook` (in `--plugin` mode the hook is not installed
  either way, but the answer is what gets persisted to `config.json`). Question 3's
  repository toggles have no flag - they are saved as `disabledRepos` in `config.json` on the
  normal `wizard_save_config` path.
- Never pass `--wizard` from inside this skill - see the note above.
- Question 8 maps to `--hoply-reminder` (yes) or `--no-hoply-reminder` (skip).

### 3b. Hoply: sign-in in the browser, never a token in the chat

When question 8 was yes, add the server (no secret involved, safe to run from here):

```sh
claude mcp add --transport http --scope user hoply https://app.hoply.work/mcp
```

Then tell the user to sign in with their Hoply account: in Claude Code run `/mcp`, pick `hoply`, choose
**Authenticate** (or `claude mcp login hoply` in their own terminal). Never ask for a token or a password in
`AskUserQuestion` or in chat: anything typed in a session is stored in its transcript. A personal token is only
for CI and headless machines (`HOPLY_TOKEN=... npx -y jb-kaizen --yes`).

## 4. Print the terminal fallback

Always mention the escape hatch for anyone who wants the real interactive TUI instead of
answering through the model:

```
bash "$ROOT/install.sh" --plugin --wizard
```

pasted into their own terminal (has a TTY, so the seven questions work normally there).

## 5. What `--plugin` skips, and why

`--plugin` skips copying skills and the routing hook into `~/.claude/skills` /
`~/.claude/hooks` - the plugin itself already delivers those (they load straight from
`CLAUDE_PLUGIN_ROOT`, no copy needed). Everything else - dependencies, workspace roots,
repository registry, nightly schedule, private-store remote, VS Code companions - is
installed and saved exactly as it would be from a repo checkout.

Re-running this skill (or `install.sh --plugin --yes`) at any time is safe and idempotent:
saved answers in `config.json` fill in anything not explicitly re-asked, flags always win over
the saved config, and nothing destructive happens on a repeat run.

## 6. Where the answers live

Every answer is saved to `~/.claude/self-learn/config.json` (path resolved through
`CLAUDE_CONFIG_DIR` the same way as everywhere else). To change one thing later - the nightly
time, the workspace roots, the private remote - re-run `/kaizen:setup` and answer only that
question differently; every other answer is carried forward from the saved config.
