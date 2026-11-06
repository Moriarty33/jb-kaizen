---
name: review-code
description: Self-review your own code changes on the current branch vs the base branch. Use when the user wants a quality check on their own work before sharing - whether they say "review my code", "check my changes", "is this ready to ship", "self-review", or just ask you to look over what they just built. Runs STRICT-mode review across all P0-P4 tiers, shows findings, and offers to auto-fix. Invoke with /kaizen:review-code [repo-name] (or /review-code on a clone install).
allowed-tools: Read, Edit, Grep, Glob, Bash(git:*), Bash(gh:*), Bash(graphify:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), AskUserQuestion, Agent
---

# Review Code (Self-Review)

Shipped with JB Kaizen. Review your own changes on the current branch against the base branch (from `dev.config.json` -> `baseBranch`, default `develop`). Uses STRICT mode - all priority tiers P0-P4.

## Instructions

### Step 1: Detect Repository

Determine the target repo:
- If argument provided (e.g., `/review-code api`), resolve `{arg}` against project config: `.claude/dev.config.json` (searched from cwd upward) -> `workspaceRoot/{arg}`. If no config, treat `{arg}` as a path relative to cwd.
- If no argument, detect from current working directory

Verify it's a git repo:
```bash
git -C {repo-path} rev-parse --is-inside-work-tree
```

Show the current branch:
```bash
git -C {repo-path} branch --show-current
```

### Step 2: Get Diff

Resolve `{base}` per `github` §0 (read `dev.config.json` -> `baseBranch`; if unset, derive from `origin/HEAD`, fallback `develop`) - do not hardcode `develop` (some repos use `main`). All `git` commands use `git -C {repo-path}`, never `cd` (`github` §1).

Get all changes on this branch vs the base:
```bash
git -C {repo-path} diff {base}...HEAD
```

If the diff is empty, also try:
```bash
git -C {repo-path} diff {base}
```

Also capture uncommitted working-tree edits, so a branch that already has commits does not pass review while just-written changes are silently skipped:
```bash
git -C {repo-path} status --short
git -C {repo-path} diff HEAD
```
Include any uncommitted changes in the review set alongside the committed diff.

If everything is empty, inform the user there are no changes to review.

Also get the list of changed files:
```bash
git -C {repo-path} diff {base}...HEAD --name-only
```

### Step 3: Read Review Rules

Read the shared review rules in `rules.md`, the file next to this `SKILL.md` in the same skill directory.

Apply these rules in **STRICT** mode - all priority tiers P0-P4, including items marked `[STRICT]`.

### Step 4: Read Project Standards

Read the project-specific CLAUDE.md for additional standards:
```
{repo-path}/CLAUDE.md
```

Also check for CLAUDE.md files in directories containing changed files.

### Step 5: Read Source Files for Context

For each changed file:
1. Read the **full current version** of the file (not just the diff)
2. Read **related files** - imports, base classes, interfaces, shared utilities
3. Understanding surrounding context is critical for accurate review

### Step 5.5: Map the Existing Architecture (MANDATORY, before any analysis)

Build the **Architecture Map** of every concern the diff touches, from the merge-base with `{base}` - procedure in `rules.md` P0.8 ("Building the map"). Place every entry point, rule and config the diff adds or changes: *through* the layer (its entry point or extension point) or *beside* it. Everything beside it is a P0.8 candidate for Step 7. Self-review is the cheapest place to catch a parallel path - before a reviewer has to.

### Step 6: DRY Detection - Parallel Codebase Search

While reading the diff, collect any functions, helpers, mappers, utilities, or components that look **generic** rather than feature-specific. Signs of potentially duplicated implementation:
- Utility functions (date formatting, string normalization, error wrapping)
- Mapper/transformer methods
- Validation helpers not tied to this specific feature
- DTOs or interfaces that overlap with existing ones

For each suspicious item, **launch an Explore agent in parallel** (Agent tool with `subagent_type=Explore`) to search the codebase for existing implementations.

Launch these searches **in parallel with Step 7** - do not wait before starting analysis.

### Step 7: Analyze Changes

Apply **ALL** priority tiers from rules.md in STRICT mode:
- P0 - Bugs & Correctness
- P0.5 - Security
- P0.8 - Architecture Conformance (judged against the Step 5.5 map: extend, never duplicate)
- P1 - Architecture & SOLID
- P1.5 - DRY (incorporate results from Step 6)
- P1.6 - File Structure & Conventions
- P1.7 - Verbose Comments
- P2 - Type Safety (zero tolerance for `any`)
- P2.5 - React Performance
- P3 - Test Coverage
- P3.5 - Framework Patterns (project-specific, e.g. NestJS, Next.js)
- P4 - Domain-Specific (project-defined: e.g. compliance, multi-tenancy, accessibility)

### Step 8: Output Findings

Present a structured markdown report to the user:

```
## Self-Review: {branch-name}

### Summary
- Files reviewed: N
- Architecture: {layer} - FOLLOWS / PARTIAL / BYPASSES (or "no owning layer")
- Issues found: N (X auto-fixable, Y manual)

### P0 - Bugs & Correctness
- [ ] {file}:{line} - {description}

### P0.5 - Security
...

(continue for each tier that has findings)

### Auto-Fixable Issues
| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 1 | ... | ... | ... | ... |

### Manual Attention Required
| # | File | Line | Issue | Reason |
|---|------|------|-------|--------|
| 1 | ... | ... | ... | ... |
```

If no issues found, report that the code looks clean.

### Step 9: Ask Permission to Fix

If there are auto-fixable issues, ask the user:

> Found {N} auto-fixable issues. Fix them automatically?

Use AskUserQuestion with options:
- "Fix all" - implement all auto-fixable changes
- "Let me choose" - show each fix and let user approve individually
- "Skip" - just keep the report, don't change anything

### Step 10: Implement Fixes (if approved)

For each approved fix:
1. Apply the fix using Edit tool
2. Resolve the lint command from config: `commands[repo].lintFix` (from `dev.config.json`). If undefined, detect from the repo's `package.json` scripts (`lint:fix`, `lint`) or CLAUDE.md; ask the user only if none resolve.
3. Run the resolved linter after each file, against the repo path rather than by changing directory (e.g. `yarn --cwd {repo-path} lint:fix`, `npm --prefix {repo-path} run lint:fix`)

### Step 11: Final Report

```
## Fixes Applied

| # | File | Issue | Status |
|---|------|-------|--------|
| 1 | ... | ... | Fixed / Skipped |

### Still Needs Manual Attention
- {file}:{line} - {description} - {why it can't be auto-fixed}
```

## Important Notes

- This is a LOCAL self-review - nothing is posted to GitHub
- Uses STRICT mode - stricter than PR review, catches more issues
- Always read full source files for context - never review diff in isolation
- Run linter after every file modification
- Do NOT auto-fix without user confirmation
- Focus on changes in the diff - do not review pre-existing code unless directly related
