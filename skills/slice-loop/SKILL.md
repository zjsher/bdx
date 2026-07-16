---
name: slice-loop
description: Autonomously execute a plan by orchestrating worker subagents that each run a quota of slice -> slice-review iterations, with a mechanism-level quality-audit checkpoint (persona lens, auto or random) at every worker handoff, until a caller-specified goal is met ("until phase 5-6 complete", "until the plan is done", a bd-id's remaining boxes). Use when the user wants a plan executed without per-slice approval but with the full slice audit trail — "slice-loop until X", "loop slices on this plan", "run the rest of the plan with slices", "autonomously finish phase N". Not for decision-dense or unsettled-design work — this skill halts back to the human when it hits those.
user-invocable: true
argument-hint: <goal: "until phase 5-6 complete" | bd-id | plan path> [--max N] [--quota N] [--model <tier>] [--route] [--persona auto|random|<slug>] [--ultra] [--context-cap PCT] [--window TOKENS]
---

# slice-loop

Execute a plan as an **orchestrated converge loop**: a lean parent (this session) spawns one worker subagent at a time; each worker runs a fixed quota of slice -> slice-review iterations, then retires at a planned seam where the parent runs a **mechanism-level audit** — the one review class the slice/slice-review pairing deliberately filters out. Repeat until the caller's goal is met, a halt trigger routes to the human, or the bound trips.

Why two tiers: implementation burns context (file reads, test output, diffs), and a degraded implementer builds bad slices. Workers retire fresh at ~3 slices, nowhere near any window; the parent accumulates only structured reports, so total run length is not bounded by one context. Cold handoff costs almost nothing because the loop's state is durable by construction — ticked plan boxes, decision-ledger rows, per-slice bd comments, the self-check ratchet. (This is the plan-execution analogue of crash-resume: incarnations die, the fact log survives, the successor resumes at the frontier.)

## What this trades away (say it in the launch summary)

`slice` exists to keep the human's judgment visible between increments; this skill removes that per-slice approval gate and replaces it with an audit trail reviewable after the fact, built by workers you never watched. It is the right tool when the mechanism is settled and the remaining boxes are execution; it is the wrong tool when boxes still hide design decisions — which is why the halt triggers are generous and firing one is the system working, not failing.

## Arguments

Parse `$ARGUMENTS`:

- **Goal** (everything that isn't a flag): what "done" means. A phase range ("until phase 5-6 complete"), a bd-id (remaining unchecked boxes in its plan), a plan path, or a free-form condition. Empty goal + a resolvable attached task -> the plan's remaining boxes.
- `--max N` — hard bound on total slices across all workers (default **8**). Hitting it stops loudly; never silently continue.
- `--quota N` — slices per worker incarnation (default **3**). The quota seam IS the audit checkpoint, so this is also the audit cadence.
- `--persona auto|random|<slug>` — checkpoint audit lens (default **auto**).
- `--ultra` — upgrade checkpoint audits from `quality-audit` light to ultra, for high-stakes runs where audit cost is acceptable.
- `--model <fable|opus|sonnet|haiku>` — base tier all workers run at (default: **inherit the session model**). The simple cost control: pin workers to e.g. `opus` and leave everything else alone. See *Model routing* for the escalation rules that apply regardless.
- `--route` — opt-in dynamic routing: the parent grades each upcoming chunk and promotes non-mechanical ones from the base tier to the session model. Off by default.
- `--context-cap PCT` / `--window TOKENS` — the H7 backstop threshold (default **70**% of a **1M** window; `CLAUDE_CONTEXT_WINDOW` also sets the window). A backstop, not the mechanism — quotas are what keep context fresh.

## Step 0 — Resolve the goal (parent, once)

1. Find the plan: `bd show <id>` if a bd-id was given; else the stated path; else grep `$AGENT_HOME/plan/` for the current task. No plan file -> STOP; this skill executes plans, it does not write them (`bdx:plan` does).
2. Restate the goal as a condition a machine can check — almost always "every `- [ ]` box in <sections> is ticked." If the goal cannot be made checkable, STOP and ask the user to sharpen it: an unverifiable loop is unattended mistakes at scale.
3. **Pre-flight gate — scan the in-scope boxes for unsettled decisions before spawning anything.** A box that names an open design question ("design question to settle first", an unresolved `Open questions` dependency) means the region is not executable yet. Surface those NOW; shrink the goal around them or stop. No worker tier fixes building on an unmade decision.
4. Note the phase boundaries in scope (`###` sections containing in-scope boxes) — crossing one mid-quota still triggers a checkpoint at that worker's retirement.
5. Emit the launch summary:

```
slice-loop: <goal restated>
Done when   <checkable condition>
Bound       <N> slices max · <quota> per worker
Workers     <base tier> (<inherited | --model> · routing <on|off>)
Checkpoint  quality-audit <light|ultra> · persona <mode> · at every worker handoff
Plan        <path> · <M> boxes in scope
Trades away per-slice approval for an after-the-fact audit trail.
```

## The orchestration (parent duties)

The parent never reads implementation files, diffs, or test output — workers summarize, the parent stays lean. One worker at a time, **never parallel**: slices are sequential by design; each extends the spine the last one built. Per cycle:

1. **Spawn a worker** (general-purpose subagent, `run_in_background: false`) with the *Worker contract* below: plan path, the next in-scope boxes, quota, and standing rules. Set the Agent tool's `model` per *Model routing*.
2. **Receive its report.** Post one `bd comment` per slice the worker landed (its report carries them pre-formatted) so `bd show <id>` stays a live dashboard even though the work happened out of view.
3. **Route the outcome:**
   - **Quota complete / phase boundary reached** -> run the *Checkpoint audit*, then spawn the successor with the audit's verdict noted in its boot context.
   - **Goal met** -> final checkpoint audit, then the final report.
   - **Any H1–H6 halt** -> to the human, always. The parent's authority is succession, nothing else — responding to "consequential divergence" or "audit challenged the mechanism" by spawning a fresh worker to push through would automate away exactly the judgment this design reserves for the human.
   - **Worker died** (task failure, no report) -> at most the in-flight slice is lost; check `git status` + the plan for what actually landed, post a bd comment recording the death, and spawn a successor pointed at the frontier. Two consecutive deaths on the same slice -> halt to the human (the slice itself is likely the problem).
4. **Self-check (parent's own H7):** before each spawn, run `scripts/context-tokens.sh <cap_pct> [window]`. Exit 1 -> clean halt: `bdx:dump` (the parent is the human session — the session-UUID machinery only works here), then tell the user the exact re-invocation (`/slice-loop <same goal>` — Step 0 re-derives the frontier from the plan itself). This is rare by construction: on a report-only diet the parent outlasts any plausible `--max`. For runs that must outlive every session unattended, the parent's parent is a *dumb* outer driver — `while` not-done `do claude -p "/slice-loop <goal>" done` (the Ralph-loop pattern); each invocation boots a fresh parent that re-derives the frontier. Each supervision layer up should be dumber and more reliable than the one below: steps < worker < parent < shell loop < human.

## Worker contract (what each subagent is told)

Boot: read the plan file (goal section + in-scope boxes + decision log tail), `.claude/self-check.md` if present, and the last ~5 bd comments on the task. That is the whole inheritance — everything a successor needs is durable, by design.

Then iterate, up to quota:

1. **Slice.** Invoke the `slice` skill for the next in-scope box (or the fix demanded by step 2). Its full contract binds — executable pass/fail verification, anti-gold-plating, the card, the ledger row appended to the plan's decision log. Override: its HALT returns control to this worker's loop, not to a human.
2. **Review.** Invoke `slice-review` on what landed. Contract unchanged: scope gate, concrete failure scenarios, CONFIRMED/PLAUSIBLE, empty-is-PASS, one round, self-check ratchet. CONFIRMED -> one fix pass via `slice`; re-review only if the fix was structural; new CONFIRMED on re-review -> halt H3.
3. **Tick** the completed box(es) via `bdx:check`, with a `DIVERGENCE:` annotation when trivial (see grading below); consequential divergence -> halt H1 instead.
4. **Check halts** (H1–H6 below, plus the H7 backstop) and quota. Quota done, goal met, or halt -> write the report and return.

**Report** (the worker's final message — structured, no prose padding):

```
status      quota-complete | goal-met | died-<detail> | H<n>: <one line>
slices      <n>: <title — boxes ticked — review PASS | k confirmed fixed> (one line each)
bd          <ids created for PLAUSIBLE/out-of-scope/advisory findings>
divergence  <trivial annotations made · or none>
files       <paths touched — the parent scopes the checkpoint audit with this>
inflight    <ONLY if halted mid-slice: head-state — what's half-landed, what the next action was, why stopped>
```

**No `bdx:dump` on planned retirement** — a quota retirement has nothing to say that isn't already in the plan, the ledger, and this report; dumps are for humans re-entering cold, and a per-worker dump would bury `$AGENT_HOME/context/` in files nobody reloads. On an *unplanned* halt with in-flight work, the worker instead embeds head-state in `inflight` AND posts it as a `bd comment` (durable even if the parent dies too); if the halt goes to the human, the **parent** runs the single `bdx:dump`.

Workers also carry the standing rules: no git mutations ever; formatters scoped to their own changed files; memory-efficiency conventions of the repo's CLAUDE.md bind as usual.

## Model routing (which tier each worker runs at)

One subtlety governs everything here: **the worker is both the implementer and the defect gate** — slice-review runs inside the same worker, at the same tier. Downgrading a worker doesn't just buy a cheaper generator; it buys a cheaper reviewer judging that generator's work, and the failure mode is plausible-but-wrong code blessed by its own tier — the false-green pattern. The rules below exist to cap that risk.

- **Base tier:** `--model` if given, else inherit the session model. Without `--route`, every worker runs at base tier — the caller pinned it, the parent doesn't second-guess it.
- **`--route` (opt-in):** before each spawn, the parent grades the upcoming chunk's boxes. **Mechanical** — docs, config plumbing, test boilerplate for an already-proven mechanism, UI wiring on an established pattern -> base tier. **Non-mechanical** — anything touching engine semantics, concurrency, correctness-critical paths, or a box with design language in it -> promote to the session model. When unsure, promote — "the box looks simple" is a weak signal; simple-looking boxes have a documented history of taking three attempts.
- **Escalation (always active, both flags or neither):** if the previous cycle had any CONFIRMED finding, a worker death, an audit finding above advisory, or a divergence annotation, the next worker is forced to the session model regardless of base tier. A base-tier worker halting H2/H3 gets ONE retry at the session model before the halt routes to the human — a cheap model failing is a routing signal first, a human-decision signal second. De-escalation back to base happens only after a fully clean cycle (all PASS, no annotations).
- **The audit never downgrades.** The checkpoint reviewer runs at the session model always — it is the safety net specifically because worker tiers vary.
- Record the tier per worker in the final report's `Workers` line and in each iteration's bd comment, so a later "why is this slice weak" question has an answer.

## Checkpoint audit (parent, at every worker handoff)

`slice-review` is constrained to provable defects in the diff — its scope gate *explicitly excludes* architecture opinions; that filter is what makes one round terminate. The checkpoint restores what the filter removes, at seams cheap enough to redirect: a fresh-context reviewer allowed to say "this mechanism is wrong" every ~quota slices, not fifteen slices too late. Running it in the parent is also what makes it possible at all — subagents can't spawn subagents, so a worker could never launch `quality-audit`'s clean reviewer.

- **Run:** invoke `quality-audit` (light unless `--ultra`) scoped to the retiring worker's `files` list. Its context-hygiene rules bind — the reviewer gets paths + diff pointers, never the workers' narrative or this session's rationale.
- **Persona lens:** pick from `$AGENT_HOME/personas/`: `auto` (default) reads each persona's `description:` and picks the best match for what the slices touched; `random` picks uniformly excluding personas already used this run; `<slug>` fixes the lens. Voice is a lens, not a lowered bar — a persona opinion still needs a concrete defect or a named structural consequence. Empty personas dir -> lens-less, noted.
- **Routing:** CRITICAL or any finding challenging a mechanism the remaining plan builds on -> halt H4, to the human. Confirmed and locally fixable -> first task of the successor worker (counts against `--max`). Advisory -> `bd create`, continue.

## Halt triggers (generous by design — firing one is the loop working)

Workers detect H1–H3 and H6; the parent detects H4, H5, and its own H7; either may hit H2. Every halt that reaches the human gets: the reason first, options framed as plain tradeoffs (what each costs and buys for the product, jargon glossed), a durable `bd comment` (+ `--status blocked` if the user may be away), and one parent-side `bdx:dump` when in-flight state exists.

- **H1 — consequential divergence.** A box's instruction doesn't survive contact with the code, consequentially (below).
- **H2 — blocked slice.** Verification failed unrecoverably within the slice, missing input, or a mid-slice decision the worker can't make with high confidence.
- **H3 — slice too big to review.** Re-review after a structural fix surfaces new CONFIRMED defects. The human decides how to re-cut; the loop doesn't add rounds.
- **H4 — audit mechanism challenge.** Checkpoint audit produced a CRITICAL or architecture-level finding.
- **H5 — bound.** `--max` total slices landed without meeting the goal. Report what's green, what's left, why progress stalled.
- **H6 — defect-dense region.** Two consecutive slices each needed a CONFIRMED-fix pass. Per-slice human review (plain `/slice` + `/slice-review`) is the better tool from here — say so.
- **H7 — context backstop.** Quotas make this rare by design. Parent: checked before every spawn via `scripts/context-tokens.sh` (reads the session transcript's latest usage record; exit 1 = over `--context-cap`; exit 2 = can't measure -> fall back to the qualitative check: compaction observed, or recall of the run degrading). Worker: if mid-quota it notices compaction or serious recall degradation, finish the current slice if close, else stop honestly — report `inflight`, never push a degraded implementation through to quota.

## Divergence grading (H1's threshold)

Plans meet reality; not every mismatch should stop the world.

- **Trivial** — implementation detail with no product consequence: different helper name, a simpler equivalent mechanism, the box's example not matching the real API shape. -> Annotate the ticked box (`DIVERGENCE: <one line>`), ledger row, continue.
- **Consequential** — the user would want to weigh it: observable behavior changes, a stated mechanism replaced or killed, a contract/signature other boxes depend on moves, a safety/cost/perf property traded, a later in-scope box invalidated. -> **H1.**

When genuinely unsure which side, it is consequential. The known failure mode of autonomous plan execution is self-approving exactly these calls — and a worker self-approving is invisible in a way an interactive session never was.

## Final report (parent)

End every run — success, bound, or halt — with:

```
slice-loop: <stopped because — goal met | bound | H<n> reason>

  Workers    <n> incarnations (<quota> quota) · tiers <base×k, escalated×j> · <deaths, if any>
  Slices     <n> landed: <titles, comma-run>
  Reviews    <n> PASS · <n> confirmed-fixed · <bd-ids backlogged>
  Audits     <n> run (<personas>) · <verdict summary>
  Plan       <boxes ticked>/<in scope> · <phases completed>
  Ledger     <n> rows · <n> divergences annotated
```

Then 1-3 plain-prose sentences: what the human should do now (review the diff phase by phase, decide the halted question, re-invoke `/slice-loop` for the remainder, or drop to manual `/slice`). If halted on a decision, the options and their tradeoffs go here.

## Standing rules that bind everywhere

- **No git mutations** — no commit/push/branch/stash, parent or worker, unless the user explicitly authorized it for this run.
- All `slice` and `slice-review` internal rules bind except their halt-to-human, which this loop owns and routes. The self-check ratchet (`.claude/self-check.md`) compounds across workers — half the reason succession works.
- Durable learnings graduate to `bd remember` / repo `CLAUDE.md`; the plan's decision log is the per-task record, not the cross-task one.
