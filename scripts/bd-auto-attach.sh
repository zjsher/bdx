#!/bin/bash
# SessionStart hook: if $BD_ID is set in the parent env, auto-attach this
# session to that beads task without running the /bdx:attach skill manually.
#
# Actions:
#   1. Resolve the issue's per-project Beads repository
#   2. Verify the bd issue exists
#   3. If status is `open`, flip to `in_progress`
#   4. Append this harness-qualified session identity to the plan file's
#      `sessions:` frontmatter
#      (idempotent — no-op if already present)
#   5. Emit a briefing (plan + latest context + latest summary + recent
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

# Resolve before touching Beads. This lets BD_ID sessions launch from anywhere
# while each project keeps its own native database.
if ! PROJECT_DIR=$("$SCRIPT_DIR/bdx-resolve-project" "$BD_ID"); then
  echo "bd-auto-attach: could not resolve project for $BD_ID; skipping" >&2
  exit 1
fi

# Verify bd issue + capture JSON (bd exits non-zero + emits {"error": ...} if missing)
if ! ISSUE_JSON=$(bd -C "$PROJECT_DIR" show "$BD_ID" --json 2>/dev/null); then
  echo "bd-auto-attach: $BD_ID not found in $PROJECT_DIR; skipping" >&2
  exit 1
fi
if [ "$(printf '%s' "$ISSUE_JSON" | jq -r 'type')" != "array" ] || \
   [ "$(printf '%s' "$ISSUE_JSON" | jq 'length')" = "0" ]; then
  echo "bd-auto-attach: unexpected bd output for $BD_ID; skipping" >&2
  exit 1
fi

STATUS=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].status // empty')
TITLE=$(printf '%s' "$ISSUE_JSON" | jq -r '.[0].title // empty')
STATUS_MESSAGE="Status is **$STATUS**."

# Preflight the one required live plan before changing authoritative Beads
# state. The same locked writer validates frontmatter and records this session
# against the status we actually read.
declare -a PLANS=()
while IFS= read -r plan; do PLANS+=("$plan"); done < <(
  find "$AGENT_HOME/plan" -maxdepth 1 -type f -name "$BD_ID-*.md" -print 2>/dev/null
)
if [ "${#PLANS[@]}" -eq 0 ]; then
  echo "bd-auto-attach: no plan found for $BD_ID; run /bdx:scope first" >&2
  exit 1
elif [ "${#PLANS[@]}" -gt 1 ]; then
  echo "bd-auto-attach: multiple plans found for $BD_ID" >&2
  printf '  %s\n' "${PLANS[@]}" >&2
  exit 1
fi
PLAN="${PLANS[0]}"
FRONTMATTER_ARGS=("$BD_ID" --status "$STATUS")
[ -z "$BDX_SESSION_ID" ] || FRONTMATTER_ARGS+=(--session "$BDX_SESSION_ID")
if ! "$SCRIPT_DIR/bdx-plan-frontmatter" "${FRONTMATTER_ARGS[@]}" >/dev/null; then
  echo "bd-auto-attach: failed to validate/update plan frontmatter for $BD_ID" >&2
  exit 1
fi

# Flip open → in_progress
if [ "$STATUS" = "open" ]; then
  if ! UPDATE_OUTPUT=$(bd -C "$PROJECT_DIR" update "$BD_ID" --status in_progress 2>&1); then
    echo "bd-auto-attach: failed to update $BD_ID to in_progress:" >&2
    printf '%s\n' "$UPDATE_OUTPUT" | sed 's/^/  /' >&2
    exit 1
  fi
  STATUS_MESSAGE="Status changed **open → in_progress**."
  STATUS="in_progress"
  if ! "$SCRIPT_DIR/bdx-plan-frontmatter" "$BD_ID" --status "$STATUS" >/dev/null; then
    echo "bd-auto-attach: Beads is in_progress but plan projection failed; repair with bdx-sync-status $BD_ID" >&2
    exit 1
  fi
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
  echo "Project: \`$PROJECT_DIR\`"
  echo "$STATUS_MESSAGE"
  if [ -n "$BDX_SESSION_ID" ]; then
    echo "Session identity recorded in plan \`sessions:\`: \`$BDX_SESSION_ID\`."
  else
    echo "No harness session identity was available to record."
  fi
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
  COMMENTS=$(bd -C "$PROJECT_DIR" comments "$BD_ID" 2>/dev/null | tail -80)
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
