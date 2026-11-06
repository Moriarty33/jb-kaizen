---
name: github
description: Single source of truth for git + GitHub work - the conventions AND mechanics the other bundled skills (commit, review-code, fix-pr-comments) follow when they touch git or the GitHub CLI/API. Covers the git -C / workspace rule, branch naming, commit-message format, token-frugal gh usage (--jq/--json, never diff_hunk), PR create + body template, squash-merge + delete-branch, reading CI checks, reading review comments/threads, review-as-PENDING, multi-repo PR discovery, and the safety rules (never --force/--admin/--no-verify). Read this before any git/gh action, when another skill defers GitHub specifics here, or when the user asks how git/GitHub should be handled / types /kaizen:github (or /github on a clone install).
argument-hint: (none - reference skill; read it or link to it from other skills)
allowed-tools: Read, Bash(git:*), Bash(gh:*)
---

# GitHub + git (single source of truth)

Shipped with JB Kaizen. Every skill that runs `git` or `gh` does it **the same way**, and the conventions live **here**: other skills link to this file instead of restating them. When a skill says "follow github", this is what it means.

Project-specific values come from `.claude/dev.config.json`, searched from the current directory upward to `$HOME` (first match wins). This skill states the **conventions + mechanics**; the config holds the **values**.

---

## 0. Config values (from `dev.config.json`)

