#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-permissions.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
TEST_CODEX_HOME="$TEST_ROOT/codex-home"
mkdir -p "$TEST_HOME/.claude" "$TEST_CODEX_HOME/rules"

printf '%s\n' '{"theme":"dark","permissions":{"allow":["Bash(existing:*)"]}}' > "$TEST_HOME/.claude/settings.json"
printf '%s\n' '# user rule survives' > "$TEST_CODEX_HOME/rules/bdx.rules"

run_installer() {
  HOME="$TEST_HOME" \
  CODEX_HOME="$TEST_CODEX_HOME" \
  SHELL=/bin/bash \
    bash "$REPO_ROOT/scripts/install.sh" --yes --skip-env --skip-bd \
      --skip-dolt --skip-init --skip-templates >/dev/null
}

run_installer
run_installer

jq -e '.theme == "dark"' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(existing:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null
jq -e '.permissions.allow | index("Bash(bd:*)") != null' "$TEST_HOME/.claude/settings.json" >/dev/null

RULES_FILE="$TEST_CODEX_HOME/rules/bdx.rules"
test "$(grep -Fxc '# BEGIN bdx managed rule' "$RULES_FILE")" = "1"
grep -Fqx '# user rule survives' "$RULES_FILE"
grep -Fq 'pattern = ["bd"]' "$RULES_FILE"

if command -v codex >/dev/null 2>&1; then
  codex execpolicy check --rules "$RULES_FILE" -- bd ready \
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
TEST_AGENT_HOME="$TEST_ROOT/agent-home"
mkdir -p "$FAKE_BIN" "$TEST_AGENT_HOME/plan" "$TEST_AGENT_HOME/context" "$TEST_AGENT_HOME/summary"
cat > "$FAKE_BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
case "${1:-}" in
  show) printf '%s\n' '[{"status":"in_progress","title":"Test task"}]' ;;
  comments) printf '%s\n' 'No comments on bd-test' ;;
  update) exit 0 ;;
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
    bash "$REPO_ROOT/scripts/bd-auto-attach.sh" \
      <<<'{"session_id":"auto-123","source":"startup"}' >/dev/null
}

run_auto_attach
run_auto_attach
test "$(grep -Fxc '  - "codex:auto-123"' "$TEST_AGENT_HOME/plan/bd-test-plan.md")" = "1"

printf 'permission and session hook tests passed\n'
