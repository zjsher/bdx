#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-frontmatter.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

TEST_HOME="$TEST_ROOT/home"
AGENT="$TEST_ROOT/agent"
PROJECT="$TEST_ROOT/project"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$TEST_HOME" "$AGENT/plan" "$AGENT/context" "$AGENT/summary" \
  "$PROJECT/.fake-beads" "$FAKE_BIN"
PROJECT=$(CDPATH= cd -- "$PROJECT" && pwd -P)

cat > "$AGENT/manifest.md" <<EOF
# Projects

## demo

- **slug**: \`demo\`
- **path**: \`$PROJECT\`
EOF

PLAN="$AGENT/plan/bd-meta-live-plan.md"
cat > "$PLAN" <<'EOF'
---
bd: bd-meta
kind: agent-note
tags: [plan, demo]
status: draft
sessions: []
custom: preserve-me
---
# Live plan

Body content must remain byte-for-byte stable.
EOF

cat > "$AGENT/context/bd-meta-history.md" <<'EOF'
---
bd: bd-meta
status_at_write: open
---
historical context
EOF
cp "$AGENT/context/bd-meta-history.md" "$TEST_ROOT/context.before"

cat > "$FAKE_BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
set -eu
[ "${1:-}" = "-C" ] || exit 9
project="$2"
shift 2
case "${1:-}" in
  show)
    id="$2"
    status=$(sed -n '1p' "$project/.fake-beads/$id")
    printf '[{"id":"%s","status":"%s","title":"Metadata task"}]\n' "$id" "$status"
    ;;
  *) exit 2 ;;
esac
FAKE_BD
chmod +x "$FAKE_BIN/bd"

run_meta() {
  HOME="$TEST_HOME" AGENT_HOME="$AGENT" \
    "$REPO_ROOT/scripts/bdx-plan-frontmatter" "$@" >/dev/null
}

run_sync() {
  HOME="$TEST_HOME" AGENT_HOME="$AGENT" PATH="$FAKE_BIN:$PATH" \
    "$REPO_ROOT/scripts/bdx-sync-status" "$@" >/dev/null
}

# Scalar status and list membership update together, without touching custom
# frontmatter or body content.
run_meta bd-meta --status open --session codex:first
grep -Fqx 'status: open' "$PLAN"
grep -Fqx '  - "codex:first"' "$PLAN"
grep -Fqx 'custom: preserve-me' "$PLAN"
grep -Fqx 'Body content must remain byte-for-byte stable.' "$PLAN"

# Status-only projection preserves an explicitly empty YAML list.
EMPTY_PLAN="$AGENT/plan/bd-empty-plan.md"
cat > "$EMPTY_PLAN" <<'EOF'
---
bd: bd-empty
status: draft
sessions: []
---
# Empty sessions
EOF
run_meta bd-empty --status closed
grep -Fqx 'sessions: []' "$EMPTY_PLAN"

# Repeated appends are idempotent.
run_meta bd-meta --session codex:first
test "$(grep -Fxc '  - "codex:first"' "$PLAN")" = "1"
run_meta bd-meta --session codex:first-long
test "$(grep -Fxc '  - "codex:first"' "$PLAN")" = "1"
test "$(grep -Fxc '  - "codex:first-long"' "$PLAN")" = "1"

if run_meta bd-meta --session 'codex:bad value' 2>"$TEST_ROOT/session.err"; then
  echo "expected unsafe session identity to fail" >&2
  exit 1
fi
grep -Fq 'invalid session identity' "$TEST_ROOT/session.err"

# Concurrent attaches serialize, so every session identity survives.
pids=()
for n in $(seq 1 20); do
  HOME="$TEST_HOME" AGENT_HOME="$AGENT" \
    "$REPO_ROOT/scripts/bdx-plan-frontmatter" bd-meta --session "codex:race-$n" >/dev/null &
  pids+=("$!")
done

# Narrative appends and frontmatter writes share the same lock, so neither
# whole-file transform loses the other's update.
pids=()
for n in $(seq 1 12); do
  HOME="$TEST_HOME" AGENT_HOME="$AGENT" \
    "$REPO_ROOT/scripts/bdx-plan-frontmatter" bd-meta --status in_progress \
      --session "codex:mixed-$n" >/dev/null &
  pids+=("$!")
  HOME="$TEST_HOME" AGENT_HOME="$AGENT" \
    "$REPO_ROOT/scripts/bdx-note" -q bd-meta "mixed-note-$n" &
  pids+=("$!")
done
worker_failed=0
for pid in "${pids[@]}"; do wait "$pid" || worker_failed=1; done
test "$worker_failed" = 0
for n in $(seq 1 12); do
  grep -Fqx "  - \"codex:mixed-$n\"" "$PLAN"
  grep -Fq "mixed-note-$n" "$PLAN"
done
worker_failed=0
for pid in "${pids[@]}"; do wait "$pid" || worker_failed=1; done
test "$worker_failed" = 0
for n in $(seq 1 20); do
  test "$(grep -Fxc "  - \"codex:race-$n\"" "$PLAN")" = "1"
done

# An external Beads transition is repaired by explicit one-way projection.
printf '%s\n' open > "$PROJECT/.fake-beads/bd-meta"
run_sync bd-meta
grep -Fqx 'status: open' "$PLAN"
printf '%s\n' closed > "$PROJECT/.fake-beads/bd-meta"
run_sync bd-meta
grep -Fqx 'status: closed' "$PLAN"
cmp -s "$TEST_ROOT/context.before" "$AGENT/context/bd-meta-history.md"

# Ambiguous plans fail without changing either file.
cp "$PLAN" "$AGENT/plan/bd-meta-duplicate.md"
cp "$PLAN" "$TEST_ROOT/plan.before"
if run_meta bd-meta --status open 2>"$TEST_ROOT/ambiguous.err"; then
  echo "expected ambiguous plan lookup to fail" >&2
  exit 1
fi
grep -Fq 'multiple plans found' "$TEST_ROOT/ambiguous.err"
cmp -s "$TEST_ROOT/plan.before" "$PLAN"

# Unsupported inline non-empty lists fail rather than creating duplicate YAML.
rm -f "$AGENT/plan/bd-meta-duplicate.md"
sed 's/^sessions:$/sessions: ["codex:inline"]/' "$PLAN" > "$AGENT/plan/bd-inline-plan.md"
if run_meta bd-inline --session codex:new 2>"$TEST_ROOT/inline.err"; then
  echo "expected inline non-empty sessions to fail safely" >&2
  exit 1
fi
grep -Fq 'malformed or unsupported frontmatter' "$TEST_ROOT/inline.err"

printf 'deterministic plan frontmatter tests passed\n'
