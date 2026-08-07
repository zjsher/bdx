#!/bin/bash
# Block/allow matrix for scripts/block-bd-narrative-writes.sh, plus an
# end-to-end exercise of scripts/bdx-note against a throwaway $AGENT_HOME.
#
#   bash dev/test-narrative-hook.sh
#
# Exits non-zero on the first mismatch. The KNOWN GAPS section at the bottom
# documents what the hook provably cannot catch — those cases assert the
# current (leaky) behavior so a future rewrite has a baseline to change.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$ROOT/scripts/block-bd-narrative-writes.sh"
NOTE="$ROOT/scripts/bdx-note"
PASS=0; FAIL=0

# expect BLOCK|ALLOW, then the command string
expect() {
  local want="$1" cmd="$2" got
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(jq -Rn --arg c "$cmd" '$c')" \
    | "$HOOK" >/dev/null 2>&1
  [ $? -eq 2 ] && got=BLOCK || got=ALLOW
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf '  ok    %-5s %s\n' "$got" "$cmd"
  else
    FAIL=$((FAIL+1)); printf '  FAIL  want=%s got=%s  %s\n' "$want" "$got" "$cmd"
  fi
}

echo "== blocked: narrative verbs and flags =="
expect BLOCK 'bd note bd-abc "found the leak in the retry loop"'
expect BLOCK 'bd edit bd-abc'
expect BLOCK 'bd update bd-abc --notes "some narrative"'
expect BLOCK 'bd update bd-abc --append-notes "more"'
expect BLOCK 'bd update bd-abc --design "how it works"'
expect BLOCK 'bd update bd-abc --design-file /tmp/d.md'
expect BLOCK 'bd update bd-abc --context "background"'
expect BLOCK 'bd update bd-abc --acceptance "criteria"'
expect BLOCK 'bd create "x" --design "how it works"'
expect BLOCK 'bd update bd-abc --notes="equals form"'
expect BLOCK 'cd /tmp && bd note bd-abc "after a chain"'
expect BLOCK 'bd list ; bd note bd-abc "after a semicolon"'

echo
echo "== allowed: load-bearing bdx infrastructure =="
expect ALLOW 'bd comment bd-abc "summary: /path/to/summary.md"'      # attach reads these at boot
expect ALLOW 'bd comment bd-abc "checked: extracted requireAuth"'
expect ALLOW 'bd update bd-abc -d "plan: /path/plan.md"'             # plan step 7
expect ALLOW 'bd update bd-abc --description "plan: /p.md"'
expect ALLOW 'bd remember "auth uses JWT not sessions"'              # different layer

echo
echo "== allowed: everything else =="
expect ALLOW 'bd close bd-abc'
expect ALLOW 'bd list --status=in_progress'
expect ALLOW 'bd show bd-abc'
expect ALLOW 'bd create "x" -t task -p 2 -l bdx'
expect ALLOW 'bd note --help'
expect ALLOW 'bd update --help'
expect ALLOW 'BDX_ALLOW_BD_NARRATIVE=1 bd note bd-abc "bypass"'
expect ALLOW 'git commit -m "block bd note"'          # prose must not trip the guard
expect ALLOW 'git commit -m "add bd update --notes guard"'
expect ALLOW 'echo "run bd note to append" >> README.md'
expect BLOCK '$(bd note bd-abc "in a subshell")'      # ( is a command position
expect BLOCK 'bd list || bd note bd-abc "fallback"'

echo
echo "== KNOWN GAPS: PreToolUse hands us an opaque string, so these leak =="
echo "   (asserting current behavior, not endorsing it)"
expect ALLOW 'CMD='"'"'bd note bd-x "..."'"'"'; $CMD'   # command hidden in a variable
expect ALLOW 'bd $VERB bd-x "..."'                       # verb hidden in a variable
expect ALLOW 'eval "bd note bd-x '"'"'...'"'"'"'         # eval

echo
echo "== end-to-end: bdx-note =="
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
export AGENT_HOME="$TMP"; mkdir -p "$AGENT_HOME/plan"
PLAN="$AGENT_HOME/plan/bd-e2e-demo.md"
printf -- '---\nbd: bd-e2e\n---\n\n# Demo\n\n## Goal\nx\n\n## Related\n- [[y]]\n' > "$PLAN"

e2e() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok    $desc"
  else FAIL=$((FAIL+1)); echo "  FAIL  $desc"; fi
}
e2e "creates ## Log before ## Related"  "$NOTE" -q bd-e2e "first"
e2e "appends to existing ## Log"        "$NOTE" -q bd-e2e "second"
e2e "multi-line note"                   "$NOTE" -q bd-e2e $'multi\nline'
e2e "resolves bd-id from \$BD_ID"       env BD_ID=bd-e2e "$NOTE" -q "from env"

grep -q '^## Log$' "$PLAN"            && { PASS=$((PASS+1)); echo "  ok    ## Log section exists"; } || { FAIL=$((FAIL+1)); echo "  FAIL  ## Log missing"; }
grep -q '^  line$' "$PLAN"            && { PASS=$((PASS+1)); echo "  ok    continuation line indented"; } || { FAIL=$((FAIL+1)); echo "  FAIL  continuation not indented"; }
[ "$(grep -c '^- 2' "$PLAN")" = "4" ] && { PASS=$((PASS+1)); echo "  ok    4 entries written"; } || { FAIL=$((FAIL+1)); echo "  FAIL  wrong entry count: $(grep -c '^- 2' "$PLAN")"; }
# ## Related must survive intact, below the log
grep -q '^## Related$' "$PLAN"        && { PASS=$((PASS+1)); echo "  ok    ## Related preserved"; } || { FAIL=$((FAIL+1)); echo "  FAIL  ## Related clobbered"; }

echo
echo "== end-to-end: bdx-note failure modes =="
"$NOTE" -q bd-missing "x" >/dev/null 2>&1; [ $? -eq 1 ] && { PASS=$((PASS+1)); echo "  ok    exit 1 on missing plan"; } || { FAIL=$((FAIL+1)); echo "  FAIL  wrong exit on missing plan"; }
( unset BD_ID; "$NOTE" -q "orphan" ) >/dev/null 2>&1; [ $? -eq 2 ] && { PASS=$((PASS+1)); echo "  ok    exit 2 with no resolvable bd-id"; } || { FAIL=$((FAIL+1)); echo "  FAIL  wrong exit with no bd-id"; }

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
