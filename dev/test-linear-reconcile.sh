#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/bdx-linear-reconcile-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

AGENT="$TEST_ROOT/agent"
BIN="$TEST_ROOT/bin"
CALLS="$TEST_ROOT/bd-calls"
API_CALLS="$TEST_ROOT/api-calls"
BD_STATE="$TEST_ROOT/bd-state"
mkdir -p "$AGENT/plan" "$AGENT/summary" "$AGENT/context" "$BIN"
printf '%s\n' 'durable plan must not change' > "$AGENT/plan/bd-linked-plan.md"
printf '%s\n' 'durable summary must not change' > "$AGENT/summary/bd-linked-summary.md"
printf '%s\n' 'durable context must not change' > "$AGENT/context/bd-linked-context.md"
BEFORE=$(cksum "$AGENT/plan/bd-linked-plan.md" "$AGENT/summary/bd-linked-summary.md" "$AGENT/context/bd-linked-context.md")

cat > "$BIN/bd" <<'FAKE_BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BDX_TEST_CALLS"
case "${1:-}" in
  version) printf '%s\n' 'bd version 1.2.2 (fixture)' ;;
  config)
    [ "${2:-}" = get ] || exit 80
    case "${3:-}" in
      linear.team_id) printf '%s\n' team-quickflo ;;
      linear.project_id) printf '%s\n' project-quickflo ;;
      linear.api_key) printf '%s\n' supersecret ;;
      *) exit 1 ;;
    esac
    ;;
  info)
    printf '%s\n' 'Beads Database Information' 'Database: /fixture/beads' 'Mode: direct'
    ;;
  list)
    if [ "${BDX_TEST_DUPLICATE_LINKS:-0}" = 1 ]; then
      printf '%s\n' '[
        {"id":"bd-linked","title":"Old title","priority":4,"status":"open","external_ref":"https://linear.app/quickflo/issue/QUI-1/linked"},
        {"id":"bd-duplicate","title":"Duplicate","priority":4,"status":"open","external_ref":"linear:QUI-1"}
      ]'
    else
      if [ -f "$BDX_TEST_BD_STATE" ]; then
        printf '%s\n' '[
          {"id":"bd-linked","title":"New title","priority":0,"status":"in_progress","assignee":"agent","external_ref":"https://linear.app/quickflo/issue/QUI-1/linked"},
          {"id":"bd-unlinked","title":"Local only","priority":2,"status":"open","external_ref":null}'
        if [ "${BDX_TEST_ADD_LINK:-0}" = 1 ]; then
          printf '%s\n' ',{"id":"bd-new","title":"Third","priority":1,"status":"open","external_ref":"linear:QUI-3"}'
        fi
        printf '%s\n' ']'
      else
        printf '%s\n' '[
          {"id":"bd-linked","title":"Old title","priority":4,"status":"open","assignee":"agent","external_ref":"https://linear.app/quickflo/issue/QUI-1/linked"},
          {"id":"bd-unlinked","title":"Local only","priority":2,"status":"open","external_ref":null}
        ]'
      fi
    fi
    ;;
  update|close|reopen) : > "$BDX_TEST_BD_STATE" ;;
  comment)
    [ "${BDX_TEST_COMMENT_FAIL:-0}" != 1 ] || exit 77
    ;;
  *) exit 81 ;;
esac
FAKE_BD
chmod +x "$BIN/bd"

cat > "$BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in *supersecret*) exit 84 ;; esac
  if [ "$1" = --data ]; then payload="$2"; shift 2; else shift; fi
