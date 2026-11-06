# Code Review Rules

Shipped with JB Kaizen. Shared rules for `review-code` (self-review) and for reviewing someone else's pull request.

## Strictness Levels

- **STRICT** - self-review (`review-code`): all tiers P0-P4, including items marked `[STRICT]`
- **STANDARD** - reviewing someone else's PR: P0-P2 always; P3-P4 only if severe

## Priority Tiers

### P0 - Bugs & Correctness `[STANDARD]`

- Logic errors, broken control flow
- Error handling that changes HTTP status contracts (e.g., 400 swallowed as 500), including a caught failure answered with a success status (2xx, or an error-shaped body behind 200) to a caller that only retries on non-success (webhook sender, queue, at-least-once client) - the delivery is consumed and never redelivered. Not a finding when the ack is deliberate for a payload that can never succeed, or the failure is durably recorded for reprocessing.
- Race conditions, TOCTOU issues in critical paths
- Null/undefined that will crash at runtime
- **Guard that can never fire** - a check whose expression the producer makes structurally always-true or always-false, so the failure branch is never taken. Most often a falsy test on a wrapper the callee always constructs (`if (!task)` where it returns `{ id: raw?.id || '' }`) while the empty *field* inside is the real failure. Check every return path of the producer before flagging; flag only when the caller then commits irreversible state on the bad value - a dead nullish check whose caller does nothing irreversible is dead code, not P0.
- Missing `await` on async calls
- **Not safe to run twice** - a handler fed by a retrying/at-least-once source (webhook, queue, client retry) or a re-runnable script (migration, seed, cron job), where a redelivery or a re-run over partially-applied state produces a *visible* wrong effect: a duplicated side effect, a double write, or destroyed data (e.g. a lookup miss that makes previously-written rows look orphaned and deletes them). The missing guard is not by itself the finding - name what the second run breaks.
- **Truncation reported as success** - a bounded loop or batch breaks on a page/iteration cap (or skips items), logs a warning, and the returned result still reads as complete. Flag only when something downstream *acts* on the partial set as if it were whole: a dedup/collision guard, a "not found", a total, or a subsequent write. A bounded read whose caller already treats the result as partial is not a finding.
- **Read-only implemented as `disabled`** - a `readOnly`/view-only mode implemented by setting the native `disabled` attribute, directly or through a component library's `disabled` prop. A disabled control is removed from the tab order and its value is excluded from the submitted form data, so a value the user is meant to read, and the server is meant to receive, becomes unreachable by keyboard and silently missing on submit. Flag only when the intent is "visible but not editable"; a control that is genuinely unavailable is correctly disabled. The fix is control-specific - native `readonly` exists on text `input`s and `textarea` only, so for `select`/combobox/custom widgets the read-only mode must instead keep the control focusable and its value submitted (suppress changes and set `aria-readonly`, or render the value as focusable text plus a hidden input).
- **A guard offered as a fix that can never run** - when a diff adds an early return/guard *as the stated fix for a specific reported defect*, enumerate the function's call sites before accepting it. If every call site already enforces the same condition, the guard never executes and the runtime behaviour is identical to before the change, so the reported defect is still open - say that instead of approving the fix. Requires both halves: a defect the guard claims to close, and call sites you can fully enumerate. A redundant guard on an exported/public entry point, or one nobody presents as a fix, is defence in depth and is not a finding. A sort, top-N or dedup computed in memory over a single already-paged page counts as acting on the partial set as whole - the true top-N need not be in the page; flag it only when the code presents the result as the whole set's answer.

### P0.5 - Security `[STANDARD]`

