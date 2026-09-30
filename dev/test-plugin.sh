#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for manifest in \
  .claude-plugin/plugin.json \
  .codex-plugin/plugin.json \
  .claude-plugin/marketplace.json \
  .agents/plugins/marketplace.json; do
  jq -e . "$manifest" >/dev/null || fail "invalid JSON: $manifest"
done

CLAUDE_VERSION=$(jq -r .version .claude-plugin/plugin.json)
CODEX_VERSION=$(jq -r .version .codex-plugin/plugin.json)
[ "$CLAUDE_VERSION" = "$CODEX_VERSION" ] || \
  fail "plugin versions differ: Claude=$CLAUDE_VERSION Codex=$CODEX_VERSION"

EXPECTED_SKILLS='attach
build-loop
care
check
close
dump
label
manifest
persona
plan
quality-audit
reconcile
scope
skeleton
slice
slice-loop
slice-review
summarize
triage'

ACTUAL_SKILLS=$(find skills -mindepth 1 -maxdepth 1 -type d \
  -exec test -f '{}/SKILL.md' ';' -print | sed 's#^skills/##' | sort)
[ "$ACTUAL_SKILLS" = "$EXPECTED_SKILLS" ] || {
  echo "Expected skills:" >&2
  echo "$EXPECTED_SKILLS" >&2
  echo "Actual skills:" >&2
  echo "$ACTUAL_SKILLS" >&2
  fail "skill surface drifted"
}

for skill_file in skills/*/SKILL.md; do
  skill_frontmatter=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$skill_file")
  case "$skill_frontmatter" in
    *"Opt-in BDX only"*) ;;
    *) fail "skill is missing the BDX opt-in routing gate: $skill_file" ;;
  esac
done

for required in \
  hooks/hooks.json \
  scripts/bd-auto-attach.sh \
  scripts/bdx-resolve-project \
  scripts/bdx-plan-frontmatter \
  scripts/bdx-plan-orchestration \
  scripts/bdx-sync-status \
  scripts/bdx-validate-agent-home-delete \
  scripts/bdx-ensure-agent-home.sh \
  scripts/bdx-note \
  scripts/block-bare-bd-close.sh \
  scripts/block-bd-narrative-writes.sh \
  scripts/install.sh \
  scripts/uninstall.sh \
  examples/manifest.md; do
  [ -f "$required" ] || fail "missing restored lifecycle file: $required"
done

rg -q 'plan → attach → build-loop → close' README.md || \
  fail "README no longer documents the attach lifecycle"
rg -q '\$AGENT_HOME/plan/' skills/attach/SKILL.md || \
  fail "attach no longer loads the durable Markdown plan"
rg -q 'bdx-resolve-project' skills/attach/SKILL.md || \
  fail "attach no longer resolves per-project Beads databases"
! rg -q 'remove \\$BEADS_DIR|rm -rf.*beads_dir' scripts/uninstall.sh || \
  fail "uninstaller must not offer to delete Beads project data"
rg -q 'bdx-validate-agent-home-delete' scripts/uninstall.sh || \
  fail "uninstaller no longer validates AGENT_HOME before recursive deletion"

# Source the real SessionStart output as a subsequent Bash tool call would.
# Values must survive shell parsing without expansion or an initialization error.
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-session-env.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
for agent_home in \
  "$TEST_ROOT/agent" \
  "$TEST_ROOT/My Drive/main/notes/agent" \
  "$TEST_ROOT/"'quotes" $HOME $(false) `false` back\slash'; do
  env_file="$TEST_ROOT/claude.env"
  : > "$env_file"
  AGENT_HOME="$agent_home" CLAUDE_ENV_FILE="$env_file" \
    bash scripts/bdx-ensure-agent-home.sh
  bash -eu -c '
    unset AGENT_HOME
    source "$1"
    test "$AGENT_HOME" = "$2"
    test "$PATH" = "$3:$4"
    for directory in plan context summary inbox; do
      test -d "$AGENT_HOME/$directory"
    done
  ' bash "$env_file" "$agent_home" "$ROOT/scripts" "$PATH" || \
    fail "session environment did not preserve AGENT_HOME: $agent_home"
done

echo "legacy Markdown-backed plugin tests passed"
