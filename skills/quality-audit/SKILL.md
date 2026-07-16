---
name: quality-audit
description: Adversarial audit of recent changes for security, performance, and maintainability. Fresh subagents grade the work so the session that implemented it isn't reviewing itself. Default (light) launches one adversarial reviewer; ultra mode dynamically scales a multi-agent fleet with verification; --inline runs the audit in-session with no subagents at all. Stack-agnostic. Use after implementing features or fixes.
user-invocable: true
argument-hint: "[ultra] [file/directory/scope] [--agents N (ultra only: reviewers per area)] [--inline (no subagents)]"
---

You are the **orchestrator** of an adversarial quality audit. In every mode except `--inline`, you do NOT audit the code yourself — you scope the work, dispatch fresh adversarial reviewer agent(s), and report the results.

**Why you must not grade:** this session likely implemented the changes under review. You carry the implementer's assumptions, rationale, and blind spots. Every judgment call about whether code is correct, secure, or performant belongs to a subagent with clean context. Your only jobs are mechanical: scoping, dispatching, deduplicating, and reporting.

`--inline` deliberately trades that guarantee away for speed and zero agent overhead. It is the one mode where you grade. See **Inline mode** for what that costs and when it's defensible.

If a project-specific `quality-audit` skill exists in the current repo, prefer that one — it encodes conventions this generic version has to discover.

## Modes

Parse `$ARGUMENTS` for a mode keyword first:

- **light** (default — used when no mode keyword is present): ONE adversarial reviewer agent carrying the full merged checklist. Fast, cheap, still context-clean. Right for routine post-implementation checks.
- **ultra** (keyword `ultra` or `--ultra`): dynamically scaled multi-agent fleet — the diff is partitioned into areas, each area gets multiple lens-specialized reviewers sized to the diff, and CRITICAL/WARNING findings get adversarial verification. Right for large, risky, or security-sensitive changes. `--agents N` (minimum 2) overrides the per-area reviewer count and is only meaningful in ultra mode.
- **inline** (flag `--inline`): NO subagents. You run the whole audit yourself in this session against the merged checklist. Forfeits the context-clean guarantee the rest of this skill exists to provide, so the report must say so.

`--inline` is mutually exclusive with `ultra` (a fleet is the opposite of inline) and makes `--agents` meaningless. If both a mode keyword and `--inline` are present, say plainly that they conflict, honor `--inline` (the explicit flag beats the keyword), and note it in the report.

Remaining arguments are an optional file/directory/scope filter.

## Step 0: Establish scope and ground rules (all modes)

1. Run `git diff` and `git diff --staged` (plus `git diff <base>...HEAD` if the changes are committed on a branch) to get the authoritative list of changed files and hunks. Do not rely on your memory of what you edited. Also run `git diff --stat` (same variants) — you need per-file changed-line counts to size the audit.
2. Apply the scope filter from `$ARGUMENTS` if one was given.
3. Locate the project's convention sources: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` — note their paths. In light and ultra, point reviewers at these files rather than summarizing them (your summary would carry your bias about which rules matter). In inline, read them yourself, in full.

## Context hygiene rules (light and ultra — these are the point of the skill)

These govern what you hand a reviewer. `--inline` has no reviewer to hand anything to, so they don't apply — which is exactly what it costs you. Inline still reuses the framing and output contract below, addressed to yourself.

- Give each reviewer ONLY: the file paths in scope, the relevant diff hunks (or instructions to run `git diff -- <paths>` themselves), and pointers to the convention files from Step 0.
- Do NOT tell reviewers what the change was "supposed to do", why it was implemented this way, or that it "should be fine". No implementation narrative, no design rationale, no excerpts from this conversation. The diff and the code are the whole story.
- Do NOT hint at expected findings or areas you believe are clean.

Every reviewer prompt must include, verbatim:

1. The framing: *"You are a hostile senior reviewer. Assume this code was written carelessly and your job is to find what's wrong with it. You get no credit for saying it looks fine; you get credit for real defects with evidence. Read the actual code — not just the diff — before judging. First read any CLAUDE.md / AGENTS.md / CONTRIBUTING.md at the paths given and treat explicit project-convention violations as findings. Identify the stack and the project's established auth/data-access patterns from the code itself; flag changed code that deviates from how the rest of the codebase does it."*
2. The relevant checklist(s) (from the **Checklists** section below — copy them into the prompt; subagents cannot see this skill file).
3. The output contract: *"Return raw findings as a JSON-style list, one entry per finding: `{severity: CRITICAL|WARNING|SUGGESTION, file, line, issue, evidence (the exact code that demonstrates it), suggested_fix}`. Return an empty list if you genuinely found nothing after reading every file. Do not pad with speculative or stylistic filler to appear thorough."*

---

## Light mode (default)

