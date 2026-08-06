---
name: build-loop
description: >-
  Implement ordinary planned feature work through a lightweight autonomous loop:
  settle the design, keep one implementer in context, run tight executable checks
  after each coherent behavior, persist progress only at meaningful milestones, and
  run one fresh review at the goal boundary. Use by default for "build this feature,"
  "finish this plan," or "keep implementing" when the design is settled and
  verification is strong. Route auth, tenancy, money, deletion, migrations,
  recovery/concurrency, weak test oracles, and per-increment audit requirements to
  slice-loop.
---

# build-loop

Build a planned feature quickly without giving up its durable record. Keep the inner
loop tight; pay the plan, Beads, and review costs only where they change a future
decision.

## Codex host execution (mandatory)

When the harness is Codex, run every shell tool call containing `bd` with
`sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set
`prefix_rule: ["bd"]`. Treat a sandboxed Dolt connection failure as inconclusive and
retry at host level. Claude Code and other non-Codex harnesses must ignore this section
and use their normal execution path.

## Resolve the durable task

1. Resolve the goal from the arguments, current Bead, or active plan section. Turn it
   into a checkable outcome; a phase, named plan boxes, or an explicit acceptance
   condition all qualify.
2. Locate the paired plan from `bd show <id>` or `$AGENT_HOME/plan/<bd-id>-*.md`.
   Non-trivial work without a plan first goes through `bdx:plan`. Continue only when
   its consequential decisions are settled.
3. Claim an open Bead. Read only the plan goal, in-scope boxes, settled decisions,
   open questions that block this goal, and the latest relevant Beads comments.
4. Read repository instructions, the working-tree status, the closest existing code
   pattern, and the cheapest command that proves the current spine is healthy.

Completion criterion: one Bead and plan own the goal, the working tree is understood,
and the baseline check is known.

## Route by risk

Use `build-loop` for ordinary feature behavior with settled design and a strong,
deterministic test oracle.

Stop before editing and recommend `bdx:slice-loop` when the goal changes any of these:

- authentication, authorization, or tenant isolation;
- charging, entitlement, accounting, destructive operations, or data migrations;
- crash recovery, distributed concurrency, irreversible external effects, or a
  cross-repository state machine;
- behavior whose success is subjective or cannot be exercised deterministically;
- work that must be defended or audited increment by increment.

State the plain tradeoff: `build-loop` buys wall-clock speed with one boundary review;
`slice-loop` buys repeated independent assurance and a per-slice audit trail. If the
user explicitly accepts the lighter assurance after that warning, continue here and
make the final fresh review mandatory.

Completion criterion: the assurance mode matches the actual blast radius, not merely
the user's desired speed.

## Lock the design

Before editing, emit this compact contract:

```text
build-loop: <goal>
Outcome     <observable behavior that will exist>
Invariants  <boundaries that must remain true>
Seam        <existing pattern or interface this extends>
Check       <executable acceptance command or scenario>
Non-goals   <nearby behavior deliberately excluded>
Done when   <machine-checkable completion condition>
```

Inspect enough real code to fill every line. Prefer one existing pattern over a new
abstraction. If a consequential choice remains open, post the blocker to the Bead and
return it to the human; implementation does not get to settle product behavior by
accident.

Completion criterion: every line is concrete, the check can go red, and no open
question can change the chosen seam.

## Run the tight loop

Default to at most six behavioral increments; honor `--max N` when supplied. An
increment is one coherent behavior with one observable acceptance signal, not one
file, layer, test, or checklist line.

For each increment:

1. Choose the smallest behavior that advances `Done when`. If no runnable spine
   exists, make the first increment the thinnest end-to-end path.
2. Read only the files needed for that behavior and its closest established pattern.
3. Implement through the locked seam. Keep unrelated robustness, cleanup, and edge
   cases outside the increment unless `Done when` requires them.
4. Run the narrowest deterministic check that exercises the changed behavior, then
   rerun the spine's cheap heartbeat. Add a persisted regression check when existing
   coverage cannot see the behavior.
5. Repair red results in the same context. The second recurrence of the same failure
   is a stop signal: preserve the evidence and return to the human or restart from a
   clean context with a sharper contract.
6. Continue immediately while the next behavior is settled and the context remains
   coherent. Do not run a per-increment reviewer, mutation ritual, report card,
   decision row, or Beads comment.

Use a deliberate red probe only for the new load-bearing seam or a check whose ability
to fail is genuinely uncertain. One probe for the goal is normally enough.

Completion criterion: the increment's behavior is observable, its narrow check and
heartbeat are green, and the working tree remains a stable base for the next behavior.

## Persist milestones

Durability follows outcomes, not tool calls:

| Event | Durable action |
| --- | --- |
| Plan box demonstrably complete | Invoke `bdx:check <bd-id> "<unique checkbox fragment>" --quiet` |
| Material tradeoff, divergence, or deferral | Append one concise decision-log entry |
| Phase or requested goal complete | Post one Beads comment with behavior and evidence |
| Blocker or human decision | Post the exact question and current evidence to Beads |
| Context rotation or interruption | Invoke `bdx:dump` once |

Leave partial plan boxes open. Ordinary implementation choices belong in code and
tests, not the decision log. A sequence of green micro-edits does not earn a sequence
of durable artifacts.

Completion criterion: a cold successor can locate the frontier without replaying the
session, and the record contains no per-increment narration.

## Gate the goal once

After `Done when` is satisfied:

1. Run the broader relevant tests, typecheck, lint, build, or end-to-end scenario for
   the completed goal. Scope the commands to the affected product area when possible.
2. Run one fresh-context `bdx:quality-audit light` over the goal's diff. If the goal
   crosses a mechanism boundary that later work depends on, audit at that boundary;
   otherwise audit only at the end.
3. Fix demonstrated, material defects. Allow at most two repair cycles on the same
   issue. Review the fix delta; do not reroll an unchanged diff until a reviewer says
   something different.
4. Tick each completed plan box with
   `bdx:check <bd-id> "<unique checkbox fragment>" --quiet`, then post one final Beads
   comment containing the observable result, verification commands, review verdict,
   and any deferred work.

An advisory finding is durable input, not an automatic expansion of the feature.
Create follow-up work only when it is concrete and actually needed.

Completion criterion: the broad gate is green, the fresh review has no blocking
confirmed defect, and every ticked plan box is true in the running system.

## Halt conditions

Halt cleanly when any condition fires:

- a consequential product or architecture decision is unresolved;
- the same verification failure recurs twice;
- the acceptance signal cannot objectively prove the behavior;
- the six-increment or caller-supplied bound is reached before the goal;
- context compaction or recall degradation makes the locked design unreliable;
- the diff overlaps user-owned work that cannot be isolated safely;
- the fresh reviewer challenges a mechanism the remaining plan depends on.

On an in-flight halt, invoke `bdx:dump`, record the blocker on the Bead, and name the
single decision or command that resumes work. A bound is a handoff, never permission
to tick unfinished boxes.

## Report

Emit one compact report at goal completion or halt:

```text
build-loop: <goal met | halted — reason>

  Built      <observable behavior now working>
  Verified   <narrow checks + broad gate>
  Review     <fresh-review verdict>
  Plan       <boxes completed / in scope>
  Decisions  <material entries or none>
  Next       <close, next milestone, or exact unblock action>
```

Do not close the Bead automatically. `bdx:close` remains the explicit lifecycle
boundary after the user accepts the completed task.

## Composition

- `bdx:plan` / `bdx:attach` establish the durable task.
- `bdx:check` records completed outcomes; `bdx:dump` preserves interrupted state.
- `bdx:quality-audit light` supplies the one independent boundary review.
- `bdx:slice-loop` is the high-assurance alternative for risky or per-slice-audited
  work.
- `bdx:close` writes the shipped summary and retires the task after acceptance.
