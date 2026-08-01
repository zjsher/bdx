---
name: slice-loop
description: >-
  Autonomously execute a plan by orchestrating worker subagents that each run a quota of slice -> slice-review iterations, with a mechanism-level quality-audit checkpoint at every worker handoff, until a caller-specified goal is met ("until phase 5-6 complete", "until the plan is done", a bd-id's remaining boxes). Use when the user wants a plan executed without per-slice approval but with the full slice audit trail — "slice-loop until X", "loop slices on this plan", "run the rest of the plan with slices", "autonomously finish phase N". Not for decision-dense or unsettled-design work — this skill halts back to the human when it hits those.
user-invocable: true
argument-hint: '<goal: "until phase 5-6 complete" | bd-id | plan path> [--fast] [--max N] [--quota N] [--audit-every N] [--model <tier>] [--audit-model <tier>] [--escalate-model <tier>] [--ultra]'
---

## Codex host execution (mandatory)

When the harness is Codex, invoke every shell tool call that runs `bd` with `sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set `prefix_rule: ["bd"]`. The installed allow rule only pre-approves escalation—it does not move a default call outside the workspace sandbox. This applies to read-only commands too. If a sandboxed call reports a Dolt connection failure, retry at host level before diagnosing Dolt as down; wrappers inherit the sandbox. Claude Code and other non-Codex harnesses must ignore this section and use their normal execution path.

# slice-loop

Execute a plan as an **orchestrated converge loop**: a lean parent (this session) spawns one worker subagent at a time; each worker runs a fixed quota of slice -> slice-review iterations, then retires at a planned seam where the parent runs a **mechanism-level audit** — the one review class the slice/slice-review pairing deliberately filters out. Repeat until the caller's goal is met, a halt trigger routes to the human, or the bound trips.

Why two tiers: implementation burns context (file reads, test output, diffs), and a degraded implementer builds bad slices. Workers retire fresh at ~3 slices, nowhere near any window; the parent accumulates only structured reports, so total run length is not bounded by one context. Cold handoff costs almost nothing because the loop's state is durable by construction — ticked plan boxes, decision-ledger rows, per-slice bd comments, the self-check ratchet. (This is the plan-execution analogue of crash-resume: incarnations die, the fact log survives, the successor resumes at the frontier.)

## What this trades away (say it in the launch summary)

`slice` exists to keep the human's judgment visible between increments; this skill removes that per-slice approval gate and replaces it with an audit trail reviewable after the fact, built by workers you never watched. It is the right tool when the mechanism is settled and the remaining boxes are execution; it is the wrong tool when boxes still hide design decisions — which is why the halt triggers are generous and firing one is the system working, not failing.

## Arguments

Parse `$ARGUMENTS`:

- **Goal** (everything that isn't a flag): what "done" means. A phase range ("until phase 5-6 complete"), a bd-id (remaining unchecked boxes in its plan), a plan path, or a free-form condition. Empty goal + a resolvable attached task -> the plan's remaining boxes.
- `--fast` — preset for settled, mechanical stretches. See *Fast mode*. Expands to a flag set that is printed in the launch summary; anything you pass explicitly wins over the preset.
- `--max N` — hard bound on total slices across all workers (default **8**). Hitting it stops loudly; never silently continue.
- `--quota N` — slices per worker incarnation (default **3**). Governs worker context freshness — nothing else.
- `--audit-every N` — run the checkpoint audit at every Nth worker handoff instead of every one (default **1**). The audit is the loop's only unbiased reviewer, so raising this is the one setting that trades away real coverage; see *Checkpoint audit*.
- `--ultra` — upgrade checkpoint audits from `quality-audit` light to ultra, for high-stakes runs where audit cost is acceptable.
- `--model <fable|opus|sonnet|haiku>` — base tier all workers run at (default: **inherit the session model**). The simple cost control: pin workers to e.g. `sonnet` and leave everything else alone.
- `--audit-model <fable|opus|sonnet|haiku>` — tier the checkpoint audit reviewer runs at (default: **inherit the session model**). No floor: this may be set below `--model`, which turns off the false-green guard — see *Model routing*.
- `--escalate-model <fable|opus|sonnet|haiku>` — tier that escalation bumps *up* to (default: **inherit the session model**). Set it equal to `--model` to make the loop never leave the base tier.

Tier order is `haiku < sonnet < opus < fable`. The H7 context backstop fires at **70%** of a **1M** window; set `CLAUDE_CONTEXT_WINDOW` if the window differs. It is a backstop, not the mechanism — quotas are what keep context fresh.

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
Workers     <base tier> (<inherited | --model> · escalates to <escalation tier>)
Checkpoint  quality-audit <light|ultra> · <audit tier> · every <N> handoff(s)
Plan        <path> · <M> boxes in scope
Trades away per-slice approval for an after-the-fact audit trail.
```

With `--fast`, add a line naming the preset and the flags it expanded to, so the run is reproducible without it:

```
Fast        --model sonnet --escalate-model opus --audit-model opus --quota 4 --audit-every 2
            (explicit flags override; clean handoffs only are skipped)
```

**Tier-guard warning.** Rank tiers `haiku < sonnet < opus < fable` (`fable` is the top tier). Fire the warning when the audit tier is ranked **strictly below** the base worker tier. Append it to the launch summary and repeat it in the final report:

```
⚠ Audit tier (<audit>) is below worker tier (<base>) —
  false-green guard OFF. The reviewer is weaker than the
  code it judges; expect confident-looking slices to pass.
```

Equal tiers do **not** warn — that is the default (both inherit the session model), and at parity the checkpoint still earns its keep on fresh context and mechanism-level scope rather than on being smarter than the worker. The warning is specifically for the inverted case: a reviewer graded below the generator it audits.

Warn, don't block: the caller sets the tiers, the loop just refuses to be quiet about a run whose safety net is inverted.

## The orchestration (parent duties)

The parent never reads implementation files, diffs, or test output — workers summarize, the parent stays lean. One worker at a time, **never parallel**: slices are sequential by design; each extends the spine the last one built. Per cycle:

1. **Spawn a worker** (general-purpose subagent, `run_in_background: false`) with the *Worker contract* below: plan path, the next in-scope boxes, quota, and standing rules. Set the Agent tool's `model` per *Model routing*.
2. **Receive its report.** Post one `bd comment` per slice the worker landed (its report carries them pre-formatted) so `bd show <id>` stays a live dashboard even though the work happened out of view.
3. **Route the outcome:**
   - **Quota complete / phase boundary reached** -> run the *Checkpoint audit*, then spawn the successor with the audit's verdict noted in its boot context.
   - **Goal met** -> final checkpoint audit, then the final report.
   - **Any H1–H6 halt** -> to the human, always. The parent's authority is succession, nothing else — responding to "consequential divergence" or "audit challenged the mechanism" by spawning a fresh worker to push through would automate away exactly the judgment this design reserves for the human.
   - **Worker died** (task failure, no report) -> at most the in-flight slice is lost; check `git status` + the plan for what actually landed, post a bd comment recording the death, and spawn a successor pointed at the frontier. Two consecutive deaths on the same slice -> halt to the human (the slice itself is likely the problem).
4. **Self-check (parent's own H7):** before each spawn, run `scripts/context-tokens.sh` (its defaults are the 70% cap and a 1M window; `CLAUDE_CONTEXT_WINDOW` overrides the latter). Exit 1 -> clean halt: `bdx:dump` (the parent is the human session — the session-UUID machinery only works here), then tell the user the exact re-invocation (`/slice-loop <same goal>` — Step 0 re-derives the frontier from the plan itself). This is rare by construction: on a report-only diet the parent outlasts any plausible `--max`. For runs that must outlive every session unattended, the parent's parent is a *dumb* outer driver — `while` not-done `do claude -p "/slice-loop <goal>" done` (the Ralph-loop pattern); each invocation boots a fresh parent that re-derives the frontier. Each supervision layer up should be dumber and more reliable than the one below: steps < worker < parent < shell loop < human.

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

## What actually gates a slice

The loop has three checks on every slice, and they are **not** equally trustworthy. Ranking them honestly is what keeps the run from believing its own press:

1. **The executable check — this is the gate.** `slice` requires a pass/fail check that was *observed failing* before it counted: break the thing it names, watch it go red, restore. That "prove it can fail" step is the whole ballgame. It is the only signal in the loop that comes from outside the model's own judgment — the code either ran and failed or it didn't. A slice without one has not been verified, no matter how confident the narration.
2. **The checkpoint audit — the real review.** Fresh context, separate agent, never saw the worker's reasoning. Its independence is what gives it standing to say "this mechanism is wrong."
3. **In-worker `slice-review` — a smoke test, not a gate.** It runs inside the worker that just wrote the code, at that worker's tier. A model reviewing its own output favors that output; a PASS here is weak evidence of health, not a clean bill. It is worth running — it catches the careless mistakes cheaply, and a CONFIRMED finding from it is a real finding — but its *silence* proves nothing.

The asymmetry that follows: **a finding is informative, an absence is not.** Trust `slice-review` when it says "here is a defect." Do not read "no findings" as "the code is good" — route that question to the executable check and the audit, which are the two checks with outside standing.

This is also why escalation is scoped the way it is below. Raising a self-reviewing worker's tier buys a smarter reviewer with the same blind spot for its own work; it does not convert a smoke test into a gate. Escalation exists because a *cycle that showed trouble* signals a region is harder than the plan implied — not because a bigger model can self-review its way to correctness.

## Model routing (which tier each worker runs at)

Tier choices matter less than what the loop *trusts*, so read *What actually gates a slice* first — it explains why raising a worker's tier does not make its self-review trustworthy, and therefore why the audit tier is the one worth spending on.

Every tier is caller-settable and none has a floor. The three roles resolve independently:

| Role | Flag | Default |
| --- | --- | --- |
| Worker (implementer + inline slice-review) | `--model` | session model |
| Checkpoint audit reviewer | `--audit-model` | session model |
| Promotion / escalation target | `--escalate-model` | session model |

- **Base tier:** `--model` if given, else inherit the session model. Every worker runs at base tier until a cycle gives the loop a reason to think otherwise — the caller pinned it, the parent doesn't second-guess it.
- **Escalation is reactive, never predictive.** If the previous cycle had any CONFIRMED finding, a worker death, an audit finding above advisory, or a divergence annotation, the next worker is forced to the escalation tier regardless of base tier. A base-tier worker halting H2/H3 gets ONE retry at the escalation tier before the halt routes to the human — a cheap model failing is a routing signal first, a human-decision signal second. De-escalation back to base happens only after a fully clean cycle (all PASS, no annotations). When the escalation tier is not above the base tier, escalation is a no-op — skip the retry and route H2/H3 straight to the human rather than re-running the same tier and calling it an escalation.
- **The audit tier is a choice, not a guarantee.** It defaults to the session model. At or above the worker tier it does its job — at parity the leverage is fresh context and mechanism-level scope, above parity it adds capability the worker didn't have. Set it *below* the worker tier and the net inverts: a reviewer graded under the generator cannot be relied on to catch that generator's characteristic mistakes, and the run emits the tier-guard warning. That downgrade is legitimate for genuinely mechanical stretches (docs, config plumbing, boilerplate on a proven mechanism) where the audit is a formality; it is reckless anywhere the plan's mechanism is still load-bearing.
- Record all three tiers in the final report's `Workers` and `Audits` lines, and the worker tier in each iteration's bd comment, so a later "why is this slice weak" question has an answer.

## Fast mode (`--fast`)

Runs feel slow because every worker is sized for the hardest box in the plan, even while grinding through boxes that are pure execution. `--fast` fixes that and nothing else. It is a preset, not a mechanism:

```
--model sonnet  --escalate-model opus  --audit-model opus  --quota 4
```

Anything you pass explicitly beats the preset (`--fast --model haiku` gives haiku workers). Print the expansion in the launch summary — a preset that hides what it set is a preset you can't debug.

Why this set. The expensive thinking on a bdx task already happened *upstream*, in the plan: `bdx:plan` settled the mechanism at full tier before the loop ever started. Workers execute against that settled plan, which is the role that tolerates a cheaper model — the design work isn't being redone at `sonnet`, it's being carried out. Escalation still reaches `opus`, so the moment a cycle shows trouble the loop buys back the capability it gave up, and the reviewer stays on `opus` so the audit keeps its standing over the code it judges.

**What `--fast` deliberately does not touch: the audit cadence.** Speeding up by auditing less is the tempting move and the wrong one — per *What actually gates a slice*, the checkpoint is the loop's only unbiased reviewer, and thinning it removes the one check that isn't grading its own homework. Buy speed from tiers, where the evidence is strong; don't buy it by removing the reviewer. `--audit-every` is available if you insist, but it is not part of the preset.

**When it's the wrong tool.** `--fast` rests entirely on the plan having done the design work. A thin, hand-waved, or half-settled plan means the mechanism gets decided *in the slices* — by the cheap workers, at the tier you chose for execution. No reviewer tier rescues that. Boxes still hiding design decisions -> the pre-flight gate should stop you before tier choices matter at all.

## Checkpoint audit (parent, at every worker handoff)

`slice-review` is constrained to provable defects in the diff — its scope gate *explicitly excludes* architecture opinions; that filter is what makes one round terminate. The checkpoint restores what the filter removes, at seams cheap enough to redirect: a fresh-context reviewer allowed to say "this mechanism is wrong" every ~quota slices, not fifteen slices too late. Running it in the parent is also what makes it possible at all — subagents can't spawn subagents, so a worker could never launch `quality-audit`'s clean reviewer.

- **Run:** invoke `quality-audit` (light unless `--ultra`) scoped to the retiring worker's `files` list, at the audit tier (`--audit-model`, else the session model). Its context-hygiene rules bind — the reviewer gets paths + diff pointers, never the workers' narrative or this session's rationale.
- **Never `--inline`.** `quality-audit` offers an inline mode that skips the subagent, and it is not available here at any speed setting: inline runs the audit *in the invoking session*, which is the parent, whose whole design is a report-only diet. An inline audit would make the parent read implementation code, blow the context that makes long runs possible, and pull H7 forward. The audit subagent's cold re-read is the cost of the guarantee — the only negotiable part is how often it happens.
- **Cadence (`--audit-every N`, default 1).** Quota governs worker freshness; this governs audit frequency. They were one knob and are now two, because fusing them forced a false trade — the only way to buy fewer audits was to raise quota and degrade the implementer, which is what quotas exist to prevent.

  Raising `N` is the one setting in this skill that removes real coverage, so it defaults to 1 and `--fast` leaves it there. A handoff is **never skippable** if the retiring cycle produced evidence: a CONFIRMED finding, a divergence annotation, a worker death, or an escalation in effect. Phase boundaries and the final handoff always audit, so no phase closes and no run ends unaudited.

  Note what is deliberately *absent* from that list: "all reviews PASSed." Skipping the audit because in-worker review found nothing would gate the loop's only unbiased reviewer on the silence of its biased one — and per *What actually gates a slice*, that silence is exactly the false-green the audit exists to catch. A clean cycle is not evidence of health; it is an absence of evidence, which is why `N > 1` is a plain time-based dilution rather than a smart one. At `--audit-every 2` a clean 8-slice run drops from ~3 audits to ~2, and a mechanism defect can ride roughly twice as long before independent eyes see it. Set it knowing that's the trade.
- **No persona lens.** Earlier versions dressed the audit in a voice from `$AGENT_HOME/personas/`. It's gone: a reviewer's standing here comes from fresh context and a concrete defect, and asking it to also be somebody was decoration that made the report read sharper without making it find more. `bdx:persona` is still the right tool when you *want* an opinion in a voice — that's a different job from a checkpoint gate.
- **Routing:** CRITICAL or any finding challenging a mechanism the remaining plan builds on -> halt H4, to the human. Confirmed and locally fixable -> first task of the successor worker (counts against `--max`). Advisory -> `bd create`, continue.

## Halt triggers (generous by design — firing one is the loop working)

Workers detect H1–H3 and H6; the parent detects H4, H5, and its own H7; either may hit H2. Every halt that reaches the human gets: the reason first, options framed as plain tradeoffs (what each costs and buys for the product, jargon glossed), a durable `bd comment` (+ `--status blocked` if the user may be away), and one parent-side `bdx:dump` when in-flight state exists.

- **H1 — consequential divergence.** A box's instruction doesn't survive contact with the code, consequentially (below).
- **H2 — blocked slice.** Verification failed unrecoverably within the slice, missing input, or a mid-slice decision the worker can't make with high confidence.
- **H3 — slice too big to review.** Re-review after a structural fix surfaces new CONFIRMED defects. The human decides how to re-cut; the loop doesn't add rounds.
- **H4 — audit mechanism challenge.** Checkpoint audit produced a CRITICAL or architecture-level finding.
- **H5 — bound.** `--max` total slices landed without meeting the goal. Report what's green, what's left, why progress stalled.
- **H6 — defect-dense region.** Two consecutive slices each needed a CONFIRMED-fix pass. Per-slice human review (plain `/slice` + `/slice-review`) is the better tool from here — say so.
- **H7 — context backstop.** Quotas make this rare by design. Parent: checked before every spawn via `scripts/context-tokens.sh` (reads the session transcript's latest usage record; exit 1 = over the 70% cap; exit 2 = can't measure -> fall back to the qualitative check: compaction observed, or recall of the run degrading). Worker: if mid-quota it notices compaction or serious recall degradation, finish the current slice if close, else stop honestly — report `inflight`, never push a degraded implementation through to quota.

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
  Audits     <n> run · <audit tier> · <n> skipped (cadence <N>) · <verdict summary>
  Plan       <boxes ticked>/<in scope> · <phases completed>
  Ledger     <n> rows · <n> divergences annotated
```

Repeat the tier-guard warning here if it fired at launch — a report read three weeks later should say the net was down without the reader having to reconstruct the flags.

Then 1-3 plain-prose sentences: what the human should do now (review the diff phase by phase, decide the halted question, re-invoke `/slice-loop` for the remainder, or drop to manual `/slice`). If halted on a decision, the options and their tradeoffs go here.

## Standing rules that bind everywhere

- **No git mutations** — no commit/push/branch/stash, parent or worker, unless the user explicitly authorized it for this run.
- All `slice` and `slice-review` internal rules bind except their halt-to-human, which this loop owns and routes. The self-check ratchet (`.claude/self-check.md`) compounds across workers — half the reason succession works.
- Durable learnings graduate to `bd remember` / repo `CLAUDE.md`; the plan's decision log is the per-task record, not the cross-task one.
