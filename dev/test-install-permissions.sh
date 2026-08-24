#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-permissions.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
TEST_CODEX_HOME="$TEST_ROOT/codex-home"
TEST_AGENT_HOME="$TEST_ROOT/agent-home"
mkdir -p "$TEST_HOME/.claude" "$TEST_CODEX_HOME/rules"

printf '%s\n' '{"theme":"dark","permissions":{"allow":["Bash(existing:*)","Bash(bd:*)"]}}' > "$TEST_HOME/.claude/settings.json"
printf '%s\n' '# user rule survives' > "$TEST_CODEX_HOME/rules/bdx.rules"

run_installer() {
  HOME="$TEST_HOME" \
  CODEX_HOME="$TEST_CODEX_HOME" \
  AGENT_HOME="$TEST_AGENT_HOME" \
  SHELL=/bin/bash \
    bash "$REPO_ROOT/scripts/install.sh" --yes --skip-env --skip-bd \
      --skip-dolt --skip-init --skip-templates >/dev/null
}

run_installer
run_installer

jq -e '.theme == "dark"' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(existing:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(bd:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(bdx-resolve-project:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(bdx-plan-frontmatter:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(bdx-sync-status:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e 'index("Bash(bd:*)") == null and index("Bash(bdx-plan-frontmatter:*)") != null' \
  "$TEST_HOME/.claude/bdx-managed-permissions.json" >/dev/null

RULES_FILE="$TEST_CODEX_HOME/rules/bdx.rules"
test "$(grep -Fxc '# BEGIN bdx managed rule' "$RULES_FILE")" = "1"
test "$(grep -Fxc '# END bdx managed rule' "$RULES_FILE")" = "1"
grep -Fqx '# user rule survives' "$RULES_FILE"
grep -Fq 'pattern = ["bd"]' "$RULES_FILE"
grep -Fq 'pattern = ["bdx-resolve-project"]' "$RULES_FILE"
grep -Fq 'pattern = ["bdx-plan-frontmatter"]' "$RULES_FILE"
grep -Fq 'pattern = ["bdx-sync-status"]' "$RULES_FILE"

if command -v codex >/dev/null 2>&1; then
  codex execpolicy check --rules "$RULES_FILE" -- bd ready \
    | jq -e '.decision == "allow"' >/dev/null
  codex execpolicy check --rules "$RULES_FILE" -- bdx-resolve-project bd-123 \
    | jq -e '.decision == "allow"' >/dev/null
  codex execpolicy check --rules "$RULES_FILE" -- bdx-plan-frontmatter bd-123 --status open \
    | jq -e '.decision == "allow"' >/dev/null
  codex execpolicy check --rules "$RULES_FILE" -- bdx-sync-status bd-123 \
    | jq -e '.decision == "allow"' >/dev/null
  codex execpolicy check --rules "$RULES_FILE" -- bdx ready \
    | jq -e '.decision != "allow"' >/dev/null
fi

# A Codex allow rule only pre-approves escalation. Every skill that actually
# emits a bd command must also instruct Codex to request host execution, while
# explicitly leaving non-Codex harnesses on their normal path.
BD_COMMAND_PATTERN='(^|[^[:alnum:]_])bd (ready|show|comments|update|close|create|list|search|label|dep|reopen|comment|status|dolt)'
bd_skill_count=0
while IFS= read -r skill_file; do
  bd_skill_count=$((bd_skill_count + 1))
  grep -Fq '## Codex host execution (mandatory)' "$skill_file"
  grep -Fq 'sandbox_permissions: "require_escalated"' "$skill_file"
  grep -Fq 'Claude Code and other non-Codex harnesses must ignore this section' "$skill_file"
done < <(grep -lE "$BD_COMMAND_PATTERN" "$REPO_ROOT"/skills/*/SKILL.md)
test "$bd_skill_count" -gt 0

CLAUDE_ENV_FILE="$TEST_ROOT/claude.env" \
CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/scripts/capture-session-id.sh" <<<'{"session_id":"claude-123"}'
grep -Fqx 'export BDX_SESSION_ID=claude-code:claude-123' "$TEST_ROOT/claude.env"
grep -Fqx 'export CLAUDE_SESSION_ID=claude-123' "$TEST_ROOT/claude.env"

CODEX_CONTEXT=$(PLUGIN_ROOT="$REPO_ROOT" \
  bash "$REPO_ROOT/scripts/capture-session-id.sh" <<<'{"session_id":"codex-456"}')
printf '%s' "$CODEX_CONTEXT" \
  | jq -e '.hookSpecificOutput.additionalContext | contains("codex:codex-456")' >/dev/null

OTHER_CONTEXT=$(BDX_HARNESS=cursor \
  bash "$REPO_ROOT/scripts/capture-session-id.sh" <<<'{"session_id":"other-789"}')
printf '%s' "$OTHER_CONTEXT" \
  | jq -e '.hookSpecificOutput.additionalContext | contains("cursor:other-789")' >/dev/null

FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN" "$TEST_AGENT_HOME/plan" "$TEST_AGENT_HOME/context" "$TEST_AGENT_HOME/summary"
cat > "$FAKE_BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
[ "${1:-}" = "-C" ] || exit 9
shift 2
case "${1:-}" in
  show) printf '[{"status":"%s","title":"Test task"}]\n' "${FAKE_BD_STATUS:-in_progress}" ;;
  comments) printf '%s\n' 'No comments on bd-test' ;;
  update)
    [ -z "${FAKE_BD_UPDATE_LOG:-}" ] || printf '%s\n' update >> "$FAKE_BD_UPDATE_LOG"
    if [ "${FAKE_BD_UPDATE_FAIL:-0}" = 1 ]; then
      echo "simulated update failure" >&2
      exit 9
    fi
    exit 0
    ;;
  *) exit 2 ;;
esac
FAKE_BD
chmod +x "$FAKE_BIN/bd"
cat > "$TEST_AGENT_HOME/plan/bd-test-plan.md" <<'TEST_PLAN'
---
bd: bd-test
sessions: []
---
# Test plan
TEST_PLAN

run_auto_attach() {
  PATH="$FAKE_BIN:$PATH" \
  PLUGIN_ROOT="$REPO_ROOT" \
  BD_ID=bd-test \
  AGENT_HOME="$TEST_AGENT_HOME" \
  FAKE_BD_UPDATE_LOG="${FAKE_BD_UPDATE_LOG:-}" \
    bash "$REPO_ROOT/scripts/bd-auto-attach.sh" \
      <<<'{"session_id":"auto-123","source":"startup"}' >/dev/null
}

FAKE_BD_STATUS=open run_auto_attach
FAKE_BD_STATUS=open run_auto_attach
test "$(grep -Fxc '  - "codex:auto-123"' "$TEST_AGENT_HOME/plan/bd-test-plan.md")" = "1"
grep -Fqx 'status: in_progress' "$TEST_AGENT_HOME/plan/bd-test-plan.md"

cp "$TEST_AGENT_HOME/plan/bd-test-plan.md" "$TEST_AGENT_HOME/plan/bd-test-duplicate.md"
rm -f "$TEST_ROOT/update.log"
if FAKE_BD_STATUS=open FAKE_BD_UPDATE_LOG="$TEST_ROOT/update.log" run_auto_attach \
  2>"$TEST_ROOT/attach-duplicate.err"; then
  echo "expected duplicate plan preflight to abort auto-attach" >&2
  exit 1
fi
grep -Fq 'multiple plans found' "$TEST_ROOT/attach-duplicate.err"
test ! -e "$TEST_ROOT/update.log"
rm -f "$TEST_AGENT_HOME/plan/bd-test-duplicate.md"

if FAKE_BD_STATUS=open FAKE_BD_UPDATE_FAIL=1 run_auto_attach 2>"$TEST_ROOT/attach-failure.err"; then
  echo "expected failed Beads status transition to abort auto-attach" >&2
  exit 1
fi
grep -Fq 'simulated update failure' "$TEST_ROOT/attach-failure.err"
grep -Fqx 'status: open' "$TEST_AGENT_HOME/plan/bd-test-plan.md"

# Uninstall removes only bdx-managed permission entries and preserves user
# configuration. --yes deliberately leaves AGENT_HOME data in place.
cat > "$FAKE_BIN/dolt" <<'FAKE_DOLT'
#!/usr/bin/env bash
exit 0
FAKE_DOLT
cat > "$FAKE_BIN/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
exit 1
FAKE_BREW
cat > "$FAKE_BIN/pgrep" <<'FAKE_PGREP'
#!/usr/bin/env bash
exit 1
FAKE_PGREP
chmod +x "$FAKE_BIN/dolt" "$FAKE_BIN/brew" "$FAKE_BIN/pgrep"
HOME="$TEST_HOME" CODEX_HOME="$TEST_CODEX_HOME" AGENT_HOME="$TEST_AGENT_HOME" \
  PATH="$FAKE_BIN:$PATH" bash "$REPO_ROOT/scripts/uninstall.sh" --yes >/dev/null
jq -e '.theme == "dark"' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow == ["Bash(bd:*)","Bash(existing:*)"]' "$TEST_HOME/.claude/settings.json" >/dev/null
test ! -e "$TEST_HOME/.claude/bdx-managed-permissions.json"
grep -Fqx '# user rule survives' "$RULES_FILE"
! grep -Fq '# BEGIN bdx managed rule' "$RULES_FILE"
test -d "$TEST_AGENT_HOME"

# The destructive validator rejects HOME but accepts a dedicated child.
if HOME="$TEST_HOME" "$REPO_ROOT/scripts/bdx-validate-agent-home-delete" "$TEST_HOME" >/dev/null 2>&1; then
  echo "expected HOME deletion target to be rejected" >&2
  exit 1
fi
CANONICAL_TEST_AGENT_HOME=$(CDPATH= cd -- "$TEST_AGENT_HOME" && pwd -P)
HOME="$TEST_HOME" "$REPO_ROOT/scripts/bdx-validate-agent-home-delete" "$TEST_AGENT_HOME" \
  | grep -Fqx "$CANONICAL_TEST_AGENT_HOME"

# The advertised `curl ... | bash` mode must never source a helper from cwd.
PIPED_CWD="$TEST_ROOT/piped-cwd"
mkdir -p "$PIPED_CWD"
cat > "$PIPED_CWD/bdx-validate-agent-home-delete" <<EOF
printf '%s\n' sourced > "$TEST_ROOT/cwd-helper-sourced"
EOF
(cd "$PIPED_CWD" && HOME="$TEST_HOME" CODEX_HOME="$TEST_CODEX_HOME" \
  AGENT_HOME="$TEST_ROOT/nonexistent-agent-home" PATH="$FAKE_BIN:$PATH" \
  bash -s -- --yes --dry-run < "$REPO_ROOT/scripts/uninstall.sh" >/dev/null)
test ! -e "$TEST_ROOT/cwd-helper-sourced"

printf 'permission and session hook tests passed\n'