Dispatch **exactly one** reviewer agent covering the entire scoped diff. Its prompt gets the framing, the output contract, and ALL checklists merged (security + performance + correctness & maintainability, plus the frontend checklist if any frontend files changed). Tell it to work security-first — that's the checklist you least want diluted when one agent carries everything.

No verification fan-out and no partitioning: the single agent's findings pass straight to the report. If the reviewer returns a finding you have strong mechanical evidence against (e.g. it cites a line that doesn't exist), note that in the report rather than silently dropping it — you still don't get a vote on judgment calls.

If the diff is very large (roughly 800+ changed lines or 15+ files), say so and recommend re-running with `ultra` — but still run the single agent unless the user objects; light mode is the contract they invoked.

Then go to **Report**.

---

## Ultra mode

### Step 1: Partition into code areas (orchestrator)

Group the changed files into **areas** — coherent units a reviewer can hold in context:

- Group by feature/module/layer (e.g. one backend endpoint + its service + its tests = one area; a frontend page + its components = another).
- Target roughly 2–8 files per area. A single large file can be its own area. Never split one file across areas.
- List the areas, their files, and each area's changed-line count and chosen reviewer count (Step 2) before dispatching, so the user can see the partition and how it was sized.

### Step 2: Dispatch adversarial reviewers (subagents)

For **each area**, launch **N reviewer agents in parallel** (all areas, all reviewers, in a single batch of Agent tool calls — they are independent).

**Choosing N per area (unless `--agents` was passed):** sum the changed lines for the area's files from the `--stat` output.

- Under ~200 changed lines → **N=2**. A reviewer can hold a merged checklist against a small diff; the extra agent is mostly redundant reading.
- ~200 changed lines or more → **N=3**. On large diffs a combined reviewer under-reports performance issues — N+1s and index gaps only get caught when someone is deliberately looking for them.

An explicit `--agents N` overrides this in both directions and applies to every area.

**Assign each of the N reviewers a distinct adversarial lens** so diversity catches what redundancy can't. **Security is always its own lens, never merged** — it demands a different posture (attacker mindset, tenancy, IDOR) than behavior-reading, and it's the checklist you least want diluted. With N=3: security, performance, correctness & maintainability. With N=2: security, performance+correctness+maintainability combined (give that reviewer both checklists). With N>3, add lenses: concurrency/race conditions, error handling, API-contract/data-exposure, frontend/XSS (if frontend files exist).

### Step 3: Verify findings (subagents)

Deduplicate the raw findings across reviewers by (file, line-range, issue). Merging duplicates is mechanical — that's yours. Judging validity is not.

For each unique CRITICAL or WARNING finding, dispatch a fresh **verifier agent** (parallel batch) whose prompt is: *"Attempt to refute this finding: [finding with evidence]. Read the actual code at [file]. It is only confirmed if the defect is real, reachable, and the evidence holds. Preexisting-code issues outside the diff are noted as such, not attributed to this change. Return CONFIRMED or REFUTED with one sentence of justification."*

- A finding two independent reviewers both raised may skip verification (independent agreement is the signal).
- Drop REFUTED findings from the report (list them in one line at the end as "raised but refuted", so the process is transparent).
- SUGGESTIONs pass through unverified but clearly labeled.

---

## Inline mode (`--inline`)

No subagents. You read the code and produce the findings yourself, in this session.

**Know what you are giving up.** Every other mode exists because the session that wrote the code cannot fairly grade it: you know what the code was *meant* to do, so you read intent where a stranger reads only text. Inline mode does not solve that problem, it accepts it. The failure mode is specific and predictable — you will skim the parts you are confident about, and those are exactly the parts where your confidence came from having written them.

**When it's genuinely defensible:**

- **The diff is not yours.** A pulled branch, a colleague's PR, a dependency bump, code from a previous session you no longer have context on. The implementer-bias argument simply doesn't apply, and inline costs you nothing but breadth.
- **Fast triage.** You want the obvious defects now and a real audit later. Say that in the report.
- **Subagents are unavailable or unwanted** for cost, environment, or noise reasons.

**When to refuse politely and recommend `light` instead:** you implemented the diff in this session AND it touches auth, tenancy, money, or data deletion. Say so, in one sentence, and let the user override. `light` is one agent — the overhead you're avoiding is close to nothing, and those are the four areas where implementer blindness gets expensive.

**How to run it:**

