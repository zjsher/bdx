#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-orchestration.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

COMMAND="${BDX_PLAN_ORCHESTRATION_COMMAND:-$ROOT/scripts/bdx-plan-orchestration}"
PLAN="$TEST_ROOT/plan.md"
SPEC="$TEST_ROOT/spec.json"

cat > "$PLAN" <<'EOF'
---
bd: bd-test
status: in_progress
sessions: []
custom: preserve-me
---

# Test plan

## Plan

### Phase 1 — Foundation

- [ ] Build it.

## Key decisions (already made)

- Preserve this prose.

## Verification

Keep this too.
EOF

cat > "$SPEC" <<'EOF'
{
  "max_parallel": 1,
  "phases": [
    {
      "id": "policy-contract",
      "title": "Settle policy",
      "prepare": [{"skill": "bdx:care"}],
      "run": {
        "kind": "skill",
        "skill": "codebase-design",
        "with": {"prompt": "settle the payer seam"}
      },
      "completion": {
        "acceptance": ["Policy matrix is recorded"],
        "approval": "human"
      }
    },
    {
      "id": "foundation",
      "title": "Build the seam",
      "needs": ["policy-contract"],
      "run": {
        "kind": "skill",
        "skill": "bdx:build-loop",
        "with": {"bead": "bd-test", "phase": 1}
      },
      "completion": {
        "checks": [{"run": "make test", "timeout": "10m"}],
        "approval": "none"
      }
    }
  ],
  "finish": {
    "on_success": [
      {"skill": "bdx:quality-audit"},
      {"skill": "bdx:summarize"},
      {"skill": "bdx:close"}
    ],
    "on_failure": [{"skill": "bdx:dump"}]
  }
}
EOF

RENDERED="$TEST_ROOT/rendered.md"
"$COMMAND" render --spec "$SPEC" > "$RENDERED"
grep -Fqx '## Orchestration' "$RENDERED"
grep -Fqx 'api_version: "bdx.dev/orchestration/v1"' "$RENDERED"
grep -Fqx '  max_parallel: 1' "$RENDERED"
grep -Fqx '  - id: "policy-contract"' "$RENDERED"
grep -Fqx '  - id: "foundation"' "$RENDERED"
grep -Fqx '        bead: "bd-test"' "$RENDERED"
grep -Fqx '        phase: 1' "$RENDERED"
grep -Fqx '        - run: "make test"' "$RENDERED"

cp "$PLAN" "$TEST_ROOT/plan.before"
"$COMMAND" apply --plan "$PLAN" --spec "$SPEC" >/dev/null
test "$(grep -Fxc '## Orchestration' "$PLAN")" = 1
grep -Fqx 'custom: preserve-me' "$PLAN"
grep -Fqx -- '- Preserve this prose.' "$PLAN"
grep -Fqx 'Keep this too.' "$PLAN"
grep -Fqx 'api_version: "bdx.dev/orchestration/v1"' "$PLAN"

# Re-applying replaces the block instead of duplicating it.
sed 's/Build the seam/Build the stable seam/' "$SPEC" > "$TEST_ROOT/spec-updated.json"
"$COMMAND" apply --plan "$PLAN" --spec "$TEST_ROOT/spec-updated.json" >/dev/null
test "$(grep -Fxc '## Orchestration' "$PLAN")" = 1
grep -Fqx '    title: "Build the stable seam"' "$PLAN"
! grep -Fq '    title: "Build the seam"' "$PLAN"

expect_invalid() {
  name="$1"
  expected="$2"
  spec="$TEST_ROOT/$name.json"
  if "$COMMAND" render --spec "$spec" > "$TEST_ROOT/$name.out" 2> "$TEST_ROOT/$name.err"; then
    echo "expected invalid spec to fail: $name" >&2
    exit 1
  fi
  grep -Fq "$expected" "$TEST_ROOT/$name.err"
}

jq '.phases[1].id = "policy-contract"' "$SPEC" > "$TEST_ROOT/duplicate.json"
expect_invalid duplicate 'phase ids must be unique'

jq '.phases[1].needs = ["missing"]' "$SPEC" > "$TEST_ROOT/missing.json"
expect_invalid missing 'phase has an unknown dependency'

jq '.phases[0].needs = ["foundation"]' "$SPEC" > "$TEST_ROOT/cycle.json"
expect_invalid cycle 'phase dependency graph contains a cycle'

jq '.phases[1].run = {"kind":"skill","skill":"bad skill"}' "$SPEC" \
  > "$TEST_ROOT/runner.json"
expect_invalid runner 'invalid phase contract'

jq '.finish.on_success += [{"skill":"bdx:quality-audit"}]' "$SPEC" \
  > "$TEST_ROOT/close-order.json"
expect_invalid close-order 'bdx:close must appear at most once and last'

# Validation happens before mutation.
cp "$PLAN" "$TEST_ROOT/plan.valid"
if "$COMMAND" apply --plan "$PLAN" --spec "$TEST_ROOT/cycle.json" >/dev/null 2>&1; then
  echo "expected invalid apply to fail" >&2
  exit 1
fi
cmp "$PLAN" "$TEST_ROOT/plan.valid"

# Timing out behind another whole-plan writer must not remove its lock.
mkdir "$PLAN.bdx-lock"
printf 'other-writer\n' > "$PLAN.bdx-lock/pid"
if BDX_PLAN_ORCHESTRATION_LOCK_ATTEMPTS=2 \
  "$COMMAND" apply --plan "$PLAN" --spec "$SPEC" >/dev/null 2>&1; then
  echo "expected contended plan lock to time out" >&2
  exit 1
fi
test -d "$PLAN.bdx-lock"
grep -Fqx 'other-writer' "$PLAN.bdx-lock/pid"
rm "$PLAN.bdx-lock/pid"
rmdir "$PLAN.bdx-lock"

# Ambiguous targets fail safely.
printf '\n## Orchestration\n\n```yaml\nkind: duplicate\n```\n' >> "$PLAN"
if "$COMMAND" apply --plan "$PLAN" --spec "$SPEC" >/dev/null 2>&1; then
  echo "expected duplicate Orchestration sections to fail" >&2
  exit 1
fi

printf 'plan orchestration tests passed\n'
