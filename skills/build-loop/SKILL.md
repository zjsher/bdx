---
name: build-loop
description: >-
  Implement a settled feature milestone in one continuous context, using a tight
  executable check after each behavior and one independent review at the milestone
  boundary. Use when a plan or Bead defines the outcome and the changed behavior can
  be verified deterministically. Use slice-loop when correctness requires independent
  evidence at each increment or cannot be proven reliably at one milestone boundary.
---

# build-loop

Build one planned milestone through a tight implementation loop. Keep the implementer
in context, prove each behavior as it lands, and persist outcomes at milestone
boundaries.

## Codex host execution (mandatory)

When the harness is Codex, run every shell tool call containing `bd` with
`sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set
`prefix_rule: ["bd"]`. Treat a sandboxed Dolt connection failure as inconclusive and
retry at host level. Claude Code and other non-Codex harnesses must ignore this section
and use their normal execution path.

## Load the milestone

Use the already-attached task. Invoke `bdx:attach` only when no task is attached, or
`bdx:plan` when new non-trivial work has no durable task. Load one claimed Bead, its
paired plan, the current milestone, repository instructions, nearby code patterns,
and the cheapest baseline command for the affected path. Run the baseline before
editing.

Advance when the Bead and plan paths are known, the baseline exits successfully, and
the milestone names an observable behavior.

## Choose the assurance level

Use `build-loop` when one implementer can prove the milestone with deterministic
checks and one independent boundary review.

Use `bdx:slice-loop` when any of these properties applies:

- correctness depends on state or interactions the milestone gate cannot exercise
  reliably;
- a mistaken change would be difficult to detect or reverse before affecting others;
- consequential choices need independent review while the implementation is growing;
- policy or the user requires independent evidence for each increment.

Base the choice on the properties of this change. A business-domain label alone does
not determine the assurance level.

Advance with `build-loop` when the milestone has a reliable boundary proof and one
boundary review supplies the required assurance.

## Lock the contract

Inspect the real seam, then emit:

```text
build-loop: <milestone>
Behavior   <observable behavior that will exist>
Invariant  <boundary that remains true>
Seam       <existing interface or pattern being extended>
Proof      <command or scenario that demonstrates success>
```

Resolve product choices that can change the seam before implementation. Record a
material decision in the plan when future work needs its rationale.

Advance when every field names actual behavior, an established code seam, or an
executable proof.

## Run the tight loop

For each coherent behavior that advances the contract:

1. Choose the smallest complete behavior. When the path has no runnable spine, start
   with the thinnest end-to-end path.
2. Read the files for that behavior and its closest established pattern.
3. Implement through the locked seam. Preserve the named invariant and established
   repository patterns.
4. Run the tightest deterministic check for the changed behavior. When that check
   does not exercise the runnable spine, run the spine heartbeat too.
5. Add a persisted regression check when existing coverage cannot observe the new
   behavior.
6. Repair from the failing evidence, rerun the check, and continue with the next
   settled behavior.

Keep increments in the implementer context. Persist progress and invoke independent
review at the milestone boundaries below. Use one deliberate red probe when the new
seam or its proof has not yet demonstrated that it can fail.

If two repair attempts produce the same result without new evidence, stop changing
code. Preserve the failing command and output, then report the exact missing decision,
access, or observable signal.

An increment is complete when its intended assertion is green and the spine heartbeat
is green when separate.

## Persist milestone outcomes

Durability follows observable progress:

| Event | Durable action |
| --- | --- |
| Plan box demonstrably complete | Invoke `bdx:check <bd-id> "<unique checkbox fragment>" --quiet` |
| Material tradeoff, divergence, or deferral | Append one concise decision-log entry |
| Requested milestone complete | Post one Beads comment naming the behavior and evidence |
| Human decision or missing access | Post the exact question and current evidence |
| Context rotation or interruption | Invoke `bdx:dump` once |

Leave a plan box open until its outcome is demonstrated. Durability is complete when
demonstrated plan boxes are ticked and the latest Beads comment names the current
frontier and next proof.

## Gate the milestone

When the contract's behavior is working:

1. Run the broader relevant tests, typecheck, lint, build, or end-to-end scenario for
   the affected product area.
2. Run one fresh-context `bdx:quality-audit light` over the milestone diff.
3. Repair each demonstrated blocking defect and rerun the affected proof and broad
   gate. Review the repair delta when it changes the audited mechanism.
4. Tick every demonstrably complete plan box with
   `bdx:check <bd-id> "<unique checkbox fragment>" --quiet`.
5. Post one Beads comment with the observable result, verification commands, review
   verdict, and concrete deferred work.

The milestone is complete when the broad gate exits successfully, the fresh review
has no unresolved blocking finding, and every ticked plan box is true in the running
system.

## Preserve a blocked frontier

When implementation needs a consequential decision, unavailable access, a reliable
proof, separation from overlapping user work, or a fresh context, preserve the
frontier with `bdx:dump` and a concise Beads comment. Name the single decision, access
grant, command, or re-entry action that resumes the milestone.

## Report

Emit one compact report at milestone completion or handoff:

```text
build-loop: <milestone complete | handoff reason>

  Built    <observable behavior now working>
  Proof    <narrow checks and broad gate>
  Review   <fresh-review verdict>
  Durable  <plan boxes and Beads update>
  Next     <next milestone, close, or exact re-entry action>
```

Finish with the milestone report. `bdx:close` owns the separate task-lifecycle
boundary.