1. Do Step 0 exactly as written — the scoping is mechanical and unchanged.
2. Read the convention files (`CLAUDE.md` / `AGENTS.md` / `CONTRIBUTING.md`) yourself, in full. Do not rely on what you remember of them from earlier in the session. Treat explicit violations as findings.
3. Read every changed file in full — the actual code, not just the diff hunks. This is the step you will be most tempted to skip and the one that carries the mode.
4. Apply ALL checklists (security + performance + correctness & maintainability, plus frontend if frontend files are in scope). Work **security-first**, for the same reason light mode does: it's the checklist that degrades first when one reader carries everything.
5. Turn the framing on yourself, verbatim: *"Assume this code was written carelessly. You get no credit for saying it looks fine; you get credit for real defects with evidence."* If you catch yourself writing "this is fine because I intended X" — that's not evidence, that's the bias the rest of this skill was built to route around. Cut it.
6. Findings use the same output contract: severity, file, line, issue, evidence (the exact code), suggested fix. An empty list is a legitimate result. Do not pad with stylistic filler to look thorough.

No partitioning, no dedup, no verification fan-out — there's one reader and it's you.

Then go to **Report**.

---

## Report (orchestrator, all modes)

**In `--inline` mode, open the report with this line, before any findings:** *"Inline audit: no subagents. Reviewed in-session, so this does not carry the clean-context guarantee — findings are real, but absence of findings is weaker evidence than a light/ultra run."* If this session also wrote the diff, say that in the same line. The user needs to know which product they're holding.

Report findings, CRITICAL first, then WARNING, then SUGGESTION:

- **Severity**: CRITICAL / WARNING / SUGGESTION
- **File & Line**: exact location
- **Issue**: what's wrong
- **Fix**: specific code change to resolve it
- **Provenance**: which lens(es) found it; in ultra mode, whether it was verified or dual-reported; in inline mode, omit (there's one reader)

If everything passes, say so, and summarize the coverage: in light mode, the file list and that a single merged-checklist reviewer read it; in ultra mode, the partition (areas, files, reviewers per area, lenses used); in inline mode, the file list and which checklists you carried.

Do not editorialize about findings ("this one is probably fine because…"). In light and ultra that's because you don't get a vote. In inline you do get the vote, which makes it worse: talking yourself out of a finding you already surfaced is the exact failure this skill exists to prevent, and there's no verifier agent to catch you doing it. Report it and let the user decide.

Do not apply fixes — this skill reports; the user decides what to act on.

---

## Checklists (copy the relevant one(s) into each reviewer's prompt)

### Security lens

- Every new/changed endpoint enforces authentication (guard, middleware, decorator — whatever this project uses); no accidental public routes
- Authorization checks match the project's established pattern; no hand-rolled checks alongside an existing abstraction
- Multi-tenant scoping: every query touching tenant/org/user-owned data is filtered by the caller's access — never trust an ID from the request without verifying the caller can access it (IDOR)
- Raw SQL or ORM-bypass queries replicate the access checks the abstraction they bypass would have enforced
- All user input validated at the boundary (schema validation, DTOs, parsers)
- No SQL injection (string-built queries, dynamic column/table names), command injection, path traversal, or template/expression injection
- No unsafe deserialization of untrusted data
- No sensitive fields leaked in responses (passwords, tokens, secrets, other users' data) — check serialization defaults, not just explicit returns
- Secrets not hardcoded or logged; error messages don't leak internals
- Correct status codes for access failures (403 vs 404 — don't confirm existence of resources the caller can't access)

### Performance lens

- No N+1 patterns (queries or remote calls inside loops)
- New WHERE clauses / lookup patterns supported by indexes, or an index added
- Large collections paginated or streamed — never fully loaded when they can grow unboundedly
- No unbounded growth in hot paths (accumulating arrays, string concat in loops, caches without eviction)
- Independent async operations run concurrently instead of sequential awaits in loops
- ORM relation loading targeted, not pulling entire object graphs
- No blocking/synchronous I/O on request paths in async runtimes

### Correctness & maintainability lens

- Error handling is real: failures surface to the caller or are deliberately handled — no swallowed exceptions, no fire-and-forget async whose failures vanish
- Resources cleaned up (connections, file handles, listeners, timers, subscriptions)
- Concurrency hazards: races on shared state, non-atomic read-modify-write on data multiple callers touch
- Edge cases: empty collections, null/undefined, zero, unicode, very large inputs
- No duplicated logic that already exists in a base class, utility, or shared lib — search before assuming it's new
- Types reflect runtime structure; no `any`/casts/suppressions papering over a modeling problem; no non-null assertions where the value can genuinely be absent
- Helpers live in the right layer; naming and idiom match surrounding code; dead code and debug logging removed
- Framework idioms followed (DI over manual instantiation, framework lifecycle over ad-hoc hooks); no deprecated APIs in new code

### Frontend lens (add when frontend files are in scope)

- No XSS vectors (`innerHTML`/`v-html`/`dangerouslySetInnerHTML` with user data, unescaped interpolation, unsanitized URLs)
- State managed per the framework's rules (no direct prop mutation, correct dependency arrays/reactivity)
- API calls handle errors and loading states; no unhandled rejections
- Auth/tenant context attached to requests the same way the rest of the app does it
- No leaks: listeners removed, intervals cleared, subscriptions disposed on unmount