done
[ -n "$payload" ] || exit 82
query=$(jq -r '.query' <<<"$payload")
after=$(jq -r '.variables.after // "first"' <<<"$payload")
since=$(jq -r '.variables.filter.updatedAt.gte // .variables.filter.issue.updatedAt.gte // ""' <<<"$payload")
if [ "${BDX_TEST_API_FAIL:-0}" = 1 ] && [ "$after" = page-2 ]; then exit 85; fi
if grep -q 'issue(id:' <<<"$query"; then
  printf 'issues linked\n' >> "$BDX_TEST_API_CALLS"
  if grep -q 'QUI-3' <<<"$query"; then
    printf '%s\n' '{"data":{"i0":{"id":"linear-1","identifier":"QUI-1","title":"New title","description":"Human description","priority":1,"updatedAt":"2026-08-01T00:00:00.000Z","archivedAt":null,"url":"https://linear.app/quickflo/issue/QUI-1/linked","state":{"name":"In Progress","type":"started"},"assignee":{"id":"user-1","name":"Human Owner"},"team":{"id":"team-quickflo"},"project":{"id":"project-quickflo"}},"i1":{"id":"linear-3","identifier":"QUI-3","title":"Third","description":"Old linked issue","priority":2,"updatedAt":"2026-07-01T00:00:00.000Z","archivedAt":null,"url":"https://linear.app/quickflo/issue/QUI-3/third","state":{"name":"Todo","type":"unstarted"},"assignee":null,"team":{"id":"team-quickflo"},"project":{"id":"project-quickflo"}}}}'
  else
    printf '%s\n' '{"data":{"i0":{"id":"linear-1","identifier":"QUI-1","title":"New title","description":"Human description","priority":1,"updatedAt":"2026-08-01T00:00:00.000Z","archivedAt":null,"url":"https://linear.app/quickflo/issue/QUI-1/linked","state":{"name":"In Progress","type":"started"},"assignee":{"id":"user-1","name":"Human Owner"},"team":{"id":"team-quickflo"},"project":{"id":"project-quickflo"}}}}'
  fi
elif grep -q 'comments(filter' <<<"$query"; then
  ids=$(jq -c '.variables.filter.issue.id.in // []' <<<"$payload")
  printf 'comments %s %s %s\n' "$after" "$since" "$ids" >> "$BDX_TEST_API_CALLS"
  if [ "$ids" = '["linear-3"]' ]; then
    printf '%s\n' '{"data":{"comments":{"nodes":[{"id":"comment-3","body":"Historical note on newly linked issue","createdAt":"2026-07-01T00:00:01.000Z","updatedAt":"2026-07-01T00:00:01.000Z","archivedAt":null,"url":"https://linear.app/comment/comment-3","user":{"name":"Historian"},"externalUser":null,"issue":{"id":"linear-3","identifier":"QUI-3"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  elif [ "${BDX_TEST_COMMENT_VERSION:-1}" = 2 ]; then
    printf '%s\n' '{"data":{"comments":{"nodes":[{"id":"comment-1","body":"Edited human direction","createdAt":"2026-08-01T00:00:02.000Z","updatedAt":"2026-08-02T00:00:00.000Z","archivedAt":null,"url":"https://linear.app/comment/comment-1","user":{"name":"Teammate"},"externalUser":null,"issue":{"id":"linear-1","identifier":"QUI-1"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  elif [ "$since" != '1970-01-01T00:00:00.000Z' ]; then
    printf '%s\n' '{"data":{"comments":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  elif [ "$after" = first ]; then
    printf '%s\n' '{"data":{"comments":{"nodes":[{"id":"comment-1","body":"Please handle the edge case","createdAt":"2026-08-01T00:00:02.000Z","updatedAt":"2026-08-01T00:00:02.000Z","archivedAt":null,"url":"https://linear.app/comment/comment-1","user":{"name":"Teammate"},"externalUser":null,"issue":{"id":"linear-1","identifier":"QUI-1"}}],"pageInfo":{"hasNextPage":true,"endCursor":"page-2"}}}}'
  else
    printf '%s\n' '{"data":{"comments":{"nodes":[{"id":"comment-2","body":"Unlinked discussion","createdAt":"2026-08-01T00:00:03.000Z","updatedAt":"2026-08-01T00:00:03.000Z","archivedAt":null,"url":"https://linear.app/comment/comment-2","user":{"name":"Someone"},"externalUser":null,"issue":{"id":"linear-2","identifier":"QUI-2"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}'
  fi
else
  exit 83
fi
FAKE_CURL
chmod +x "$BIN/curl"

run_linear() {
  PATH="$BIN:$PATH" \
  AGENT_HOME="$AGENT" \
  BDX_TEST_CALLS="$CALLS" \
  BDX_TEST_API_CALLS="$API_CALLS" \
  BDX_TEST_BD_STATE="$BD_STATE" \
  BDX_LINEAR_API_URL='https://fixture.invalid/graphql' \
    "$ROOT/scripts/bdx-linear" "$@"
}

