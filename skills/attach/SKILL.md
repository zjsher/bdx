---
name: attach
description: >-
  Resume an existing bd-tracked task: load its plan + prior contexts/summaries, append the current harness-qualified session identity to the plan's `sessions:`, and flip bd status to in_progress. Use at the start of a session that's continuing prior work — especially if the prior session was dumped/closed cold and you need state loaded fresh. Skip for ad-hoc bd updates (a bare `bd update --status in_progress` is enough) or for starting brand-new work (use plan instead). Predecessor: plan or scope. Successor: dump (mid-session save) or summarize (when work ships).
---

## Codex host execution (mandatory)

When the harness is Codex, invoke every shell tool call that runs `bd` with `sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set `prefix_rule: ["bd"]`. Run direct `bdx-resolve-project ...` and `bdx-plan-frontmatter ...` calls the same way with their exact command names as `prefix_rule`; the latter writes `$AGENT_HOME`, which is commonly outside the repository sandbox. The installed allow rules only pre-approve escalation—they do not move a default shell call outside the workspace sandbox. Claude Code and other non-Codex harnesses must ignore this section and use their normal execution path.

Tap the current session into an existing bd-tracked task so the agent picks up cold with full task state — plan, prior comments, prior context dumps, prior summaries — and the bd issue moves to in_progress. The counterpart to `plan` / `scope` (which create the task) and `dump` (which records mid-session head-state for a future attach to load).

**Trigger**: starting a session that's continuing prior work tracked in bd. **Skip** if (a) you only need a status flip — a bare `bd update <id> --status in_progress` is lighter, or (b) you're starting brand-new work — use `plan` to open the task first.

## What this skill does (in order)

1. Resolve the bd-id from `$ARGUMENTS`. If missing, ask the user — do not guess.
2. **Resolve the owning project** (read-only): run `bdx-resolve-project <bd-id>`. It checks an explicit `BDX_PROJECT_DIR`, the plan's manifest project tag, the current repo, then manifest project paths. It verifies every candidate with native Beads and returns one absolute path. If no project or multiple projects match, stop and show the resolver error; never guess. In Codex, this wrapper invokes `bd`, so run it with the same host-level escalation required above and use `prefix_rule: ["bdx-resolve-project"]` for the direct wrapper command. Treat the returned path as the active working directory for all subsequent repository and Beads tool calls in this session; shell `cd` state does not persist across tool calls, so set each tool call's working directory explicitly.
3. **Load task state** (read-only first). **Batch these six operations in a single tool-call message — they're independent and sequential execution wastes roundtrips:**
   - `bd -C <project-path> show <bd-id>` — issue details, description, labels, status, blockers
   - `bd -C <project-path> comments <bd-id>` — all prior comments (these contain links to summaries/contexts from summarize / dump)
   - Find the plan: `ls $AGENT_HOME/plan/<bd-id>-*.md` (typically one match)
   - Find prior context dumps: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/context"/*.md 2>/dev/null`
   - Find prior summaries: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md 2>/dev/null`
   - Read `$AGENT_HOME/manifest.md`

   Then (once the first batch returns) batch a second round:
   - Read the plan file end-to-end
   - Read the most recent context dump (if any) end-to-end
   - Skim summaries

   **Look up the project** in the manifest using the project label from `bd show` — pull `path`, `type`, and `notes` for the briefing. If the project isn't in the manifest, flag it.
4. **Resolve the session identity** (no mutation yet): prefer `$BDX_SESSION_ID`; otherwise use the exact `bdx-session-id` value injected by SessionStart; otherwise prefix a non-empty `$CLAUDE_SESSION_ID` as `claude-code:<id>`.
5. **Update bd status**: if the issue is `open`, run `bd -C <project-path> update <bd-id> --status in_progress` and fail honestly if it does not succeed. If already `in_progress`, `blocked`, `deferred`, or `closed`, leave it alone. If `closed`, warn the user and ask whether to `bd -C <project-path> reopen` before continuing.
6. **Project live frontmatter**: call `bdx-plan-frontmatter <bd-id> --status <verified-current-status>` and, when an identity exists, add `--session <identity>` to the same command. This locked, atomic script owns `status:` and `sessions:` updates; never hand-edit either field. If it fails, report the exact error rather than claiming attachment succeeded.
7. **Brief the user**: print a concise summary covering:
   - Project blurb from the manifest (path + 1-line description) — so you remember what this project is
   - Title, status, priority, labels
   - Plan path + 3–5 line overview of the goal/scope (not the full plan)
   - Last 2–3 bd comments (newest first)
   - Paths to the most recent context dump and summary if they exist
   - Next uncompleted checkbox from the plan, if applicable ("Pick up at: <step>")
8. Report one line: `Attached to <bd-id> (<title>) — project: <project-path> — plan: <path>`.

## Rules

- **Read before mutate.** Steps 2–4 are entirely read-only. Only steps 5–6 write.
- **Don't re-plan.** If the plan feels stale or wrong, do NOT overwrite it — flag it to the user and let them decide whether to `plan` a new task or edit the existing plan manually. Plans are append-only in spirit.
- **Don't dump context here.** attach only reads. Use `dump` separately if you want to snapshot current state before continuing.
- **Don't close or comment on the bd issue.** Attaching is a load operation, not a status broadcast. The only state change is `open → in_progress`.
- **Ambiguous bd-id**: if the user passed a slug instead of a bd-id, search projects from the manifest and present matches; don't auto-pick.
- **Project-aware Beads**: after resolution, every Beads command in this workflow must use `bd -C <project-path>`. Do not rely on a global `BEADS_DIR` or whichever repo happens to be the shell's current directory.
- **One status authority.** Beads is authoritative; plan `status:` is a deterministic projection refreshed by `bdx-plan-frontmatter` / `bdx-sync-status`. Context dumps and summaries are historical artifacts and are never rewritten to mirror live status.
- **Preserve all other frontmatter.** The deterministic writer may change only `status:` and `sessions:`. Every other key and all body content must round-trip untouched.

## Process

1. Resolve bd-id from `$ARGUMENTS`; ask if missing.
2. Run `bdx-resolve-project <bd-id>` and stop safely if it does not return exactly one project.
3. **Single batched message** — run in parallel: `bd -C <project-path> show`, `bd -C <project-path> comments`, `ls plan`, `grep contexts`, `grep summaries`, read manifest.
4. **Second batched message** — run in parallel: read plan file, read most recent context, skim summaries.
5. Resolve the bdx session identity using the rule above.
6. If bd status is `open`, `bd -C <project-path> update <bd-id> --status in_progress`; fail honestly on error. If `closed`, warn + prompt.
7. Run `bdx-plan-frontmatter <bd-id> --status <verified-current-status> [--session <identity>]`.
8. Print the briefing (title, status, plan overview, recent comments, next step).
9. Report the one-line confirmation.
