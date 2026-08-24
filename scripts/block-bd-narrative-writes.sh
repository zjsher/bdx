#!/bin/bash
# PreToolUse hook: keep task *narrative* in the plan file instead of bd's
# opaque text fields.
#
# Why this has to be a hook and not documentation: `bd prime` runs at every
# SessionStart and puts "bd update <id> --title/--description/--notes/--design"
# into turn-1 context. An instruction re-injected by the harness every session
# outranks prose living inside a skill file that only loads on invocation. The
# agent isn't ignoring bdx — it's obeying bd. Only a deterministic block wins.
#
# Blocked:
#   bd note ...
#   bd edit ...
#   bd create|update ... --notes|--append-notes|--design|--design-file
#                        |--context|--acceptance
#
# NOT blocked, deliberately:
#   bd comment  — load-bearing bdx infrastructure. `attach` reads the comment
#                 thread at boot (scripts/bd-auto-attach.sh), and dump /
#                 summarize / triage / check / slice-loop write pointers into
#                 it. Comments are the bd-side index; the plan is the prose.
#   -d/--description — plan step 7 writes the plan pointer through it.
#   bd remember — cross-session knowledge, a different layer entirely.
#
# Bypass: include `BDX_ALLOW_BD_NARRATIVE=1` as an inline env assignment in the
# bash command itself — e.g. `BDX_ALLOW_BD_NARRATIVE=1 bd note bd-x "..."`.
# The hook inspects the command string (not its own env), matching the
# convention in block-bare-bd-close.sh.

set -u

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Skip help invocations
if printf '%s' "$CMD" | grep -Eq '\bbd[[:space:]]+(note|edit|create|update)\b.*(-h\b|--help\b)'; then
  exit 0
fi

# Bypass escape hatch — inline env assignment in the command string itself.
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];&|])BDX_ALLOW_BD_NARRATIVE=1\b'; then
  exit 0
fi

# Only match `bd` in *command position*: start of a line, or after a shell
# separator. A plain space is deliberately NOT a boundary — `git commit -m
# "block bd note"` must not trip this, and prose mentioning the verb is far
# more common than an obscure invocation that needs it.
BOUNDARY='(^|[;&|(])[[:space:]]*'
NARRATIVE_FLAGS='--(notes|append-notes|design|design-file|context|acceptance)([[:space:]=]|$)'

VERB=""
if printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+note\b"; then
  VERB="bd note"
elif printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+edit\b"; then
  VERB="bd edit"
elif printf '%s' "$CMD" | grep -Eq "${BOUNDARY}bd[[:space:]]+(create|update|new)\b.*${NARRATIVE_FLAGS}"; then
  VERB="bd create/update with a narrative flag"
fi

[ -n "$VERB" ] || exit 0

# Reconstruct the exact replacement command so the fix is copy-paste, not a
# puzzle. Pull the bd-id and the last quoted string out of the attempt.
BD_ID=$(printf '%s' "$CMD" | grep -Eo 'bd-[a-z0-9]+' | head -1)
TEXT=$(printf '%s' "$CMD" | grep -Eo '"[^"]*"' | tail -1 | sed 's/^"//; s/"$//')

SUGGESTION="bdx-note ${BD_ID:-<bd-id>} \"${TEXT:-<what you learned>}\""

cat >&2 <<EOF
Blocked: \`$VERB\` — task narrative goes in the plan file, not bd's text fields.

bd holds state (status, deps, labels). The plan holds narrative, and it's the
only one of the two that a future \`/bdx:attach\` reads back or that you can
edit in place. Notes written into --notes/--design are invisible to every part
of the workflow.

Run this instead:

  $SUGGESTION

Other routes, by intent:
  a plan checkbox is done          ->  /bdx:check ${BD_ID:-<bd-id>} "<step>"
  about to log out mid-task        ->  /bdx:dump
  a pointer for the bd thread      ->  bd comment ${BD_ID:-<bd-id>} "..."  (still fine)
  knowledge that outlives the task ->  bd remember "..."  (still fine)

Escape hatch (rare):
  BDX_ALLOW_BD_NARRATIVE=1 <your original command>
EOF
exit 2
