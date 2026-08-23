#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for manifest in .claude-plugin/plugin.json .codex-plugin/plugin.json \
  .claude-plugin/marketplace.json .agents/plugins/marketplace.json; do
  jq -e . "$manifest" >/dev/null || fail "invalid JSON: $manifest"
done

claude_version=$(jq -r '.version' .claude-plugin/plugin.json)
codex_version=$(jq -r '.version' .codex-plugin/plugin.json)
test "$claude_version" = "$codex_version" || fail "plugin versions differ"

actual_skills=$(
  for path in skills/*/SKILL.md; do
    test -f "$path" || continue
    basename "$(dirname "$path")"
  done | sort
)
expected_skills=$(printf '%s\n' build-loop close dump plan quality-audit render)
test "$actual_skills" = "$expected_skills" || {
  printf 'expected skills:\n%s\nactual skills:\n%s\n' \
    "$expected_skills" "$actual_skills" >&2
  exit 1
}

for skill in build-loop close dump plan quality-audit render; do
  file="skills/$skill/SKILL.md"
  test -f "$file" || fail "missing $file"
  grep -Fqx -- '---' "$file" || fail "missing frontmatter: $file"
  grep -Fq "name: $skill" "$file" || fail "wrong skill name: $file"
done

for skill in close dump plan render; do
  file="skills/$skill/SKILL.md"
  grep -Fq "Use when the user invokes /bdx:$skill" "$file" || \
    fail "thin skill must have a narrow invocation pointer: $file"
  grep -Fq 'official Beads skill' "$file" || \
    fail "thin skill must delegate to official Beads: $file"
  grep -Fq '`bd prime`' "$file" || \
    fail "thin skill must defer to current Beads guidance: $file"
  grep -Fq 'allow_implicit_invocation: false' \
    "skills/$skill/agents/openai.yaml" || \
    fail "thin skill must require explicit Codex invocation: $file"
done

grep -Fq 'read-only projection' skills/render/SKILL.md
grep -Fq 'OS temp directory' skills/render/SKILL.md
grep -Fq 'must not mutate' skills/render/SKILL.md

test ! -f hooks/hooks.json || fail "plugin hooks must not exist"
if find scripts -type f -print 2>/dev/null | grep -q .; then
  fail "plugin scripts must not exist"
fi
if find examples -type f -print 2>/dev/null | grep -q .; then
  fail "Markdown artifact examples must not exist"
fi
if find . -path ./.git -prune -o -path ./.beads -prune -o -type f \
    \( -iname '*linear*' -o -iname '*jira*' -o -iname '*github*' \
       -o -iname '*gitlab*' -o -iname '*notion*' -o -iname '*ado*' \) \
    -print | grep -q .; then
  fail "tracker-specific files remain"
fi

grep -Fq 'Add implementation discipline to one Bead' skills/build-loop/SKILL.md
grep -Fq 'official Beads skill owns' skills/build-loop/SKILL.md
grep -Fq '`bd prime` as the source of' skills/build-loop/SKILL.md
grep -Fq '/bdx:quality-audit light' skills/build-loop/SKILL.md

if grep -Eq 'bd (ready|show|comments|update|close|create|list|search|label|dep|reopen|comment|status|dolt|note|remember)' \
    skills/build-loop/SKILL.md; then
  fail "build-loop duplicates native Beads lifecycle commands"
fi

if grep -Eq 'bdx:(attach|plan|check|dump|close|render|summarize|scope|triage|reconcile|label|manifest|persona|slice)' \
    skills/build-loop/SKILL.md; then
  fail "build-loop must remain independent of bdx lifecycle entry points"
fi

if grep -R '\$AGENT_HOME' skills .claude-plugin .codex-plugin \
    .agents/plugins >/dev/null 2>&1; then
  fail "AGENT_HOME dependency remains in the shipped plugin"
fi

grep -Fq 'integration-agnostic' README.md
grep -Fq 'official skill' README.md
grep -Fq '`bd prime`' README.md
grep -Fq 'plan, dump, close, render, build-loop, and quality-audit' \
  .claude-plugin/marketplace.json
test "$(jq '.interface.defaultPrompt | length' .codex-plugin/plugin.json)" = 3

bash -n dev/release.sh dev/test-native-plugin.sh
test "$(./dev/release.sh current)" = "$claude_version"

printf 'native Beads plugin tests passed\n'
