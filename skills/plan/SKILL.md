---
name: plan
description: Use when the user invokes /bdx:plan to shape durable work directly in Beads before implementation.
---

# plan

Turn an outcome into an implementation-ready native Bead. This skill supplies a
planning quality gate; the installed official Beads skill owns every lifecycle
operation and `bd prime` is the current command source of truth.

## Plan in Beads

1. Load the official Beads skill and current `bd prime` guidance. Resolve the Beads
   workspace and determine whether the arguments name an existing Bead or new work.
2. Inspect the target and nearby dependencies before changing it. Preserve useful
   existing context and ask only about choices that materially change the outcome,
   boundary, or implementation seam.
3. Create or update native Beads data so the work records:
   - a self-contained observable outcome and scope;
   - consequential design decisions, constraints, seams, and invariants;
   - acceptance criteria that name checkable proof;
   - native parent, child, dependency, or related links where they affect execution.
4. Split only independently closable outcomes. Store each split as a native Bead and
   express ordering or blocking through native relationships.
5. If a specification or ADR is itself a deliverable, link it from the Bead. Keep
   task planning and handoff state in Beads rather than creating a planning document.

Finish when each resulting Bead is understandable without this conversation and is
either ready to claim or names the exact unresolved decision or blocker. Report the
Bead IDs, the durable fields changed, and the ready/blocked frontier.
