---
name: commit
description: Create git commits with proper ticket formatting. Project-agnostic - reads ticket pattern, lint command, and commit format from .claude/dev.config.json or package.json. Auto-stages changes, runs project linter, extracts ticket ID from branch name. Invoke with /kaizen:commit (or /commit on a clone install).
allowed-tools: Read, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git branch:*), Bash(yarn:*), Bash(npm:*), Bash(pnpm:*), Bash(npx:*)
---

# Commit Changes

Shipped with JB Kaizen. Create git commits with consistent ticket formatting. Reads project configuration to stay project-agnostic.

> Git conventions (git -C, branch naming, commit format, safety) follow the `github` skill shipped alongside. This skill keeps its own staging/lint flow and message-guideline examples below.

## Configuration Discovery

Resolve in order. `.claude/dev.config.json` is searched from the current directory upward to `$HOME` (or the filesystem root); the first one found wins.

1. **`.claude/dev.config.json`** - read `ticketPattern`, `commit.messageFormat`, `commit.maxLength`, `commit.skipBranches`, and per-repo `commands[repo].lintFix`
2. **`<cwd>/CLAUDE.md`** section `## Commit Format` (e.g. `Ticket pattern: TICKET-\d+`)
3. **`<cwd>/package.json`** scripts: `lint:fix` -> `lint --fix` -> `lint`
4. **Defaults**:
   - `ticketPattern`: `[A-Z]+-\d+`
   - `messageFormat`: `{ticket}: {message}` when ticket present, otherwise just `{message}`
   - `maxLength`: 72
   - `skipBranches`: `develop`, `master`, `main`, `release/*`, `hotfix/*`

## Instructions

### Step 1: Check Git Status

```bash
git status
git diff
git log --oneline -5
```

If no changes, inform user and stop.

### Step 2: Get Branch Name & Extract Ticket

```bash
git branch --show-current
```

If branch matches any pattern in `config.commit.skipBranches`, skip ticket prefix - use plain description.

Otherwise apply `config.ticketPattern` to the branch name. Examples:

- `feature/TICKET-1234-add-login` -> `TICKET-1234`
- `PROJ-567/fix-bug` -> `PROJ-567`

If pattern doesn't match, ask the user whether to commit without a ticket prefix.

### Step 3: Stage Changes

```bash
git add .
```

If sensitive files (`.env`, credentials) appear in `git status`, warn and exclude them.

### Step 4: Run Linter (if configured)

Resolve lint-fix command from config / package.json. Run it. If lint fails with errors:

1. Show errors
2. STOP - do not commit broken code
3. User must fix first

If no linter found, skip silently.

If the linter ran and modified files (lint-fix), re-stage them so the fixes are included in this commit: `git add -u` (plus any newly created files). Do NOT re-stage if the linter only reported errors and you stopped.

### Step 5: Analyze Changes & Generate Message

```bash
git diff --staged
```

Analyze:

- Files modified/added/deleted
- Nature of change (feature, fix, refactor, docs, test)
- The "why" - high-level intent

### Step 6: Create Commit

Apply `config.commit.messageFormat` with `{ticket}` and `{message}` placeholders. Default examples:

- With ticket: `TICKET-1234: Add user authentication endpoint`
- Without ticket: `Add user authentication endpoint`

Pass via HEREDOC if multi-line is needed. Keep within `config.commit.maxLength`.

```bash
git commit -m "<formatted message>"
git status
```

## Commit Message Guidelines

**Keep it short - one sentence, max `config.commit.maxLength` chars.**

- One sentence in English
- Describe essence at high level (abstract)
- Present tense ("Add feature", not "Added feature")
- Focus on WHAT was achieved, not HOW

**Good:**

- `TICKET-1234: Add user authentication endpoint`
- `TICKET-5678: Fix login validation error`
- `TICKET-9999: Update user profile API response format`

**Bad:**

- `TICKET-1234: Added new endpoint for user authentication with JWT tokens and session management` (too long, too detailed)
- `TICKET-5678: Fix bug` (too vague)
- `Fixed the login` (no ticket, past tense)

## Project Configuration Examples

### Via `dev.config.json`

```json
{
  "ticketPattern": "[A-Z]+-\\d+",
  "commit": {
    "messageFormat": "{ticket}: {message}",
    "maxLength": 72,
    "skipBranches": ["develop", "main", "release/*"]
  },
  "commands": {
    "<repo>": { "lintFix": "yarn lint:fix" }
  }
}
```

### Via `CLAUDE.md`

```markdown
## Dev Pipeline Config

Ticket pattern: TICKET-\d+
Lint command: yarn lint:fix
```

### Via `package.json`

```json
{
  "scripts": {
    "lint:fix": "eslint . --fix"
  }
}
```

## Important Notes

- Safety (no auto-push, no `--no-verify`, no amend of pushed commits, no `--force`) follows the `github` skill.
- Append the Claude co-author + session trailers to every commit (`Co-Authored-By: Claude ...` and `Claude-Session: ...`, exactly as the session harness specifies); no OTHER trailers. See the `github` skill §3.
- If linter fails, STOP and show errors
- If no changes exist, inform user and stop
- If ticket pattern unclear, ask user
