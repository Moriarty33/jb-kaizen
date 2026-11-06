---
name: fix-pr-comments
description: Review and respond to PR review comments. Use when the user mentions "address PR feedback", "fix the review comments", "apply reviewer suggestions", "respond to PR comments", shares a PR with pending feedback, or asks you to handle code review items on an open pull request. Project-agnostic - reads workspace, repos, GitHub org, lint commands from .claude/dev.config.json. Analyzes each review comment, validates if it improves the code, implements valid suggestions, and reports skipped items with reasoning. Invoke with /kaizen:fix-pr-comments [PR number] (or /fix-pr-comments on a clone install).
argument-hint: [PR number or URL]
allowed-tools: Read, Edit, Grep, Glob, Bash(git:*), Bash(gh:*), Bash(yarn:*), Bash(npm:*), Bash(npx:*), AskUserQuestion
---

# Fix PR Comments

Shipped with JB Kaizen. Review and intelligently fix PR review comments. Reads project configuration to stay project-agnostic; git and gh mechanics follow the `github` skill shipped alongside.

## Configuration Discovery

`.claude/dev.config.json` (searched from cwd upward to `$HOME`, first match wins) -> `CLAUDE.md` -> defaults. Required fields: `workspaceRoot`, `repos`, `githubOrg`. Optional: per-repo `commands[repo].lintFix`, `commands[repo].typecheck`.

If `githubOrg` is missing, detect via `git -C {repo} remote get-url origin`.

## Instructions

### Step 1: Get PR Information

If PR number provided as argument, parse and use it. Otherwise detect from current branch across all `config.repos`:

```bash
for repo in <config.repos>; do
  branch=$(git -C {workspaceRoot}/$repo branch --show-current 2>/dev/null)
  if [ -n "$branch" ] && [ "$branch" != "{baseBranch}" ]; then
    pr=$(gh pr view "$branch" --repo {githubOrg}/$repo --json number,url,title,headRefName 2>/dev/null)
    if [ -n "$pr" ]; then echo "$repo: $pr"; fi
  fi
done
```

If multiple repos have open PRs, ask user which one (or process all).

### Step 2: Fetch Review Comments

For each PR, get all unresolved review threads with full context via the `github` skill §8 (the `gh api graphql` `reviewThreads` query; select thread `id`/`databaseId`/`path`/`line`/`body`, filter `isResolved == false`). Keep each thread `id` - Step 9 reuses it to resolve.

**Also read the review bodies, not just the threads.** Copilot emits *suppressed / low-confidence* findings inside a collapsed block in the review body itself. They are never comment objects, so both the `reviewThreads` query and the `github` §8 `pulls/{pr}/comments` sweep miss them silently:

```bash
gh api "repos/{githubOrg}/{repo}/pulls/{pr}/reviews" --paginate \
  --jq '.[]|select(.state!="PENDING" and .body!="")|{id,login:.user.login,at:.submitted_at,body}'
```

**Process only review bodies not already answered.** A review body is permanent and has no `isResolved`, and this skill is often re-run on the same PR after every new review - so without a gate it re-fixes and re-answers the same findings every round. First read the PR's issue comments (`github` §8 sweep) and skip any review whose `id` already appears in a prior answer.

Findings from an unanswered review body go through Step 3 like any other comment, but carry no thread `id` - nothing to reply to in Step 7, nothing to resolve in Step 9. Answer each such review in ONE new PR issue comment opening with `Suppressed comments from review {id}:` (this is the marker the gate above reads), naming the fixing commit:

```bash
gh api "repos/{githubOrg}/{repo}/issues/{pr}/comments" -f body='...'
```

Count them on their own row in Steps 6 and 10.

If there are no unresolved threads and no unanswered review bodies, inform user and stop.

### Step 3: Process Each Comment

For each unresolved comment:

1. **Read referenced file and code context** - file path + line numbers from comment
2. **Analyze** - what is the reviewer suggesting?
3. **Validate**:
   - Does this improve code quality?
   - Is the reasoning correct?
   - Does it align with project conventions?
   - Valid concern or matter of preference?
4. **Decide** - first re-read the target file at HEAD: on a long-running branch a later commit may have deleted or rewritten the code the comment points at.
   - **IMPLEMENT** - improves code, fixes bug, follows best practices, aligns with project standards
   - **SKIP** - incorrect, preference-only, would break functionality, doesn't improve quality
   - **OBSOLETE** - the finding was valid when written, but the code it targets no longer exists at HEAD. Make no edit - never invent a change to a deleted path to make it look addressed. Reply naming the commit or rewrite that removed it
   - **PARTIAL** - the observation is valid but the prescribed fix cannot be done as written, because the API/SDK/platform exposes no such operation. Treat the achievable part as an IMPLEMENT so it goes through Step 4 and the Step 5 gate, and name the concrete blocker for the rest. "Too big" or "out of scope" is NOT a PARTIAL - a valid finding deferred for scope is still IMPLEMENT-or-ask

   OBSOLETE and PARTIAL are answered in Step 7 like a SKIP, but the reply gives the concrete reason ("removed in {commit}", "{API} exposes no delete operation"). Never report either as SKIP - a SKIP reply reads as "the reviewer was wrong", which neither case is.

