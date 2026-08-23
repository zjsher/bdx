# Linear projection

bdx treats Linear as a team-facing projection, not as a second copy of the
Beads database.

## Ownership

| Data | Authority | Projection behavior |
| --- | --- | --- |
| Team status, assignee, priority, project, cycle, discussion | Linear | Read by agents; never inferred from artifact prose |
| Bead ID, dependency graph, agent workflow state | Beads | Retained locally; only the canonical Linear reference crosses the seam |
| Live plan | `$AGENT_HOME` Markdown | Published one-way as one issue-linked Linear Document, updated in place |
| Plan checkboxes and `## Log` | `$AGENT_HOME` Markdown | Checkboxes stay in the document; raw log entries stay local |
| Summary | `$AGENT_HOME` Markdown | Published as an immutable completion comment, or a document when long |
| Context dumps | `$AGENT_HOME` Markdown | Excluded unless explicitly opted in; eligible dumps become sanitized checkpoint comments |
| Memories and session IDs | Beads / artifact metadata | Never published |

The source Markdown is never rewritten from Linear. Human edits to a managed
projection do not become artifact edits.

## Privacy

Publication fails closed:

- `private: false` is required.
- `private: true`, missing `private:`, and unrecognized values are excluded.
- An artifact must contain exactly one scalar `bd:` matching a Beads ID and
  exactly one scalar boolean `private:`. Duplicate, null, collection, missing,
  and malformed values are excluded.
- Frontmatter uses a deliberately narrow bdx grammar: top-level keys must be
  canonical bare identifiers. Tagged, anchored, escaped, quoted, merged,
  explicit, whitespace-separated, or otherwise exotic top-level YAML makes
  the entire artifact ineligible. This prevents equivalent YAML spellings from
  overriding the privacy boundary without introducing a runtime YAML parser.
  Indented content is accepted only beneath a preceding canonical collection
  or block-scalar key; root-indented content is rejected as malformed.
- Plans and summaries are eligible artifact kinds.
- Context dumps require a separate explicit opt-in even when `private: false`.
- Frontmatter, session IDs, local absolute paths, and plan logs are not part of
  the published view.

Legacy files without privacy metadata stay local until a human classifies them.

## Identity and idempotency

The Beads `external_ref` is the canonical Linear issue identity. A future
artifact publisher owns one Linear object per `bd-id + artifact kind + source
filename`: a mutable Document for the live plan, an immutable completion
comment for a summary, and an opt-in checkpoint comment for a context dump.
Each object carries a stable marker and content hash. Reapplying unchanged
content must be a no-op.

Agent-level plan checkboxes remain inside the plan Document. Only independently
assignable team work becomes a Linear sub-issue. Raw `bdx-note` log entries do
not generate comments; milestone-level progress may publish as a concise
bridge-owned comment.

Derived `linear:TEAM-123` frontmatter references may help Obsidian graphing,
but they are not sync identity.

## Mutation boundary

There is no unbounded mutation command. Issue transport must receive explicit
bead IDs or one explicit parent tree, show the native `bd linear` dry-run, and
require a separate apply action. Artifact publication follows the same
plan/apply boundary.

`bdx-linear status` is read-only. It reports compatibility, native Linear
configuration, publishable artifacts, and exclusions without printing API
credentials.
