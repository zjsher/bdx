#!/bin/bash
# SessionStart hook: if $BD_ID is set in the parent env, auto-attach this
# session to that beads task without running the /bdx:attach skill manually.
#
# Actions:
#   1. Verify the bd issue exists
#   2. If status is `open`, flip to `in_progress`
#   3. Append this harness-qualified session identity to the plan file's
#      `sessions:` frontmatter
#      (idempotent — no-op if already present)
#   4. Emit a briefing (plan + latest context + latest summary + recent
#      comments) as `additionalContext` so the agent starts pre-loaded
#
# Opt in by launching as:
#   BD_ID=bd-xxx claude -n "bd-xxx-<slug>"
# or use the `bdc` shell function (see ~/.claude/hooks/bdc).

set -u

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty')

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./bdx-session-id.sh
. "$SCRIPT_DIR/bdx-session-id.sh"
BDX_SESSION_ID=""
[ -n "$SESSION_ID" ] && BDX_SESSION_ID=$(bdx_session_identity "$SESSION_ID")

# Only act on fresh startup — resume/clear/compact already have context
[ "$SOURCE" = "startup" ] || exit 0

BD_ID="${BD_ID:-}"
[ -n "$BD_ID" ] || exit 0  # not a bd-attached session, no-op

AGENT_HOME="${AGENT_HOME:-$HOME/.bdx-agent}"

# Verify bd issue + capture JSON (bd exits non-zero + emits {"error": ...} if missing)
if ! ISSUE_JSON=$(bd show "$BD_ID" --json 2>/dev/null); then
  echo "bd-auto-attach: $BD_ID not found; skipping" >&2
  exit 1
fi
if [ "$(printf '%s' "$ISSUE_JSON" | jq -r 'type')" != "array" ] || \
   [ "$(printf '%s' "$ISSUE_JSON" | jq 'length')" = "0" ]; then
  echo "bd-auto-attach: unexpected bd output for $BD_ID; skipping" >&2
  exit 1
fi

STATUS=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].status // empty')
TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].title // empty')

# Flip open → in_progress
if [ "$STATUS" = "open" ]; then
  bd update "$BD_ID" --status in_progress >/dev/null 2>&1 || true
fi

# Locate plan (1 per task by convention)
PLAN=$(ls "$AGENT_HOME"/plan/"$BD_ID"-*.md 2>/dev/null | head -1)

# Append the harness-qualified session identity to plan frontmatter
# (idempotent).
# POSIX awk — no python or yq dependency. Handles four cases:
#   - sessions: with existing entries → append new uuid if not present
#   - sessions: with new uuid already there → no-op (idempotent)
#   - sessions: [] inline empty list → convert to multi-line + append
#   - no sessions: key in frontmatter → inject the block before closing ---
# Files without YAML frontmatter pass through unchanged.
if [ -n "$PLAN" ] && [ -n "$BDX_SESSION_ID" ]; then
  awk -v sid="$BDX_SESSION_ID" '
  BEGIN { in_fm=0; in_sessions=0; saw_sessions=0; sid_present=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; print; next }
  in_fm && /^---[[:space:]]*$/ {
    if (in_sessions && !sid_present) print "  - \"" sid "\""
    if (!saw_sessions) { print "sessions:"; print "  - \"" sid "\"" }
    in_fm=0; in_sessions=0; print; next
  }
  in_fm && /^sessions:[[:space:]]*$/ { saw_sessions=1; in_sessions=1; print; next }
  in_fm && /^sessions:[[:space:]]*\[\][[:space:]]*$/ { saw_sessions=1; print "sessions:"; in_sessions=1; next }
  in_sessions && /^[[:space:]]+-/ { if (index($0, sid) > 0) sid_present=1; print; next }
  in_sessions && /^[^[:space:]-]/ {
    if (!sid_present) print "  - \"" sid "\""
    in_sessions=0; print; next
  }
  { print }
  ' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN" || rm -f "$PLAN.tmp"
fi

# Pick latest context + summary for this bd-id
latest_with_bd() {
  local dir="$1"
  [ -d "$dir" ] || return
  grep -l "^bd: *$BD_ID\$" "$dir"/*.md 2>/dev/null | while read -r f; do
    printf '%s\t%s\n' "$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")" "$f"
  done | sort -rn | head -1 | cut -f2-
}
LATEST_CTX=$(latest_with_bd "$AGENT_HOME/context")
LATEST_SUM=$(latest_with_bd "$AGENT_HOME/summary")

# Build briefing
CTX=$(mktemp)
{
  echo "# Auto-attached to $BD_ID — ${TITLE:-(no title)}"
  echo
  echo "Status flipped to **in_progress** (was $STATUS)."
  echo "Session identity appended to plan \`sessions:\` list: \`$BDX_SESSION_ID\`."
  echo
  if [ -n "$PLAN" ]; then
    echo "## Plan — $PLAN"
    echo
    echo '```markdown'
    head -400 "$PLAN"
    echo '```'
    echo
  else
    echo "_No plan file found at $AGENT_HOME/plan/$BD_ID-*.md._"
    echo
  fi
  if [ -n "$LATEST_CTX" ]; then
    echo "## Latest context dump — $LATEST_CTX"
    echo
    echo '```markdown'
    head -200 "$LATEST_CTX"
    echo '```'
    echo
  fi
  if [ -n "$LATEST_SUM" ]; then
    echo "## Latest summary — $LATEST_SUM"
    echo
    echo '```markdown'
    head -120 "$LATEST_SUM"
    echo '```'
    echo
  fi
  COMMENTS=$(bd comments "$BD_ID" 2>/dev/null | tail -80)
  if [ -n "$COMMENTS" ] && [ "$COMMENTS" != "No comments on $BD_ID" ]; then
    echo "## Recent bd comments"
    echo
    echo '```'
    echo "$COMMENTS"
    echo '```'
  fi

  # Counter-instruction to `bd prime`, which lands in this same turn-1 context
  # advertising `bd update <id> --notes/--design`. Stated here so the agent
  # picks the right channel up front instead of discovering it via a block.
  echo
  echo "## Where writes go"
  echo
  echo "- Learned something mid-flight -> \`bdx-note \"<text>\"\` (appends to the plan's \`## Log\`)"
  echo "- Plan step finished -> \`/bdx:check $BD_ID \"<step>\"\`"
  echo "- Leaving mid-task -> \`/bdx:dump\`"
  echo "- Pointer for the bd thread -> \`bd comment $BD_ID \"...\"\`"
  echo
  echo "\`bd note\` and \`bd create|update --notes/--design/--context/--acceptance\` are blocked by a PreToolUse hook: nothing in this workflow reads those fields. Narrative lives in the plan."
} > "$CTX"

jq -Rs --arg title "bd-attached: $BD_ID" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    sessionTitle: $title,
    additionalContext: .
  }
}' < "$CTX"

rm -f "$CTX"
exit 0