- Database queries missing owner/tenant scoping - use the scope column the **model** declares (`userId`, `accountId`, or a domain FK), not only those two names. Flag a *multi-row* read/write (`findMany`/`updateMany`/`deleteMany`/raw SQL) on a model whose scope FK is **required**, when the `where` constrains neither that column, nor a relation carrying it, nor a globally-unique id - confirm against a sibling query on the same model that does scope. Not a finding when the scope column is nullable, the table is a global lookup with no owner, the query resolves the scope itself, scoping is enforced by middleware/RLS/a base repository, or the caller is a deliberately cross-tenant admin/migration/job path.
- Missing authentication guards on endpoints
- Input validation gaps (missing DTO decorators, no Zod schema)
- **Decoded is not validated** - a `JSON.parse` / base64 / query-string decode of external input consumed as a typed value with no shape check: `42`, `[]` and `{"wrong":"keys"}` all survive the cast and are read as well-formed. Flag only when the wrong-shaped value then reaches a branch or a write, and name the value that slips through. Not a finding if the result is narrowed by a schema, type guard or DTO before use.
- **Falsy read as absent** - a truthiness guard (`if (decoded)`, `!value`) standing in for an existence check on a value whose declared type legitimately admits `0`, `false` or `""`, so a present value is handled as missing. Flag only when such a value is actually reachable and the wrong branch has a visible effect; name it. Truthiness on a type that cannot hold a meaningful falsy member, or an explicit `=== undefined` / `in` / `??` check, is not a finding.
- Sensitive data exposure in responses or logs
- SQL injection, XSS vulnerabilities
- **Percent-encoding treated as path containment** - a user-supplied id or segment reaches a filesystem path (`fs` call, `path.join`/`path.resolve`) or an outbound/proxied URL path, and the only guard is `encodeURI`/`encodeURIComponent`. Encoding escapes separators; it does not constrain where the path lands. `encodeURI` leaves `/` intact, so a full `../../` survives verbatim. `encodeURIComponent` does encode `/` to `%2F`, but leaves `.` and `..` untouched - so an id of exactly `..` still climbs a level (`path.join('/srv/root', '..')` -> `/srv`), a URL path segment `..` is normalized away by the URL parser and changes which endpoint is hit, and any later `decodeURIComponent` (or a proxy that decodes `%2F`) restores the rest. Require actual containment: `path.resolve` then verify the result still starts with the intended root, or validate the id against its format (uuid/numeric/allowlist). Do not flag query-string or body values, or a segment encoded into a URL when the id is already format-validated - there encoding is the correct fix.
- **A default that points at production** - a `??`/`||` fallback or config default that resolves to the live host, key, bucket, tenant or queue, so any environment missing the variable reads or writes production. Judge the direction of the default: a value identical in every environment (a vendor's public endpoint) is fine; one that must differ per environment should be inert or fail loudly when absent.

### P0.7 - Cross-Service Contract Consistency `[STANDARD]`

Applies when a single ticket spans multiple PRs/repos (e.g. a back-end API PR + a front-end PR that consumes it), and when a change lands on something shared *inside* one repo. Review the sharing sides together and verify the contract holds end-to-end:

- **Field name / casing drift** - back-end returns `documentReferenceIds`, front-end reads `documentIds` (or `snake_case` vs `camelCase` mismatch). Silent `undefined` at runtime.
- **Type / shape mismatch** - back-end returns an array, front-end expects a paginated object; nullable on one side but dereferenced unconditionally on the other.
- **Enum / status value mismatch** - front-end switches on string literals the back-end never emits (or vice-versa).
- **HTTP contract** - front-end expects 200 with a body where the back-end returns 204; error-shape assumptions that don't match the API's actual error payload.
- **Route / method mismatch** - path params, query params, or verbs that don't line up between client call and server handler.
- **Auth / scoping assumptions** - front-end sends an identifier the back-end ignores or scopes differently.
- **Shared-symbol consumer drift** - a shared helper, constant, type or hook changed, but only some of its call sites were updated. Grep the symbol and confirm each remaining call site still holds under the new behaviour. Flag only call sites that are now *wrong*, never ones merely unmentioned. (A secondary write path bypassing the primary path's guard/lock is P0's TOCTOU bullet, not this one.)

When flagging, name both sides (file:line on each side) and state which side should change.

### P0.8 - Architecture Conformance: extend, never duplicate `[STANDARD]`

A change must plug into the architecture that already owns its concern - call its entry point, add a case at its extension point - never build a second one beside it. A parallel path works on day one and then drifts: the next fix lands in one copy only. This tier is judged against an **Architecture Map** of the base branch, built before any analysis; a review without the map has not run this tier.

**Building the map** - on the base (`origin/<base>`, or the merge-base for a self-review), never the PR head, which already carries the deviation:
1. **Name the concerns** the diff touches - from the ticket, the changed paths and the symbols it adds (avatars, phone input, permissions, file intake, notifications, ...).
2. **Find the owning layer** of each: `graphify query "<concern>"` / `graphify explain "<concern>"` from the workspace root when `graphify-out/` exists, then the module itself (`src/<concern>/`, `libs/*/src/<concern>/`, shared libs), `docs/`, the repo `CLAUDE.md` and `.claude/rules/*.md`, and any lint or boundary rule that enforces it (restricted imports, custom lint rules, nx module boundaries).
3. **Read its intent**: `git log --oneline -- <layer path>` on the base finds the tickets and PRs that built it; read their bodies (`gh pr view <n> --json title,body`) for the design rules ("single read path", "every fetch goes through the registry", "each owner module owns its write").
4. **Write the map** in 5-15 lines: entry points (endpoints, services, clients, hooks, components), the rules it owns (classification, ownership/permission predicates, path/prefix builders, cache keys, query config), its extension points (registry, strategy, enum, lane, adapter), what is deliberately per-module, and what it has retired.

Scale the effort to the diff, but never skip it - a two-file diff can still re-implement a rule a central helper owns. A multi-PR ticket gets one map spanning every repo in the group. When no owning layer exists, say so in the report; the PR may then establish one, judged under P1.

**Flag** - every finding cites both sides, the layer element at `file:line` on the base and the diff's `file:line`:
- **Parallel path** - a second endpoint, service, client, hook or component for a concern the layer already serves (a second read path, a second upload flow, a second fetch client).
- **Owned rule re-implemented** - a decision the layer owns (classification, ownership or permission predicate, source selection, blob path/prefix, cache key) rewritten in a controller, service or page. Semantic equivalence is enough - unlike P1.5 it need not be verbatim, because the copy stays equivalent only until the layer changes.
- **Shared config copied** - query options, keys, freshness/GC/retry settings or lanes duplicated, or a registry the layer routes every fetch through bypassed.
- **Extension point skipped** - the layer has a registry, strategy, enum or lane for new cases, and the diff special-cases with if/else at the call sites instead.
- **Nth copy** - the diff adds a third copy of logic that already exists twice. Ask for one helper in the layer that owns the rule, used here; moving the older copies can be a follow-up.
- **Retired surface fed** - the diff extends a path, field or flag the architecture removed (a field no client reads, a dropped read path), or leaves a comment or doc describing the old design as current.
- **Enforcement bypassed** - a lint disable, boundary-rule exception or deep import used to reach around the layer.

**Not a finding:** what the map records as deliberately per-module; a diff that extends the layer at its seam (a new registry entry, a new strategy); an exception documented in an ADR, `docs/` or the ticket; duplication that predates the diff and that the diff neither touches nor adds to; logic that cannot reach the layer across a dependency boundary (a `ui` lib cannot import `features`) - unless the right fix is to move the rule down into the lower layer.

**Reporting:** name the layer element and the ticket or PR that introduced it, the bypass, what will drift, and a concrete fix that routes the change through the layer. Every confirmed finding is reported - exempt from "when in doubt, skip it" - and one without the base-side `file:line` is not confirmed and is dropped. Summarise each ticket as **FOLLOWS / PARTIAL / BYPASSES** with the layer's name.

### P1 - Architecture & SOLID `[STANDARD]`

- **Single Responsibility**: class/method does more than one thing
- **Open/Closed**: behavior can't be extended without modifying existing code
- **Liskov Substitution**: subtypes not properly substitutable
- **Interface Segregation**: interfaces too broad
- **Dependency Inversion**: depending on concretions instead of abstractions
- God classes (>500 lines) or god methods (>200 lines)

### P1.5 - DRY: Reinventing Existing Code `[STANDARD]`

- Use parallel Explore agents to search for existing implementations before flagging - the duplicate is usually in a file the diff never opens, or a few lines above in the same file. Search by the changed file's own name and suffix (the other `*-mapper.service.ts`, the same-named file under each sibling app) and by the distinctive identifiers in the body, not only the shared `utils/`/`common/` directories. Flag only a near-verbatim body - identical line for line, differing in one argument, a comparator or a literal; structural similarity between per-module implementations is not a finding.
- If an existing utility/helper/mapper does the same thing - comment with the path and suggest reuse
- If an existing implementation is close but not identical - suggest extending it

### P1.6 - File Structure & Conventions `[STANDARD]`

- New files not following the project's module organization pattern
- Wrong test file naming (`.test.ts` vs `.spec.ts` - must match project convention)
- New tests must use the project's established test framework and layout (its page objects, fixtures, helpers and reporters); flag bespoke Node runners (`console.log` + `process.exit`) as P1, even for API-only flows and the first test in a repo
- Missing module registrations or incorrect import patterns
- File casing mismatch with existing files in the same directory

### P1.7 - Code Comments `[ALWAYS STRICT]`

P1.7 runs at STRICT rigor in every mode, including a STANDARD PR review. It is exempt from the STANDARD filter and from "when in doubt, skip it". The standard is self-documenting code (a project CLAUDE.md may tighten it further): every comment has to earn its place.

**Scope:** every comment line the diff adds or modifies, in production and test files alike. That covers `//`, `/* */`, JSDoc/TSDoc, JSX `{/* */}`, trailing `// ...` after code, and `#`/`--` in SQL, YAML, HCL and shell. Comments the diff does not touch are out of scope, except deleted rationale (last paragraph). Generated code is out of scope too, for example Prisma migration headers such as `-- CreateTable`, and codegen output.

**A comment stays only when it is one of these, in 1-2 lines:**
- A non-obvious invariant, or a domain or regulatory rule (a privacy law, a protocol spec, consent semantics). State the rule, not how it was found.
- A workaround pinned to an external constraint, a bug ticket or an upstream issue.
- A `TODO`/`FIXME` carrying a ticket key.
- A lint or type suppression with its reason.

**Flag everything else, in particular:**
- **Obvious/redundant** - restating what the code already says.
- **"What" instead of "why"** - narrating the code rather than explaining reasoning.
- **History / review archaeology** - "used to", "previously", "originally", "was X", "we found", before/after numbers, commit SHAs, review-thread or Jira-comment citations. State the current rule in 1-2 lines; the story belongs in the PR body.
- **Oversized** - more than 2 lines for one invariant, multi-paragraph JSDoc, or long inline blocks. Shorten it to the invariant.
- **Stacked or orphaned doc comments** - two `/** */` blocks on one symbol (only the last one attaches), or a doc comment separated from the symbol it documents.
- **Trivial JSDoc** - e.g., `/** Returns the name */` on `getName()`.
- **Section dividers**.
- **Stale or misleading** - the comment does not match current code behavior. The same rule applies to any prose the diff adds or touches that a reader acts on: an input/parameter `description`, a README or docs line, a header comment. Check the claim against the code it describes and flag mismatches, quoting both sides. Rate it by the wrong action a reader would take, not as a doc nit. Unlike the bullets above, the defect here is that the text is wrong, not that it is redundant.

**Reporting:** post one inline comment **per file** that has offenders, anchored on the first offending line.
- Give the count, and list **every** offending line with its action: delete, replace with a quoted one-liner, or rename a symbol so the comment is unnecessary.
- Never collapse a PR into one sample comment, and never stop at "e.g.". The author must be able to fix every instance from the list alone.
- A file whose added comments all qualify gets nothing.

Flag the reverse too: **rationale deleted that the branch never added** - comment hunks that are deletion-only in a file whose code this change does not otherwise alter, losing a legend, a section header, or a note on why an odd-looking form is deliberate. The removal is in the diff, so the pre-existing-issue exclusion does not apply; ask for those lines back verbatim from the base revision. Not a finding when the code the comment described went with it, when this branch added the comment, when stripping that file's comments was the requested change, or when the comment was stale/misleading per the bullet above - deleting those is the fix, not over-reach. One finding per file, anchored on a surviving line.

### P2 - Type Safety `[STANDARD]`

- Usage of `any` type - zero tolerance in STRICT, flag in STANDARD
- Untyped function parameters or return values
- Missing DTO decorators for API inputs/outputs

### P2.5 - React Performance `[STRICT]`

- More than 2 `useSelector` calls per component (prefer 1 composite selector)
- `axios` calls in components instead of React Query
- Missing memoization (`React.memo`, `useMemo`, `useCallback`) where re-renders are costly
- Missing `shallowEqual` with object/array selectors
- Multiple boolean flags instead of a single status enum

### P3 - Test Coverage `[STRICT]`

- Missing tests for business logic happy paths
- Missing tests for critical error paths
- **A new branch tested on only one side** - when the diff adds a decision *and* adds or edits the spec for that unit, check that some fixture lands on each side. A green, on-topic suite is not evidence: the recurring shape is that every case builds the input where the new code is safe and none builds the one that motivated the change (every mock returns an object body, so the empty-body response the branch exists for is never constructed; every fixture gives a permission exactly one role, so the two-roles-one-permission case cannot occur). Flag by naming the exact input no case constructs, and only when the uncovered side changes an observable outcome - a permission, a status code, a persisted or returned value. Not a finding when the type makes that side unreachable, when a sibling spec already covers it (search first), or for a trivial defensive default. A decision with *no* test at all is the bullet above.
- Test assertions that don't verify actual behavior (e.g., only checking `.toBeDefined()`), or a
  fixture/predicate that can never reach the asserted branch - the assertion is green because it
  never runs, not because the behaviour holds
- **A spec file replaced wholesale loses cases** - when a diff rewrites a test file instead of editing it, compare the `it()`/`test()` names on both sides and flag only names with no equivalent in the new file (a parameterized `each` case counts as equivalent), naming the behaviour now untested
- **A test offered as the proof of an access boundary is proven by mutation, not by reading** - when the diff adds a test as the evidence that an authorization/permission/tenant-isolation rule holds, green proves nothing by itself: the fixture may never apply the permission, the asserted field may never be emitted, or the route may be gated on the very permission the test uses to demonstrate the refusal. Only when you can both edit files and run tests: break the one production line that test names, re-run that single test, confirm it goes red, then edit the line back and re-run it to green - restore by reversing the edit, never with `git checkout`, since the branch's own changes to that file may be uncommitted. Say which mutation you ran. Boundary tests the diff adds only - a test run per mutation is too costly as a default. If you cannot edit or cannot run tests, say the boundary is unproven instead of doing it.

### P3.5 - Framework Patterns (e.g. NestJS) `[STRICT]`

- Improper dependency injection
- Missing try-catch with proper logging in services
- Missing guards/decorators on endpoints
- SRP violations in services

### P4 - Domain-Specific `[STRICT]`

Whatever the project's CLAUDE.md declares as its domain rules, for example:
- Data-protection rules for personal data (what may be stored, logged or exported; audit trails)
- Standards compliance the domain requires (a protocol or schema spec)
- Multi-tenancy isolation (`accountId` scoping)
- Audit fields (`createdBy`/`updatedBy`) on mutations

## Filtering Rules

### STANDARD mode (PR review)

**INCLUDE:**
- Bugs that will cause incorrect behavior in production
- Architecture violations creating tech debt or maintenance burden
- Security issues
- Cross-service contract mismatches (front-end/back-end field/type/route/status drift) when reviewing a multi-PR ticket
- Every confirmed P0.8 architecture-conformance finding (both sides cited) - a change built beside the architecture is never "minor"
- Missing tests for core business logic paths
- File naming convention violations
- Every P1.7 comment finding - `[ALWAYS STRICT]`, exempt from the rest of this filter, reported per file with every offender listed
- DRY violations with confirmed existing implementations

**EXCLUDE (do NOT comment on):**
- Code style preferences (naming, formatting) - except file naming conventions
- Minor refactoring suggestions that don't affect correctness
- "Nice to have" improvements
- Things the linter would catch
- Items marked `[STRICT]` unless severity is high

When in doubt, skip it. Fewer high-quality comments > many minor ones.

### STRICT mode (self-review)

**INCLUDE everything from STANDARD, plus:**
- All `[STRICT]` tier items (P2.5, P3, P3.5, P4). P1.7 is `[ALWAYS STRICT]` and applies in both modes.
- Medium-priority improvements that improve maintainability
- React performance patterns
- Framework best practices (e.g. NestJS)
- Test coverage gaps

**EXCLUDE:**
- Code style preferences handled by linter/prettier
- Pre-existing issues not touched by current changes

## False Positives (exclude in both modes)

- Pre-existing issues not introduced by the reviewed changes
- Issues a linter/typechecker/compiler would catch
- Code style preferences (formatting, naming style)
- Issues with lint-ignore comments - explicitly silenced
- Something that appears to be a bug but is actually correct
- Changes in functionality that are likely intentional
