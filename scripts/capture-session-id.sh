#!/bin/bash
# SessionStart hook: capture the host-provided session id as a harness-qualified
# bdx identity (for example, claude-code:<uuid> or codex:<uuid>).
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=./bdx-session-id.sh
. "$SCRIPT_DIR/bdx-session-id.sh"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
[ -n "$SESSION_ID" ] || exit 0

BDX_ID=$(bdx_session_identity "$SESSION_ID")
HARNESS=${BDX_ID%%:*}

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  # Claude Code provides an env file whose exports persist into later tool
  # calls. Keep CLAUDE_SESSION_ID as a raw compatibility alias for tooling that
  # knows how to find Claude transcripts.
  printf 'export BDX_SESSION_ID=%q\n' "$BDX_ID" >> "$CLAUDE_ENV_FILE"
  if [ "$HARNESS" = "claude-code" ]; then
    printf 'export CLAUDE_SESSION_ID=%q\n' "$SESSION_ID" >> "$CLAUDE_ENV_FILE"
  fi
else
  # Codex and other hook-compatible hosts don't expose a persistent env-file
  # contract. Inject the identity into developer context so bdx skills can use
  # it directly. Re-emitting on clear/compact keeps it available after context
  # resets when those SessionStart sources are supported.
  jq -n --arg sid "$BDX_ID" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ("bdx-session-id: \"" + $sid + "\". Use this exact harness-qualified value in sessions: frontmatter when BDX_SESSION_ID is unavailable.")
    }
  }'
fi
exit 0
