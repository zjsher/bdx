---
name: render
description: Use when the user invokes /bdx:render to open a disposable Markdown view of a Bead and its cross-referenced Beads.
---

# render

Create a human-readable, read-only projection of native Beads data. The installed
official Beads skill and current `bd prime` guidance own data access; this skill must not mutate issues, comments, relationships, memories, or status.

## Collect the graph

1. Resolve one exact root Bead and read its complete native record and discussion.
2. Discover referenced Beads through native parent, child, dependency, blocking, and
   related relationships, plus explicit Bead IDs in collected issue fields and
   comments.
3. Traverse those references transitively. De-duplicate by Bead ID, break cycles, and
   record missing or inaccessible references without inventing their contents.
4. Collect every available native field and comment for each discovered Bead. Do not
   follow arbitrary external URLs or load linked repository documents unless the
   user explicitly adds them to the scope.

## Render and open

Write one Markdown file under the OS temp directory using a safely generated unique
path. Never place the projection in the repository. Include:

- generation time, workspace, root Bead, and a disposable/read-only warning;
- a relationship index that links to anchors within the document;
- the root Bead first, followed by each referenced Bead exactly once;
- for every Bead: metadata and status, relationships, description, design,
  acceptance criteria, notes, and comments in chronological order;
- explicit markers for empty fields and unresolved references.

Open the generated file in the system's default Markdown-capable application. Keep
the temp file available while that application is using it and report its path. The
rendered file is a snapshot: edits to it never flow back to Beads, and a fresh render
is required after Beads changes.
