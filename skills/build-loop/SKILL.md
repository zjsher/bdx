---
name: build-loop
description: >-
  Implement one settled Beads task in a continuous context using a compact
  behavior/invariant/seam/proof contract, tight executable feedback, and one
  independent review at the milestone boundary. Beads owns the lifecycle.
---

# build-loop

Add implementation discipline to one Bead without creating another work system.
This skill owns how code is built and proven. The official Beads skill owns task
selection, issue fields, planning, dependencies, claiming, persistence, handoffs,
closure, memory, and integrations.

## Compose with Beads

Start only after the native Beads workflow has selected a Bead, loaded its current
context, and claimed it. Use the installed Beads skill and `bd prime` as the source of
truth for every lifecycle operation and CLI command. Do not duplicate those rules in
this skill; they evolve with Beads.

If no Bead is active, the outcome is not settled, or the work needs to be split,
return control to the Beads workflow. Do not create a Markdown plan or invent a bdx
lifecycle.

Load repository instructions, relevant code, nearby patterns, and the cheapest
baseline command for the affected path. Run the baseline before editing.

Advance when the active Bead names an observable outcome, its acceptance boundary is
clear, and the baseline exits successfully.

## Choose this loop when the proof fits

Use `build-loop` when one implementer can prove the requested milestone with
deterministic checks and one independent boundary review. Return to Beads to split
the work when it contains independently assignable outcomes or when one milestone
gate cannot reliably exercise consequential interactions.

## Lock the contract

Inspect the real seam, then emit:

```text
build-loop: <milestone>
Behavior   <observable behavior that will exist>
Invariant  <boundary that remains true>
Seam       <existing interface or pattern being extended>
Proof      <command or scenario that demonstrates success>
```

Resolve choices that can change the seam before implementation. Hand material
decisions back to the Beads workflow for native persistence; do not keep a separate
ledger or plan.

Advance when every contract field names actual behavior, an established code seam,
or an executable proof.

## Run the tight loop

For each coherent behavior that advances the contract:

1. Choose the smallest complete behavior. When no runnable spine exists, start with
   the thinnest end-to-end path.
2. Read the files for that behavior and the closest established pattern.
3. Implement through the locked seam while preserving the invariant.
4. Run the tightest deterministic check for the changed behavior. When that check
   does not exercise the runnable spine, run the spine heartbeat too.
5. Add a persisted regression check when existing coverage cannot observe the new
   behavior.
6. Repair from failing evidence, rerun the check, and continue.

Use one deliberate red probe when a new seam or proof has not demonstrated that it
can fail. If two repair attempts produce the same result without new evidence, stop
changing code and return the exact failing command, output, and missing signal to the
Beads workflow as a handoff frontier.

Do not narrate every command. Preserve only evidence or decisions another worker
genuinely needs, using the current native Beads guidance.

## Gate the milestone

When the contract behavior is working:

1. Run the broader relevant tests, typecheck, lint, build, or end-to-end scenario.
2. Run one fresh-context `/bdx:quality-audit light` over the milestone diff.
3. Repair demonstrated blocking defects and rerun the affected proof and broad gate.
   Review a repair delta when it changes the audited mechanism.
4. Compare the active Bead's acceptance boundary with executable evidence.
5. Return one compact evidence bundle to the Beads workflow: observable result,
   verification commands, review verdict, remaining work, and any reusable decision.

The milestone is complete when the broad gate exits successfully, the fresh review
has no unresolved confirmed finding, and the native Beads record can accurately
represent the remaining frontier without another bdx artifact.

## Report

Emit one compact result for both the user and the Beads workflow:

```text
build-loop: <milestone complete | handoff reason>

  Built    <observable behavior now working>
  Proof    <narrow checks and broad gate>
  Review   <fresh-review verdict>
  Evidence <decisions and results Beads should retain>
  Next     <close, split, block, or exact re-entry action>
```

The report is an input to Beads persistence, not a second durable record.