### Step 3.5: Detect Architectural Smell From Repeat Comments

Before implementing another point fix, check whether the same file / symbol / code path has accumulated multiple review comments across this PR's history. Repeat comments on the same area signal that the underlying abstraction is wrong - individual patches will keep generating new review comments.

**How to detect:**

1. List all resolved + unresolved comment paths for this PR via the `github` skill §8 `reviewThreads` query (fetch `first: 100`, select `isResolved`/`path`/`line`/`body` - do NOT filter on resolution here; you need the full history).

2. Count comments per file (or per nearby line range). 3+ comments on a single file/function = potential architectural smell.
3. Look at the *character* of comments. Different symptoms of one underlying mechanism (e.g. "unbounded growth", "stale index", "missing runtime guard", "edge case in trimming") = abstraction is wrong. Unrelated nitpicks (typos, naming) = this rule does not apply.

**When the smell is detected:**

- **STOP.** Do not implement another point fix.
- **STEP BACK and diagnose.** Write out:
  - Shared root cause behind the multiple comments
  - Which abstraction or invariant is being violated
  - What architectural pattern would eliminate the whole class of comments by construction
- **PROPOSE a refactor** via `AskUserQuestion`:
  - Table of recurring comments
  - Root-cause diagnosis (2-3 sentences)
  - Proposed architectural change
  - Before/after comparison
  - Scope estimate (files touched, test rewrites)
- **Wait for user approval.** Do not unilaterally refactor.
- If approved: implement as a single atomic change (not interleaved with point fixes); commit message calls out "addresses repeat review feedback".
- If declined: fall back to point-fix flow; warn that the next review pass is likely to surface another variant.

**Why:** Six rounds of patches on the same area cost more than one one-shot refactor.

### Step 4: Implement Valid Changes

For each comment marked IMPLEMENT - edit file via Edit tool. Make the minimal change.

### Step 5: Lint + Typecheck

Resolve commands per repo from `config.commands[repo]`:

Run them against the repo path, never by changing directory (`github` §1), e.g.:

```bash
yarn --cwd {workspaceRoot}/{repo} lint:fix
yarn --cwd {workspaceRoot}/{repo} typecheck
```

If commands not defined, fall back to `package.json` scripts (`lint:fix`, `typecheck`).

### Step 6: Report Summary

| # | Repo | File | Comment | Decision | Reason |
|---|------|------|---------|----------|--------|
| 1 | ... | ... | ... | Implemented / Skipped / Obsolete / Partial | ... |

### Step 7: Reply to Skipped Comments

For each SKIPPED, OBSOLETE or PARTIAL comment, post a reply explaining WHY, using the reply-to-review-comment mechanic in the `github` skill §8 (`gh api .../pulls/{pr}/comments/{id}/replies -f body=...`).

Reply should be concise and technical. Examples:

- "Intentional - we removed FormControl to prevent label click opening the popover. The trade-off (no aria wiring) is acceptable for this custom component."
- "The zod schema transforms empty arrays to undefined before sending, so this case can't occur."

### Step 8: Ask User for Actions

```text
AskUserQuestion (multi-question):

  Q1: "Which comments should be resolved on GitHub?"
  Options:
    - "All implemented"
    - "All (implemented + skipped)"
    - "Let me choose" -> multi-select per comment
    - "None"

  Q2: "Commit and push the changes?"
  Options:
    - "Yes, commit and push"
    - "No, I'll handle it"
```

### Step 9: Execute User's Choices

**Resolve threads** (if requested): reuse the `thread.id` values already captured in Step 2, then run the `resolveReviewThread` mutation per the `github` skill §8, once per thread.

**Commit and push** (if approved):

- Stage changed files (specific files only, not `git add -A`)
- Apply `config.commit.messageFormat` with ticket from branch name. Default: `{ticket}: fix PR review comments`
- Push to current branch

### Step 10: Final Report

```text
## Done

| Action | Result |
|--------|--------|
| Comments fixed | {N} |
| Comments skipped (with replies) | {N} |
| Comments obsolete / partial (with replies) | {N} |
| Comments resolved | {N} |
| Committed & pushed | Yes / No |
```

## Important Notes

- ONLY process unresolved/active comments
- If uncertain about a change, ask the user
- Run lint + typecheck after changes
- Group changes by file for efficiency
- Always reply to skipped comments with reasoning on GitHub
- Resolve every thread immediately after replying to it (whether the suggestion was implemented or skipped/reply-only) - never leave an answered thread unresolved
- Never auto-commit without user approval
- For multi-repo PRs, process all repos in one pass
