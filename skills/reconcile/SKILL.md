---
name: reconcile
description: >-
  Reconcile the open bd queue against ground truth — the durable notes in $AGENT_HOME and the actual code in the repos listed in the manifest — at two granularities: which issues should close or supersede, and which individual plan checkboxes the code proves are already done. Every close proposal and every tick must carry executable evidence from the codebase (a file/symbol/test that exists, a commit that landed, a check that passes); prose overlap alone is never enough. Use when the queue has drifted from reality — work shipped in sessions that never ran `close` or `check`, or several bds describe work one change already did. Run `--boxes` for the cheap tick-only sweep. Skip for a single issue you know is done (use `close`) or a single box you just finished (use `check`), and for draining capture into tasks (use `triage`, the forward direction). Predecessor: none. Successor: close / supersede / check.
---

## Codex host execution (mandatory)

When the harness is Codex, invoke every shell tool call that runs `bd` with `sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set `prefix_rule: ["bd"]`. The installed allow rule only pre-approves escalation—it does not move a default call outside the workspace sandbox. This applies to read-only commands too. If a sandboxed call reports a Dolt connection failure, retry at host level before diagnosing Dolt as down; wrappers inherit the sandbox. Claude Code and other non-Codex harnesses must ignore this section and use their normal execution path.

The queue rots in one direction: work ships, the session ends, `close` never runs and half the boxes it finished stay `- [ ]`. Six months later `bd ready` is fiction and every plan under-reports what's built. This skill re-grounds both by checking them against the two things that can't lie — the **durable record** (`$AGENT_HOME/summary`, `context`, `plan`) and the **code on disk** at the path the manifest gives for that project.

It reconciles at **two granularities**, and they use the same evidence bar:

- **Issue-level** — should this bd close, or supersede into another?
- **Box-level** — which `- [ ]` lines in the plan does the code already satisfy?

Box-level is not a consolation prize for issues that fail to close. A plan whose boxes are honest is what makes `attach` re-enter cold correctly and what makes peeking at a plan worth doing, so **every** bd in the worklist gets its boxes probed — including the ones headed for close, which get ticked *before* being handed off so the `plan ↔ summary` diff stays truthful.

**Trigger**: the open queue has drifted from what's actually built. **Skip** when you know one specific issue is done (`close` it) or one box just finished (`check` it), or when you're converting capture into tasks (`triage` — the forward direction; this skill is the reverse).

**This skill never closes anything.** It produces evidence-backed proposals and, on your confirmation, hands each one to `close` (which enforces summary-before-close). That separation is load-bearing: an agent that can both decide "this looks done" and retire the issue will eventually delete real work.

## Arguments

| `$ARGUMENTS` | Mode |
|---|---|
| (empty) | every `open` + `in_progress` bd, all manifest projects |
| `<project-slug>` (matches a manifest H2 or alias) | only bds labeled with that slug |
| `bd-<id>` (`bd-[a-z0-9]+`) | one issue, deep pass |
| `--boxes` | **tick-only sweep**: probe checkboxes, propose no closes or supersedes. Ignores `--stale` (defaults to the whole open queue) because an actively-worked plan is exactly the one whose boxes lag reality. Cheap and safe — the one to run weekly. |
| `--stale <duration>` | prefilter to bds whose `updated_at` is older than the duration (default `30d`; `--stale 0` disables). Applies to the issue-level pass only. |
| `--apply` | after the report, execute the approved buckets — still gated on one batch confirmation, and ticks are confirmed separately from closes |

Parse order: `bd-id` regex → manifest slug/alias lookup → flags. Flags compose with any mode.

## Evidence tiers

A **claim** is one thing that might be done: an issue, or a single `- [ ]` box. Every claim gets a tier, and the bar is the same either way. **Only `SHIPPED` and `SUPERSEDED` may be acted on** — a tick needs as much proof as a close, just over a narrower claim.

| Tier | Requires | Verdict on an issue | Verdict on a box |
|---|---|---|---|
| **SHIPPED** | A probe you actually ran at the project path came back positive: the named file/symbol/route/test exists, `git log --grep=<bd-id>` or `git log -S<symbol>` shows the commit, or the stated acceptance check passes. Quote the one-line result. | propose close | propose tick |
| **SUPERSEDED** | A `$AGENT_HOME/summary` (or another bd) describes this exact work under a different id **and** one codebase probe corroborates it. | propose `bd supersede` | propose tick with a `→ <where it landed>` note |
| **PARTIAL** | Some of the issue's boxes are SHIPPED, others aren't. | issue stays open | n/a — a box is atomic; it's SHIPPED or it isn't |
| **PLAUSIBLE** | Prose overlap only — a summary "sounds like" this claim, or the topic looks handled. No probe, or the probe was ambiguous. | Ask list | Ask list — **never tick** |
| **OPEN** | Probes ran, found nothing. | leave open (report only if `--stale` matched) | leave unticked, silently |
| **UNVERIFIABLE** | No manifest entry, repo missing from disk, or the claim isn't code (docs, decisions, ops, "think about X", "discuss with Zach"). | Ask list, labeled with the reason | leave unticked; list under Ask only if the issue is otherwise closeable |

**Absence of evidence is not evidence of completion.** A probe that finds nothing means OPEN, not done. The asymmetry runs the same way at both granularities: a wrongly-reopened issue costs a minute, a wrongly-closed one loses the work — and a falsely-ticked box poisons the one artifact a cold `attach` trusts.

## What this skill does (in order)

1. **Load the manifest** — `$AGENT_HOME/manifest.md` → `slug → {path, components[], aliases[]}` plus a reverse alias index. A bd whose labels resolve to no manifest path can never be code-verified; it goes straight to UNVERIFIABLE.
2. **Build the worklist** — `bd list -s open,in_progress --json`. Apply the project filter and `--stale` cutoff (`updated_at` older than the window). Report how many were filtered out, so a small worklist never reads as a clean queue.
3. **Cheap pass first (no repo reads).** For every bd in the worklist, in one batch:
   - `grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md` → a summary exists but the bd is open = **zombie**, the highest-confidence close candidate in the system. Still requires one corroborating probe before proposing.
   - locate the plan (`$AGENT_HOME/plan/<bd-id>-*.md`) and extract **every open `- [ ]` line with its line number** — that list is the box-level worklist.
   - `bd show <bd-id>` for comments and dependency links — a comment saying "shipped in PR-x" is a probe target, not proof.
   Anything the cheap pass resolves needs no repo work.
4. **Derive probes — per box first, then per issue.** Each open checkbox is its own claim; turn its text into 1–2 runnable checks against the project path. Then add 2–4 issue-level probes from the plan Goal / acceptance criteria / bd description for the "is the whole thing done" question. Good probes name a thing: `rg -n "WorkerPoolTerminateDeadline" libs/`, `test -f apps/ui/src/components/ExportDialog.vue`, `git log --oneline --since=<created_at> --grep=<bd-id>`, `git log -S"<new symbol>" --oneline`. Bad probes are vibes: "check if the dashboard feels done." A box whose text yields no nameable probe (`- [ ] decide on the retry policy`) is UNVERIFIABLE — don't invent a probe to force a verdict.
5. **Run the probes, read-only.** Never checkout, stash, pull, or write in a target repo. If the working tree is dirty or the checkout is on an unexpected branch, say so in the report — evidence from a dirty tree is still evidence, but the reader should know.
6. **Classify** every claim — each box and each issue — into a tier with its quoted evidence line. An issue is closeable only if its own probes are SHIPPED; "all boxes ticked" is corroboration, not a substitute (plans go stale, and a box list is rarely the full acceptance bar).
7. **Report** the buckets (below), boxes included. Nothing has been mutated yet.
8. **Confirm, then apply — ticks first.** Ticks and closes are confirmed separately, since ticking is cheap and correct far more often. On approval: `check` the SHIPPED boxes (see below), *then* `close <bd-id> "<resolution citing the evidence>"` per closeable issue (it writes the missing summary), and `bd supersede <bd-xxx> --with=<bd-yyy>` for supersedes. Ordering matters — a bd handed to `close` with stale boxes produces a summary that contradicts its own plan. Without `--apply`, stop after the report and let the user pick.

## Ticking boxes

Ticks go through `check`, not through a direct edit of the plan — `check` owns the matching, the `sessions:` frontmatter append, and the append-only guarantees, and reconcile should not grow a second implementation of them.

```
/bdx:check <bd-id> "<full checkbox text>" --note "<where it actually landed>" --quiet
```

- **Pass the full box text**, not a fragment. Reconcile already knows the exact line; fragments reintroduce the ambiguity `check` would then have to fail on. Multiple proven boxes on one bd can go in one comma-separated call — but only if every fragment is unambiguous, since `check` fails the whole call otherwise.
- **`--note` when the code diverged from the box.** The probe usually tells you how: `- [x] add /api/users endpoint → landed as /api/v2/users`. One line, append-only, same rules as `check`'s annotation contract. No note when the code matches what the box said.
- **`--quiet`**, then one rollup comment per bd: `bd comment <bd-id> "reconcile: ticked N box(es) from codebase evidence — <one-line list>"`. Per-box comments are right when a human ticks them one at a time; a sweep that fires twelve comments at once just buries the thread.
- **Never untick, never add, never reorder.** `[x] → [ ]` is out of scope even when a probe suggests the work was reverted — report that as a finding and let the user decide, because a reverted box usually means the *issue* needs reopening, not the plan needs editing.
- **Never touch a closed bd's plan.** Those are historical records now.

The tick bar is deliberately identical to the close bar. A box ticked on PLAUSIBLE evidence is worse than an unticked one: an unticked box costs a re-check, a falsely-ticked box means the next cold `attach` skips real work.

## Fan-out

Above ~8 bds, group the worklist by project and dispatch one **read-only** investigator subagent per project (they share a checkout and a mental model of the repo, so per-project beats per-issue). Hand each investigator the bds *and* their open checkbox lines verbatim. Each returns, per claim (issue or box, identified by bd-id + exact box text): tier, the probes it ran verbatim, the quoted result, and a one-line rationale — plus a divergence note where the code satisfies a box differently than written.

Investigators may not run `bd close`, `bd update`, `check`, or any write to `$AGENT_HOME` — they gather evidence and report. All mutation stays in the parent session (steps 1–3 and 6–8). At or below 8 bds, run inline; the subagent overhead isn't worth it.

## Report

```
Reconciled 23 bds (of 50 open — 27 filtered by --stale 30d) across 4 projects.
19 of 23 had plans; 71 open boxes probed.

