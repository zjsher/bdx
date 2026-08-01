#!/bin/bash
# Shared helpers for turning a hook-provided session id into a portable bdx
# identity. Keep the stored value harness-qualified so the same frontmatter can
# point back to sessions from more than one agent host.

bdx_detect_harness() {
  local harness="${BDX_HARNESS:-}"

  if [ -z "$harness" ]; then
    # PLUGIN_ROOT is a Codex-specific plugin-hook variable. Codex also exports
    # CLAUDE_PLUGIN_ROOT for compatibility, so it must be checked first.
    if [ -n "${PLUGIN_ROOT:-}" ]; then
      harness="codex"
    elif [ -n "${CLAUDE_ENV_FILE:-}" ] || [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
      harness="claude-code"
    else
      harness="unknown"
    fi
  fi

  harness=$(printf '%s' "$harness" | tr '[:upper:]' '[:lower:]')
  case "$harness" in
    ''|*[!a-z0-9._-]*) harness="unknown" ;;
  esac
  printf '%s' "$harness"
}

bdx_session_identity() {
  local raw_id="${1:-}"
  [ -n "$raw_id" ] || return 1
  printf '%s:%s' "$(bdx_detect_harness)" "$raw_id"
}
