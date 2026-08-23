---
name: dump
description: Use when the user invokes /bdx:dump to persist a concise resumability handoff on a native Bead.
---

# dump

Capture the durable frontier of the current work without creating a context file.
The installed official Beads skill owns persistence and lifecycle mechanics; use its
current `bd prime` guidance rather than carrying a private command recipe here.

## Persist the handoff

1. Resolve one exact target Bead and inspect its current fields, relationships, and
   existing discussion. Do not rely on an ambiguous last-touched issue.
2. Distill only verified, resumable state:
   - current outcome and state;
   - changes or investigation completed;
   - executable evidence and actual results;
   - decisions, constraints, and rejected paths that still matter;
   - remaining work or blocker;
   - the exact next action.
3. Append that handoff through the native Beads discussion surface. If the task's
   durable definition changed, update the corresponding native description, design,
   acceptance, or relationship as well instead of hiding the change in a comment.
4. Create and link native follow-up Beads for independently actionable work. Put a
   genuinely reusable cross-task fact into native Beads memory through the official
   workflow.

Keep the handoff compact. Exclude transcripts, secrets, speculation, and facts that
the repository or Bead already makes obvious. Integration visibility is determined
by Beads and its configured provider, so team-critical task definition belongs in
native issue fields rather than only in discussion.

Finish by reporting the target Bead and what durable frontier was persisted. Create
no Markdown dump or second task artifact.
