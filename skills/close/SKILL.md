---
name: close
description: >-
  Finalize a bd task — ensure a summary exists (auto-running summarize if not), then `bd close` with a one-line resolution. Accepts summarize's --personas / --deep flags and passes them through. Use when the work is actually done and you're ready to retire the issue from the active queue. Skip if there's still real follow-up work — keep the bd open. Predecessor: summarize (close runs it implicitly if missing). Successor: terminal — close ends the lifecycle.
---

## Codex host execution (mandatory)

When the harness is Codex, invoke every shell tool call that runs `bd` with `sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set `prefix_rule: ["bd"]`. Run direct `bdx-resolve-project ...`, `bdx-plan-frontmatter ...`, and `bdx-sync-status ...` calls the same way with their exact command names as `prefix_rule`; the frontmatter writer targets `$AGENT_HOME`, which is commonly outside the repository sandbox. The installed allow rules only pre-approve escalation; they do not move a default shell call outside the workspace sandbox. Claude Code and other non-Codex harnesses must ignore this section and use their normal execution path.

Close out a finished (or abandoned) task: verify a summary exists for the bd issue, then `bd close` it with a resolution. The **finalize** step that ends the triage → plan → attach → summarize → close lifecycle.

**Trigger**: the work is done and you're ready to retire the bd from `bd ready` / `bd todo`. **Skip** if there's still meaningful follow-up — keep the bd open even though a summary may already exist (summary and close are deliberately decoupled).

Zombie issues (summary written, bd never closed) are the failure mode this skill prevents.

## Arguments

`$ARGUMENTS` is a bd-id, an optional resolution message, and optional flags in any position.

| Flag | Effect |
| --- | --- |
| `--personas` | Passed through to `summarize` if it runs: adds an inline persona pass. |
| `--deep` | Passed through to `summarize` if it runs: persona pass in an opus subagent. |

**Strip flags before reading the trailing text as the resolution message** — otherwise `--deep` lands inside the tombstone. Both flags are inert when a summary already exists and `summarize` doesn't run; say so rather than running a persona pass over the old summary.

Run the summary inline on the active session model so direct `summarize` and the auto-summarize path see the same conversation context.

## What this skill does (in order)

1. Parse `$ARGUMENTS` for the bd-id, optional flags, and optional resolution message. If the bd-id is missing, infer from the active conversation or plan file in context; ask the user if still ambiguous.
2. Resolve the owning project with `bdx-resolve-project <bd-id>` and use that returned path as the active working directory for the summarize process and every repository operation. Every Beads command must use `bd -C <project-path>`. In Codex, run this wrapper with host-level escalation and `prefix_rule: ["bdx-resolve-project"]`.
3. Check for an existing summary: `grep -l "^bd: <bd-id>$" "$AGENT_HOME/summary"/*.md` (a summary is any file with the matching `bd:` frontmatter line). Also locate the live plan at `$AGENT_HOME/plan/<bd-id>-*.md` before closing so a missing or ambiguous plan is discovered before the irreversible status change.
4. **If no summary exists**, run the full `summarize` process for this bd-id before continuing, forwarding any `--personas` / `--deep` flag. Do not skip this — summaries are the durable record of the work; a close without one loses history.
5. Resolve the resolution message (from the flag-stripped text):
   - If passed in `$ARGUMENTS` → use it.
   - If `$ARGUMENTS` contains "abandon" / "kill" / "drop" → default to `"abandoned: <verbatim-trailing-text>"`.
   - Otherwise → default silently to `"done"`. Do **not** prompt — the summary is the durable record; the resolution is a one-line tombstone and "done" is fine for the clean-completion case.
   - Only prompt if the close is ambiguous (e.g. summary mentions unresolved follow-ups and the user hasn't signaled intent).
6. Close the issue: `BDX_ALLOW_BARE_BD_CLOSE=1 bd -C <project-path> close <bd-id> -r "<resolution>"`. The inline env assignment signals the plugin's guard hook to allow this close through; without it the hook blocks all bare `bd close` calls.
7. After Beads confirms the close, run `bdx-plan-frontmatter <bd-id> --status closed`. This is a one-way projection into the live plan; never rewrite historical context dumps or summaries. If projection fails, report the closed Bead plus the exact repair command `bdx-sync-status <bd-id>`.
8. Report: bd-id, resolution, and the summary path.

## Resolution message guidance

- **Clean completion**: `"done"`, `"shipped in PR-1234"`, `"merged 2026-04-16"`.
- **Abandoned**: always prefix with `"abandoned: "` followed by the reason. Keeps `bd list -s closed` grep-able for "why did this die?"
- **Superseded by another task**: `"superseded by bd-yyy"` (and consider `bd supersede <bd-xxx> --with <bd-yyy>` instead of `bd close` — it creates a formal link).
- **One line, past tense.** The summary file holds the full story; the resolution is the one-sentence tombstone.

## Rules

- **Never close without a summary.** If step 3 fails (the user declines to summarize, or summarize errors), abort the close and tell the user why. Better to leave the issue open than to lose the record.
- **Don't edit the summary to reflect the close.** The summary is past-tense; closing is an act after. Keep them independent.
- **Project status deterministically.** Beads is authoritative. Only `bdx-plan-frontmatter` changes live plan `status:`; agents never hand-edit status YAML.
- **Don't file follow-ups automatically.** If the summary mentions "Follow-ups / known gaps", report them to the user so they can decide what to file — but don't auto-create issues. Agent-generated backlog noise is the other failure mode this skill avoids.
- **Closing an abandoned plan is valid and should be easy.** If the user says "kill it" or similar, run summarize first (to capture *why* it was abandoned — decisions worth preserving even for dead work), then close with `"abandoned: <reason>"`.

## Process

1. Resolve the bd-id and strip any `--personas` / `--deep` flag from `$ARGUMENTS` (from `$ARGUMENTS`, active plan file, or ask).
2. Resolve the project with `bdx-resolve-project <bd-id>`.
3. **Single batched message** — run in parallel: summary grep, plan lookup, and `bd -C <project-path> show <bd-id>` to confirm the issue exists and is closeable.
4. Resolve the resolution from the flag-stripped text: `$ARGUMENTS` if passed, `"abandoned: ..."` on abandon-signal keywords, else `"done"`. No prompt for the clean case.
5. If no summary is found → invoke the `summarize` process (follow that skill's instructions end-to-end, with this bd-id and any forwarded persona flag). After it writes the summary, continue.
6. Run `BDX_ALLOW_BARE_BD_CLOSE=1 bd -C <project-path> close <bd-id> -r "<resolution>"`.
7. Run `bdx-plan-frontmatter <bd-id> --status closed`; on failure report `bdx-sync-status <bd-id>` as the repair.
8. Report one line: `Closed <bd-id>: "<resolution>" — summary at <path>`.