TICK — boxes the code already satisfies (14 across 6 bds)
  bd-r3un  five9 list import                                              workflows
     [x] add batch chunking to the import path
         rg -n "chunkBy(" libs/five9/import.ts → L88
     [x] add /api/imports/status endpoint  → landed as /api/v2/imports/status
         git log -S"importsStatusHandler" → 4f1a09b "five9: import status route"
  bd-2ojr  package export dialog                                          workflows
     [x] build the export dialog component
         apps/ui/src/components/ExportDialog.vue exists

CLOSE — issue-level evidence (5)
  bd-9kl6  worker terminate deadline        workflows  SHIPPED   (+2 boxes ticked first)
           git log -S"terminateDeadlineMs" → a91f2c3 "worker: hard terminate deadline"

SUPERSEDE (2)
  bd-p3ux  dashboard filter casing          →  bd-77x   summary/dashboard-filter-casing--2026-05-02.md + rg confirms

PARTIAL — boxes ticked, issue stays open (3)
  bd-r3un  five9 list import                4 of 7 boxes proven; open: retry policy, backoff test, docs

ASK — can't decide alone (4)
  bd-w2cq  "revisit queue backpressure"          PLAUSIBLE     summary bd-1z7q covers backpressure, different queue
  bd-mml1  "write up licensing decision"         UNVERIFIABLE  not code — no probe exists
  bd-r3un  [ ] "decide on the retry policy"      UNVERIFIABLE  box states a decision, not an artifact

