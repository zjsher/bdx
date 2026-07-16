#!/usr/bin/env bash
# context-tokens.sh [cap_pct] [window]
# Prints the current session's actual context occupancy, measured from the last
# API exchange recorded in the session transcript (input + cache-read +
# cache-write on the most recent assistant message = what the model's context
# actually held on that turn), as a percentage of the context window.
#
#   cap_pct  halt threshold as % of window (default 70)
#   window   context window in tokens (default $CLAUDE_CONTEXT_WINDOW or 1000000)
#
# The window cannot be measured — the transcript records only the model id, not
# its window size — so it is configured: 1M matches this machine's default
# sessions; pass 200000 (or set CLAUDE_CONTEXT_WINDOW) for a non-1M session.
#
# Exit codes: 0 = under cap, 1 = at/over cap (usable as a gate),
#             2 = transcript not found (treat as "cannot measure", not "over").
set -euo pipefail

CAP_PCT="${1:-70}"
WINDOW="${2:-${CLAUDE_CONTEXT_WINDOW:-1000000}}"

# Locate the transcript: prefer the exact session, fall back to the newest
# transcript for this project (correct unless parallel sessions share the cwd).
PROJECT_SLUG=$(pwd | sed 's/[\/.]/-/g')
PROJECT_DIR="$HOME/.claude/projects/$PROJECT_SLUG"

TRANSCRIPT=""
if [[ -n "${CLAUDE_SESSION_ID:-}" && -f "$PROJECT_DIR/$CLAUDE_SESSION_ID.jsonl" ]]; then
  TRANSCRIPT="$PROJECT_DIR/$CLAUDE_SESSION_ID.jsonl"
elif [[ -d "$PROJECT_DIR" ]]; then
  TRANSCRIPT=$(ls -t "$PROJECT_DIR"/*.jsonl 2>/dev/null | head -1 || true)
fi

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  echo "context-tokens: no transcript found under $PROJECT_DIR" >&2
  exit 2
fi

TOKENS=$(tail -50 "$TRANSCRIPT" | jq -rs '
  [ .[] | select(.message.usage != null) | .message.usage
    | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
  ] | last // empty')

if [[ -z "$TOKENS" ]]; then
  echo "context-tokens: no usage entries in transcript tail" >&2
  exit 2
fi

USED_PCT=$(( TOKENS * 100 / WINDOW ))
echo "$TOKENS tokens = ${USED_PCT}% of ${WINDOW} window (halt at ${CAP_PCT}%) · $(basename "$TRANSCRIPT" .jsonl)"

if (( USED_PCT >= CAP_PCT )); then
  exit 1
fi