: > "$CALLS"; : > "$API_CALLS"
PREVIEW=$(run_linear reconcile plan)
grep -Fq 'Linear reconciliation preview' <<<"$PREVIEW"
grep -Fq 'bd-linked (QUI-1): status open -> in_progress' <<<"$PREVIEW"
grep -Fq 'bd-linked: 1 new/updated Linear comment(s)' <<<"$PREVIEW"
! grep -Eq '^(update|close|reopen|comment) ' "$CALLS"
[ ! -d "$AGENT/.state" ]
test "$(grep -c '^issues ' "$API_CALLS")" = 1
test "$(grep -c '^comments ' "$API_CALLS")" = 2
grep -Fq '["linear-1"]' "$API_CALLS"
! grep -q 'supersecret' "$CALLS" "$API_CALLS"

: > "$CALLS"; : > "$API_CALLS"
if BDX_TEST_DUPLICATE_LINKS=1 run_linear reconcile plan >"$TEST_ROOT/duplicate.out" 2>"$TEST_ROOT/duplicate.err"; then
  printf 'duplicate external refs unexpectedly allowed\n' >&2
  exit 1
fi
grep -Fq 'duplicate Linear external_ref identifiers: QUI-1' "$TEST_ROOT/duplicate.err"
test ! -s "$API_CALLS"

: > "$CALLS"; : > "$API_CALLS"
APPLY=$(run_linear reconcile once --yes)
grep -Fq 'cursor advanced after all local writes' <<<"$APPLY"
grep -Fqx 'update bd-linked --status in_progress' "$CALLS"
grep -Fqx 'update bd-linked --title New title --priority 0' "$CALLS"
grep -Fq 'comment bd-linked linear inbox: 1 new/updated comment(s)' "$CALLS"
! grep -Eq 'linear (pull|sync)' "$CALLS"
! grep -Eq -- '--description|--assignee|--parent|dep ' "$CALLS"

STATE_ROOT=$(find "$AGENT/.state/linear" -mindepth 1 -maxdepth 1 -type d | head -n 1)
test -f "$STATE_ROOT/cursor.json"
test -f "$STATE_ROOT/issues/bd-linked.json"
test -f "$STATE_ROOT/comments/bd-linked.json"
jq -e '.bd_id == "bd-linked" and .description == "Human description" and .assignee.name == "Human Owner"' "$STATE_ROOT/issues/bd-linked.json" >/dev/null
jq -e '.["comment-1"].body == "Please handle the edge case" and .["comment-1"].version == 1 and .["comment-1"].unread == true' "$STATE_ROOT/comments/bd-linked.json" >/dev/null
! grep -q 'supersecret\|Please handle' "$STATE_ROOT/cursor.json"
! grep -q 'page-2' "$STATE_ROOT/cursor.json"
AFTER=$(cksum "$AGENT/plan/bd-linked-plan.md" "$AGENT/summary/bd-linked-summary.md" "$AGENT/context/bd-linked-context.md")
test "$BEFORE" = "$AFTER"

: > "$CALLS"; : > "$API_CALLS"
run_linear reconcile once --yes >/dev/null
! grep -Eq '^(update|close|reopen|comment) ' "$CALLS"

INBOX=$(run_linear inbox bd-linked)
grep -Fq 'Please handle the edge case' <<<"$INBOX"
grep -Fq '* Teammate' <<<"$INBOX"
printf '%s\n' 'not JSON; target inbox must not scan this bead' > "$STATE_ROOT/comments/bd-other.json"
run_linear inbox bd-linked --json >/dev/null
rm -f "$STATE_ROOT/comments/bd-other.json"
run_linear inbox bd-linked --mark-read >/dev/null
jq -e '.["comment-1"].unread == false' "$STATE_ROOT/comments/bd-linked.json" >/dev/null
if run_linear inbox '../../escape' >"$TEST_ROOT/path.out" 2>"$TEST_ROOT/path.err"; then
  printf 'path-like bead ID unexpectedly allowed\n' >&2
  exit 1
fi
grep -Fq 'invalid bead ID' "$TEST_ROOT/path.err"

