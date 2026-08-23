#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-linear-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

AGENT="$TEST_ROOT/agent"
BIN="$TEST_ROOT/bin"
CALLS="$TEST_ROOT/bd-calls"
mkdir -p "$AGENT/plan" "$AGENT/summary" "$AGENT/context" "$BIN"

artifact() {
  local path="$1" bd="$2" privacy="${3-__missing__}"
  {
    printf '%s\n' '---'
    [ "$bd" = "__missing__" ] || printf 'bd: %s\n' "$bd"
    [ "$privacy" = "__missing__" ] || printf 'private: %s\n' "$privacy"
    printf '%s\n\n# Fixture\n' '---'
  } > "$path"
}

artifact "$AGENT/plan/bd-public-plan.md" bd-public false
artifact "$AGENT/summary/bd-public-summary.md" bd-public false
artifact "$AGENT/summary/bd-private-summary.md" bd-private true
artifact "$AGENT/summary/bd-legacy-summary.md" bd-legacy
artifact "$AGENT/summary/orphan-summary.md" none false
artifact "$AGENT/summary/no-bd-summary.md" __missing__ false
artifact "$AGENT/context/bd-public-context.md" bd-public false
artifact "$AGENT/plan/bd-invalid-plan.md" bd-invalid maybe
artifact "$AGENT/plan/null-id.md" null false
cat > "$AGENT/plan/duplicate-privacy.md" <<'DUPLICATE'
---
bd: bd-private
private: false
private: true
---
# Duplicate privacy must fail closed
DUPLICATE
cat > "$AGENT/plan/quoted-private.md" <<'QUOTED_PRIVATE'
---
bd: bd-private
"private": true
private: false
---
# Quoted duplicate key must fail closed
QUOTED_PRIVATE
cat > "$AGENT/plan/spaced-private.md" <<'SPACED_PRIVATE'
---
bd: bd-private
private : true
private: false
---
# Spaced duplicate key must fail closed
SPACED_PRIVATE
cat > "$AGENT/plan/quoted-null-bd.md" <<'QUOTED_BD'
---
"bd": null
bd: bd-valid
private: false
---
# Quoted duplicate identity must fail closed
QUOTED_BD
cat > "$AGENT/plan/tagged-private.md" <<'TAGGED_PRIVATE'
---
bd: bd-private
!!str private: true
private: false
---
TAGGED_PRIVATE
cat > "$AGENT/plan/anchored-private.md" <<'ANCHORED_PRIVATE'
---
bd: bd-private
&privacy private: true
private: false
---
ANCHORED_PRIVATE
cat > "$AGENT/plan/escaped-private.md" <<'ESCAPED_PRIVATE'
---
bd: bd-private
"pr\u0069vate": true
private: false
---
ESCAPED_PRIVATE
cat > "$AGENT/plan/tagged-null-bd.md" <<'TAGGED_BD'
---
!!str bd: null
bd: bd-valid
private: false
---
TAGGED_BD
cat > "$AGENT/plan/indented-private.md" <<'INDENTED_PRIVATE'
---
  private: true
bd: bd-valid
private: false
---
INDENTED_PRIVATE
cat > "$AGENT/plan/indented-null-bd.md" <<'INDENTED_BD'
---
  bd: null
bd: bd-valid
private: false
---
INDENTED_BD
cat > "$AGENT/plan/nested-metadata.md" <<'NESTED_METADATA'
---
bd: bd-nested
private: false
sessions:
  - "codex:test-session"
---
NESTED_METADATA

cat > "$BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BDX_TEST_CALLS"
case "${1:-}" in
  version)
    printf 'bd version %s (fixture)\n' "${BDX_TEST_VERSION:-1.2.2}"
    ;;
  linear)
    [ "${2:-}" = status ] && [ "${3:-}" = --json ] || exit 90
    printf '%s\n' '{"configured":true,"has_api_key":true,"pending_push":7,"team_id":"team-fixture","api_key":"supersecret"}'
    ;;
  *) exit 91 ;;
esac
FAKE_BD
chmod +x "$BIN/bd"

run_status() {
  PATH="$BIN:$PATH" \
  AGENT_HOME="$AGENT" \
  BDX_TEST_CALLS="$CALLS" \
  BDX_TEST_VERSION="${1:-1.2.2}" \
    "$ROOT/scripts/bdx-linear" status --json
}

: > "$CALLS"
RESULT=$(run_status)

jq -e '.bd.version == "1.2.2" and .bd.mutation_ready == true' <<<"$RESULT" >/dev/null
jq -e '.linear.configured == true and .linear.available == true' <<<"$RESULT" >/dev/null
jq -e '.linear.api_key == null' <<<"$RESULT" >/dev/null
jq -e '.artifacts.total == 20' <<<"$RESULT" >/dev/null
jq -e '.artifacts.publishable | length == 3' <<<"$RESULT" >/dev/null
jq -e '[.artifacts.publishable[].kind] | sort == ["plan","plan","summary"]' <<<"$RESULT" >/dev/null
jq -e '.artifacts.exclusions == {context_requires_opt_in:1,duplicate_privacy:1,invalid_bd:2,invalid_privacy:1,missing_bd:1,missing_privacy:1,noncanonical_frontmatter:9,private:1}' <<<"$RESULT" >/dev/null
! grep -q 'supersecret' <<<"$RESULT"

test "$(grep -Fxc 'version' "$CALLS")" = 1
test "$(grep -Fxc 'linear status --json' "$CALLS")" = 1
! grep -Eq 'sync|push|pull' "$CALLS"

: > "$CALLS"
OLD=$(run_status 1.0.2)
jq -e '.bd.version == "1.0.2" and .bd.mutation_ready == false' <<<"$OLD" >/dev/null

HUMAN=$(PATH="$BIN:$PATH" AGENT_HOME="$AGENT" BDX_TEST_CALLS="$CALLS" BDX_TEST_VERSION=1.0.2 \
  "$ROOT/scripts/bdx-linear" status)
grep -Fq 'mutation blocked; requires >= 1.2.2' <<<"$HUMAN"
grep -Fq '3 publishable · 17 excluded · 20 total' <<<"$HUMAN"
grep -Fq 'No Linear mutations were attempted.' <<<"$HUMAN"
! grep -q 'supersecret' <<<"$HUMAN"

printf 'linear projection tests passed\n'
