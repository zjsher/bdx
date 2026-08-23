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

bdx does not use native Beads pull for routine reconciliation. Native pull has
a shared `linear.last_sync` cursor and can import dependency relations, which
crosses the authority boundary below. Instead, the bdx reconciler reads Linear
directly and updates only already-linked beads. Linear Completed, Canceled, or
archived issues close the linked bead; started issues become `in_progress`.

The initial inbound allowlist is title, priority, and coordination status.
Linear description and human assignee are cached for agent visibility but do
not overwrite the bead: bdx uses the description for the durable plan pointer
and Beads uses assignee for the agent claim. Dependencies, labels, issue type,
plans, summaries, and contexts are never changed by inbound reconciliation.

Linear comments are cached one-way as full, UUID-keyed inbox records. Creates
and edits are idempotent; edited comments become unread again. A run emits at
most one concise Beads pointer comment per affected bead, never one Beads
comment per Linear comment body. On disk, each bead has one UUID-keyed comment
object, so reading or reconciling one inbox does not scan the history of every
other bead.

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

```bash
# Explicit bead selection
scripts/bdx-linear issues plan bd-123 bd-456
scripts/bdx-linear issues apply --yes bd-123 bd-456

# Or one parent tree, expanded to an explicit capped list before native push
scripts/bdx-linear issues plan --tree bd-parent
# Run the frozen explicit-ID command printed by plan; apply rejects --tree.
scripts/bdx-linear issues apply --yes bd-parent bd-child-1 bd-child-2
```

Selections are deduplicated and capped at 100 beads. Apply repeats the dry-run
and stops if it fails. Tree expansion is preview-only so descendants added
between preview and apply cannot enter the frozen selection. After a successful
push, native `external_ref` remains canonical; a recognized Linear identifier
is mirrored as `linear:TEAM-123` in the matching plan's `external:` list when
that list can be edited safely.

`bdx-linear status` is read-only. It reports compatibility, native Linear
configuration, publishable artifacts, and exclusions without printing API
credentials.

## Inbound reconciliation

```bash
# Preview issue and comment changes; writes nothing
scripts/bdx-linear reconcile plan

# Apply one bounded reconciliation window
scripts/bdx-linear reconcile once --yes

# Run locally every two minutes; minimum interval is 60 seconds
scripts/bdx-linear reconcile loop --yes --interval 120

# Read cached human discussion, then mark it read
scripts/bdx-linear inbox bd-123
scripts/bdx-linear inbox bd-123 --mark-read
```

Operational state lives under
`$AGENT_HOME/.state/linear/<scope-fingerprint>/`. The fingerprint includes the
Beads database, Linear team/project, and API endpoint. Issue and comment
progress is tracked independently: issues are observed as a current snapshot,
while comments use a time-window watermark and transient GraphQL page cursors.
Remote queries are restricted to the issues already linked from Beads. Each
run reads those linked issue snapshots in batches. The comment watermark
continues across link removals; a newly linked or re-linked issue alone gets a
historical comment bootstrap, rather than resetting the whole project window.

Only one apply run may hold the scope lock. Cursor state contains no API key,
comment body, email, or agent session. It advances only after every intended
Beads mutation, inbox write, and rollup pointer succeeds. A partial run may
leave already-applied idempotent Beads changes, but the old cursor forces the
next run to reconcile the same remote window again. A dead same-host PID lock
is recovered automatically. A foreign-host lock never expires automatically;
verify that runner has stopped before manually removing its lock directory.

Polling is the local-first transport. A later webhook receiver may trigger the
same reconciliation command for lower latency; periodic polling remains the
recovery path for missed deliveries. Hard-deleted comment tombstones require a
webhook remove event or a periodic full inventory comparison and are deferred
from the first poller milestone.