| Value | Key | Example |
|-------|-----|---------|
| Workspace root | `workspaceRoot` | `~/work/my-product` |
| GitHub org | `githubOrg` | `my-org` |
| Repos | `repos[]` | api, web, infra |
| Base branch | `baseBranch` | `develop` |
| Branch prefix | `branchPrefix` | `feature/` (bug fixes use `bugfix/`) |
| Ticket regex | `ticketPattern` | `[A-Z]+-\d+` |
| Skip branches | `commit.skipBranches` | develop, master, main, release/*, hotfix/* |
| Issue link base | `browseBaseUrl` | `https://tracker.example.com/browse/` (omit when there is no tracker) |

Default `baseBranch` when unset: `git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'`, fallback `main`.

---

## 1. `git -C` / workspace rule (hard rule)

A workspace root can itself be a git repo - a superproject whose subdirs are submodules, each a full repo - and then a bare `git` at the root acts on the superproject, never on the repo you mean. **Every git command uses `git -C {workspaceRoot}/{repo}`; never `cd` into a repo.** Multi-repo commands and any command from the workspace root MUST pass `-C`/absolute paths.

**Reading a file at a ref: always brace the variable** - `git show "${REF}:{path}"`, never `git show "$REF:{path}"`. In zsh, after a colon an *unbraced* expansion gets history-style modifiers **even inside double quotes**, so `"$B:libs/..."` silently lowercases the ref and eats the `l` (`:l`), and `"$B:terraform/..."` truncates it to its last path segment (`:t`). Biting letters: `a A c e h l P q Q r t u` (silent) and `s` (hard `bad substitution`). The failure is usually **invisible** - with `2>/dev/null` or a pipe the exit code is 0 and the empty output reads as "that file is not on this branch". Brace it up front.

---

## 2. Branch naming

- `{branchPrefix}{ticketId}` when the work has a ticket; `{branchPrefix}{slug}` otherwise (slug = lowercase, hyphens, max 50 chars).
- Bug fixes conventionally use `bugfix/{ticketId}` even though `branchPrefix` defaults to `feature/`.
- Never commit on a `skipBranches` branch (develop/main/master/release/*/hotfix/*) - branch first.
- **Cut from the branch the PR will target.** Default is `baseBranch`
  (`git -C {workspaceRoot}/{repo} fetch origin && git -C {workspaceRoot}/{repo} checkout -b {branch} origin/{baseBranch}`).
  If the user says this change lands somewhere else - straight to `main`/prod, a release branch, or
  "where prod was last released from" - cut from **that** branch and pass the same branch to
  `--base` (§5). A stated target overrides any project `CLAUDE.md` default that pins
  `origin/{baseBranch}`.

---

## 3. Commit messages

- Format: `{ticket}: {message}` - present tense, one sentence, **max 72 chars** on the subject. Ticket id parsed from the branch name; no ticket, no prefix.
- Lint before committing. Never blind `git add -A` - stage explicit paths after a sensitive-file check.
- **Trailers:** append the Claude co-author + session trailers (`Co-Authored-By: Claude ...` and `Claude-Session: ...`) exactly as the session harness specifies; no other trailers.
- Never `--no-verify`. Never amend an already-pushed commit. Never auto-push from a commit step (push is a separate, explicit step).

---

## 4. Token-frugal `gh` (hard rule)

Always pass `--jq` or `--json field1,field2` to `gh api` / `gh pr view` / `gh pr diff` / `gh pr list` / `gh run`. Never take the default/raw response - it carries `diff_hunk` blobs and other bulk that explodes context. Select only the fields you act on. Save large diffs/logs to `/tmp/*.txt` and `grep` them rather than piping into context.

---

## 5. PR create + body template

```bash
gh pr create --repo {org}/{repo} --base {baseBranch} --head {branch} \
  --title "{ticket}: {summary}" \
  --body "$(cat <<'EOF'
## [{ticket}]({browseBaseUrl}{ticket}): {summary}

### Changes
{bullet list}

### Quality Gates
- Lint: PASS | Build: PASS | Tests: PASS

### Related PRs
{cross-references - MANDATORY for multi-repo changes}

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- No ticket (or no `browseBaseUrl`): omit the link line and use a plain title/heading.
- "PR already exists" -> inform, skip creation for that repo.
- **Re-derive the facts before rewriting an open PR's Changes section.** A body written at design time describes the design that was then abandoned - counts, symbol names and schema constraints drift with the work, so do not keep the old wording and patch around it. Falsify the specifics first: `git -C {workspaceRoot}/{repo} grep -c '<symbol>'` for anything it counts, `Read` the migration for a constraint it asserts, `git -C {workspaceRoot}/{repo} diff --stat origin/{baseBranch}...HEAD` for paths it calls untouched; correct or drop whatever does not survive, and say what you checked. A body just written from the diff in hand, and mechanical section edits that add no claims (cross-links to related PRs), need no such pass.
- Never `--force`-push a PR branch. Push feature branches with `-u origin {branch}`.
- **`--base` must equal the branch you cut from.** When the user names a landing branch other than
  `baseBranch` for *this* PR, the PR's `--base` and the branch's fork point must be the same commit.
  If the branch was already cut from `baseBranch`, do **not** fix it with `gh pr edit --base {target}`
  alone - retargeting moves only the comparison base, so the diff drags in every commit `baseBranch`
  is ahead of the target (one real case: 65 commits / 462 files). Rebuild instead:
  `git -C {workspaceRoot}/{repo} fetch origin`, `checkout -b {branch}-{target} origin/{target}`,
  cherry-pick your own commits, push, open a new PR with `--base {target}`, and close the mis-based
  PR with a one-line pointer to the new one (same shape as §11's fresh-branch rebuild - never
  `--force`-push or rewrite the pushed branch). Verify before asking for review:
  `gh pr view <PR> --json baseRefName,commits --jq '"\(.baseRefName) \(.commits|length)"'` should
  show the target and only your own commits.

---

## 6. Squash-merge + delete branch (mechanics)

**First branch on `mergeStateStatus`** - you already have it from the approved + green check (§11), so this costs nothing. `CLEAN`/`UNSTABLE` -> merge as below. **`BEHIND`** (the repo requires the head branch be up to date with the base) -> a plain `gh pr merge` is rejected with `not mergeable: the head branch is not up to date with the base branch`, and waiting never clears it. Run `gh pr update-branch <PR> --repo {org}/{repo}` first (dependabot PR: comment `@dependabot rebase` instead), then re-check approved + green - the update re-triggers CI - and merge. If `update-branch` reports a conflict, stop and surface it (§11). **`BLOCKED`** -> the refusal reads `not mergeable: the base branch policy prohibits the merge`: some branch-protection requirement is unmet. Never re-fire the merge, and never reach for a different endpoint to land it - a second door is still a bypass (§11). Name the cause before acting: `reviewDecision` not `APPROVED`, or any required check not yet `SUCCESS` -> **wait**. Already approved and green -> the usual remainder is an unresolved review thread under *require conversation resolution*, which `gh pr view --json` does not expose - read them with §8's `reviewThreads` query and resolve them. Still unexplained -> stop and hand it to the user: it is a protection the PR JSON cannot see (merge queue, required deployment, signed commits, linear history). `--auto` is available to land it when CI goes green, but do not use it when a post-merge step (a deploy watch, a ticket hand-off) must run right after the merge.

`gh pr merge <PR> --repo {org}/{repo} --squash --delete-branch` closes the PR and removes the remote branch. **Run it unpiped** - `| tail`/`| head` returns the *filter's* exit status, so a refused merge is recorded as a successful call (§4's pipe-to-`/tmp` rule is for reads, not for mutating commands). Unless you passed `--auto`, confirm it landed before any post-merge step: `gh pr view <PR> --repo {org}/{repo} --json state --jq .state` must read `MERGED`; anything else means GitHub refused it - read the refusal message and branch above, do not retry. Then sync the local base branch:

```bash
git -C {workspaceRoot}/{repo} fetch origin --prune
git -C {workspaceRoot}/{repo} checkout {baseBranch}
git -C {workspaceRoot}/{repo} pull --ff-only origin {baseBranch}
git -C {workspaceRoot}/{repo} branch -D {headRefName} 2>/dev/null || true
```

Merge only an **approved + green** PR (§11).

---

## 7. Reading CI checks

- Snapshot: `gh pr view <PR> --json statusCheckRollup` or `gh pr checks <PR> --json name,bucket,state` - key off **`bucket`** (pass/fail/pending/skipping), not per-step state; use `--required` (fall back to all if none required).
- **Green describes the base the checks last ran against, not today's base.** A `pull_request` run tests head merged with the base *as of that run*; GitHub never re-runs it when the base later moves, and `mergeStateStatus` says `BEHIND` only where the repo *requires* up-to-date branches - so a long-open PR reads `CLEAN` + all-green against a base that no longer exists. Whenever you hand a green verdict to a human (asking for review, "ready to merge", §6's merge gate), read the gap once and **state the number** with the verdict: `gh api repos/{org}/{repo}/compare/{baseRefName}...{headRefName} --jq .behind_by` - use the PR's own `baseRefName` (§5: it is not always `{baseBranch}`). Double-digit, or the base has since landed something this PR touches -> `gh pr update-branch` (§6), then re-read the checks that update re-triggers. Never fire `update-branch` from a watch loop - it pushes a commit and restarts CI; there, just report the count and leave the refresh to the merge step. (Real case: a green PR 180 commits behind base was rejected on review - its checks described a merge that no longer existed.)
- Watch transitions by emitting only on a bucket change, so a `pass -> fail` flip is caught.
- Locate a deploy/workflow run by merge SHA: `gh run list --repo {org}/{repo} --branch {baseBranch} --event push --json databaseId,workflowName,headSha,status,conclusion --jq '[.[]|select(.headSha=="'$SHA'")]'`.

---

## 8. Reading review comments / threads

- Unresolved threads: `gh api graphql` on `pullRequest.reviewThreads { isResolved, comments { ... } }`.
- Per-PR comment sweep: `gh api --paginate ".../{issues,pulls}/{pr}/comments?since=<ISO>"` gated on each comment's `created_at` - **never** track progress by `max(.id)` of a single page (misses paginated/older comments).
- Reply to a review comment: `gh api .../pulls/{pr}/comments/{id}/replies -f body=...`.
- Resolve a thread: the `resolveReviewThread` GraphQL mutation.
- Always select fields (§4) - review payloads are `diff_hunk`-heavy.

---

## 9. Review-as-PENDING (hard rule)

When posting a code review on someone else's PR, create it as **PENDING** via `gh api .../pulls/{pr}/reviews` - **never auto-submit**. Inline comments anchor to RIGHT-side line numbers (walk the diff to compute positions). The human submits: right after posting, ask for the verdict (approve / request changes / leave pending) and submit only the chosen one.

---

## 10. Multi-repo PR discovery

- Open PRs across repos: loop `gh pr list --repo {org}/$repo --state open --json number,title,headRefName` over `repos[]`.
- Changed repos this session: `git -C {workspaceRoot}/$repo status --porcelain` + current branch vs `baseBranch`.

---

## 11. Safety rules (hard)

- Never `--force`, `--force-push`, `--admin`, `--no-verify`, or bypass branch protection.
- Never merge a PR that is not **approved + green** (an unrelated flaky check may be re-run once; a real failure stops the flow).
- **A user override of these rules is scoped to what was named when it was granted, and expires with it.** "Merge them all with admin bypass" covers the PRs on the table at that moment - not a PR opened afterwards, not a different ticket, not the next day. When the user grants one, state back which PRs it covers; when you later reach for it, re-check that the PR was in that set. If it was not, ask again. A PR created *after* the override has by definition never been seen by the person who waived the review, which is the whole thing the review requirement protects.
- Lint before commit; never blind `git add -A`; sensitive-file check before staging.
- Never auto-resolve merge conflicts: stop and surface them.
- Never amend or rewrite pushed history.
- **Someone else's commit is already pushed on your branch and you cannot reach its author** (typically a parallel session on a shared checkout): do not `revert` it either - their work may still be in flight. Cherry-pick **your** commits onto a fresh branch, open a new PR, close the old one with a one-line explanation. (A teammate's review-suggestion or co-author commit on your PR is normal - leave it alone; this is only for a commit that does not belong on the branch at all.)

---

## Quick checklist for any git/gh action

1. Git command? -> `git -C {workspaceRoot}/{repo}`, never `cd`. Reading a ref? -> `"${REF}:{path}"`, braced.
2. `gh` read? -> `--jq`/`--json`, never raw (diff_hunk).
3. Commit? -> `{ticket}: {message}` <=72, lint first, explicit staging, no `--no-verify`.
4. PR? -> body template + Related PRs + Claude footer; no ticket -> no tracker link.
5. Merge? -> squash + delete-branch, only approved + green; `BEHIND` -> `update-branch` first.
6. Review? -> PENDING, never auto-submit.
7. Never `--force`/`--admin`/bypass.