STILL OPEN — probed, found nothing (9)
  bd-ijpa, bd-j1y3, bd-ismw, ...
```

Keep it scannable: id, title, project, tier, and **the evidence line**. A verdict without a quoted probe result is a bug in the run, not a terse report. Under `--boxes`, print the TICK, ASK, and counts sections only — no close proposals at all, so the report stays a one-screen decision.

## Rules

- **Never `bd close`, never edit a plan directly.** Closes route through `close` (so a summary gets written first — a reconcile-driven close is exactly the case where the durable record is missing); ticks route through `check`.
- **No prose-only closes and no prose-only ticks.** A summary that describes the work is a lead; the probe is the proof. PLAUSIBLE goes to Ask, always, at both granularities.
- **Ticking is not closing.** A fully-ticked plan does not by itself close its issue — probe the issue on its own terms. Plans routinely omit the last mile (docs, migration, rollout).
- **Read-only in every target repo.** No checkout, pull, stash, install, or build that writes. Running an existing test command is fine when it's cheap and the plan named it as the acceptance check.
- **One round.** Reconcile does not loop until the queue is empty. Unresolved items stay open and come up next run.
- **Don't refile.** Follow-ups discovered mid-reconcile get reported, not created. Agent-generated backlog is the noise this skill is supposed to remove, not add.
- **Don't rewrite plans.** Ticks go through `check`; prose, structure, and box ordering are untouched. Never add a box, never untick one.
- **State the filter.** Always print how many bds `--stale` and the project filter excluded. A report that reads "3 stale issues" when 47 weren't looked at is a lie by omission.
- **A missing repo is UNVERIFIABLE, not OPEN.** If the manifest path doesn't exist on disk, say the path is missing — that's a manifest bug worth surfacing (`manifest` fixes it).

## Process

1. Parse `$ARGUMENTS` (bd-id → single deep pass; slug/alias → project filter; `--boxes` → tick-only, ignore `--stale`; `--stale`, default `30d`; `--apply`).
2. **Single batched message**: read `$AGENT_HOME/manifest.md`, run `bd list -s open,in_progress --json`, and `ls $AGENT_HOME/summary $AGENT_HOME/plan`.
3. Apply filters; if the worklist is empty, print "Nothing to reconcile" plus the filter counts and stop.
4. Cheap pass — zombie grep, plan lookup, **extract every open `- [ ]` line per plan**, `bd show` for each bd, batched.
5. Derive probes: 1–2 per open checkbox (skip boxes that name no artifact → UNVERIFIABLE), plus 2–4 issue-level probes per bd unless `--boxes`.
6. Run probes: inline if ≤8 bds, else one read-only investigator subagent per project group.
7. Classify every claim into a tier; assemble the buckets with quoted evidence.
8. Print the report. Stop here unless `--apply`.
9. On `--apply` (or the user picking from the report): confirm ticks and closes as **two separate batches**, then run `check` for approved boxes (one call per bd, `--quiet`, plus a rollup `bd comment`), then `close` / `bd supersede` for approved issues. Report what was executed, one line each.
