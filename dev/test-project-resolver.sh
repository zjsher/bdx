#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-project-resolver.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
TEST_AGENT_HOME="$TEST_ROOT/agent"
FAKE_BIN="$TEST_ROOT/bin"
ALPHA="$TEST_HOME/repos/alpha"
BETA="$TEST_HOME/repos/beta"
OUTSIDE="$TEST_HOME/outside"
mkdir -p "$TEST_AGENT_HOME/plan" "$FAKE_BIN" "$ALPHA/.test-beads" \
  "$BETA/.test-beads" "$OUTSIDE"
ALPHA=$(CDPATH= cd -- "$ALPHA" && pwd -P)
BETA=$(CDPATH= cd -- "$BETA" && pwd -P)
OUTSIDE=$(CDPATH= cd -- "$OUTSIDE" && pwd -P)

cat > "$FAKE_BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = "-C" ]; then
  project="$2"
  shift 2
else
  project="$PWD"
fi
case "${1:-}" in
  show)
    id="${2:-}"
    [ -f "$project/.test-beads/$id" ] || exit 1
    printf '[{"id":"%s","status":"open","title":"Resolved task"}]\n' "$id"
    ;;
  comments) printf '%s\n' "No comments on ${2:-}" ;;
  update) exit 0 ;;
  *) exit 2 ;;
esac
FAKE_BD
chmod +x "$FAKE_BIN/bd"
cat > "$FAKE_BIN/claude" <<'FAKE_CLAUDE'
#!/usr/bin/env bash
printf '%s|%s|%s|%s\n' "$PWD" "${BD_ID:-}" "${BDX_PROJECT_DIR:-}" "$*"
FAKE_CLAUDE
chmod +x "$FAKE_BIN/claude"

cat > "$TEST_AGENT_HOME/manifest.md" <<EOF
# Projects

## alpha

- **slug**: \`alpha\`
- **path**: \`~/repos/alpha\`

## beta

- **slug**: \`beta\`
- **path**: \`$BETA\`
EOF

resolve() {
  (cd "$OUTSIDE" && env -u BDX_PROJECT_DIR HOME="$TEST_HOME" \
    AGENT_HOME="$TEST_AGENT_HOME" PATH="$FAKE_BIN:$PATH" \
    "$REPO_ROOT/scripts/bdx-resolve-project" "$1")
}

# A plan tag is the normal fast path.
touch "$BETA/.test-beads/bd-plan"
cat > "$TEST_AGENT_HOME/plan/bd-plan-work.md" <<'EOF'
---
bd: bd-plan
tags: [plan, beta, component]
---
# Plan
EOF
test "$(resolve bd-plan)" = "$BETA"

# bdc starts Claude inside the owning repository and carries an authoritative
# project hint into the SessionStart hook.
BDC_OUTPUT=$(cd "$OUTSIDE" && env -u BDX_PROJECT_DIR HOME="$TEST_HOME" \
  AGENT_HOME="$TEST_AGENT_HOME" PATH="$FAKE_BIN:$PATH" \
  "$REPO_ROOT/scripts/bdc" bd-plan --print)
test "$BDC_OUTPUT" = "$BETA|bd-plan|$BETA|-n bd-plan-resolved-task --print"

# With no plan, scan only manifest projects and expand ~/ paths.
touch "$ALPHA/.test-beads/bd-scan"
test "$(resolve bd-scan)" = "$ALPHA"

# An explicit project hint is authoritative.
test "$(cd "$OUTSIDE" && HOME="$TEST_HOME" AGENT_HOME="$TEST_AGENT_HOME" \
  BDX_PROJECT_DIR="$ALPHA" PATH="$FAKE_BIN:$PATH" \
  "$REPO_ROOT/scripts/bdx-resolve-project" bd-scan)" = "$ALPHA"

# Duplicate IDs across per-project databases fail safely.
touch "$ALPHA/.test-beads/bd-dupe" "$BETA/.test-beads/bd-dupe"
if resolve bd-dupe >"$TEST_ROOT/dupe.out" 2>"$TEST_ROOT/dupe.err"; then
  echo "expected ambiguous ID to fail" >&2
  exit 1
fi
grep -Fq 'exists in multiple manifest projects' "$TEST_ROOT/dupe.err"

# Unknown IDs do not fall back to an unrelated project.
if resolve bd-missing >"$TEST_ROOT/missing.out" 2>"$TEST_ROOT/missing.err"; then
  echo "expected missing ID to fail" >&2
  exit 1
fi
grep -Fq 'was not found in any manifest project' "$TEST_ROOT/missing.err"

printf 'per-project Beads resolver tests passed\n'