: > "$CALLS"; : > "$API_CALLS"
BDX_TEST_COMMENT_VERSION=2 run_linear reconcile once --yes >/dev/null
jq -e '.["comment-1"].body == "Edited human direction" and .["comment-1"].version == 2 and .["comment-1"].unread == true' "$STATE_ROOT/comments/bd-linked.json" >/dev/null
test "$(grep -c '^comment bd-linked linear inbox:' "$CALLS")" = 1

: > "$CALLS"; : > "$API_CALLS"
BDX_TEST_ADD_LINK=1 run_linear reconcile once --yes >/dev/null
grep -Fq 'comments first 1970-01-01T00:00:00.000Z ["linear-3"]' "$API_CALLS"
! grep -Fq '1970-01-01T00:00:00.000Z ["linear-1","linear-3"]' "$API_CALLS"
jq -e '.["comment-3"].body == "Historical note on newly linked issue"' "$STATE_ROOT/comments/bd-new.json" >/dev/null
jq -e '.linked_identifiers == ["QUI-1","QUI-3"]' "$STATE_ROOT/cursor.json" >/dev/null

rm -rf "$AGENT/.state"
: > "$CALLS"; : > "$API_CALLS"
if BDX_TEST_API_FAIL=1 run_linear reconcile once --yes >"$TEST_ROOT/api-fail.out" 2>"$TEST_ROOT/api-fail.err"; then
  printf 'GraphQL page failure unexpectedly succeeded\n' >&2
  exit 1
fi
! grep -Eq '^(update|close|reopen|comment) ' "$CALLS"
[ ! -f "$(find "$AGENT/.state/linear" -name cursor.json -print -quit)" ]

: > "$CALLS"; : > "$API_CALLS"
if BDX_TEST_COMMENT_FAIL=1 run_linear reconcile once --yes >"$TEST_ROOT/partial.out" 2>"$TEST_ROOT/partial.err"; then
  printf 'comment failure unexpectedly succeeded\n' >&2
  exit 1
fi
[ ! -f "$(find "$AGENT/.state/linear" -name cursor.json -print -quit)" ]
[ ! -f "$(find "$AGENT/.state/linear" -path '*/comments/*.json' -print -quit)" ]

: > "$CALLS"; : > "$API_CALLS"
run_linear reconcile once --yes >/dev/null
test "$(grep -c '^comment bd-linked linear inbox:' "$CALLS")" = 1

STATE_ROOT=$(find "$AGENT/.state/linear" -mindepth 1 -maxdepth 1 -type d | head -n 1)
mkdir "$STATE_ROOT/.lock"
printf '%s\n' "$$" > "$STATE_ROOT/.lock/pid"
hostname > "$STATE_ROOT/.lock/host"
date '+%s' > "$STATE_ROOT/.lock/started"
: > "$CALLS"; : > "$API_CALLS"
if run_linear reconcile once --yes >"$TEST_ROOT/locked.out" 2>"$TEST_ROOT/locked.err"; then
  printf 'concurrent reconciliation unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'already running' "$TEST_ROOT/locked.err"
test ! -s "$API_CALLS"

printf '%s\n' 'different-live-host' > "$STATE_ROOT/.lock/host"
printf '%s\n' "$(( $(date '+%s') - 901 ))" > "$STATE_ROOT/.lock/started"
if run_linear reconcile once --yes >"$TEST_ROOT/foreign-lock.out" 2>"$TEST_ROOT/foreign-lock.err"; then
  printf 'foreign-host reconciliation lock unexpectedly stolen\n' >&2
  exit 1
fi
grep -Fq 'lock belongs to host different-live-host' "$TEST_ROOT/foreign-lock.err"
test ! -s "$API_CALLS"
rm -f "$STATE_ROOT/.lock/pid" "$STATE_ROOT/.lock/host" "$STATE_ROOT/.lock/started"
rmdir "$STATE_ROOT/.lock"

: > "$CALLS"
if run_linear reconcile loop --yes --interval 59 >"$TEST_ROOT/interval.out" 2>"$TEST_ROOT/interval.err"; then
  printf 'unsafe poll interval unexpectedly allowed\n' >&2
  exit 1
fi
grep -Fq 'at least 60 seconds' "$TEST_ROOT/interval.err"
test ! -s "$CALLS"

printf 'linear reconciliation tests passed\n'
