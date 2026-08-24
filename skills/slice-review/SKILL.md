---
name: slice-review
description: >-
  Review a slice that /slice just landed under a constrained finding-contract - CONFIRMED requires an executable repro run against the current code (trace-only suspicion is PLAUSIBLE), one bounded mutation probe checks the slice's net can actually go red, an empty findings list is a PASS, only CONFIRMED blocks, PLAUSIBLE goes to the backlog, and the review runs exactly one round. Optionally borrows a saved persona as its lens. Use to close a slice without the review-until-clean loop that terminates by exhaustion instead of correctness.
---

## Codex host execution (mandatory)

When the harness is Codex, invoke every shell tool call that runs `bd` with `sandbox_permissions: "require_escalated"`; for a direct `bd ...` command, also set `prefix_rule: ["bd"]`. The installed allow rule only pre-approves escalation—it does not move a default call outside the workspace sandbox. This applies to read-only commands too. If a sandboxed call reports a Dolt connection failure, retry at host level before diagnosing Dolt as down; wrappers inherit the sandbox. Claude Code and other non-Codex harnesses must ignore this section and use their normal execution path.

# slice-review

Review one slice under a contract that only fires on **real defects in what this slice changed.** This is the counterweight to an open-ended adversarial review: a reviewer told to "find what's wrong" treats an empty report as failing its job, so it manufactures speculative edge cases and you spend rounds whittling them down. This skill changes the reviewer's contract so an empty findings list is the *expected* outcome of a good slice - which is what makes one round enough.

## Core contract (do not violate)

1. **Scope gate - defects in THIS slice only.** A finding must be a defect in what the diff changed. Pre-existing issues, "while you're here" cleanups, and architecture opinions are **out of scope** - `bd create` them and move on. If you cannot point at a changed line, it is not a finding.
2. **Every finding needs a concrete failure scenario.** Specific input/state -> specific wrong output or crash. "This could be fragile" is not a finding. "Called with `organizationId` the user doesn't belong to, this returns another org's rows" is. **Re-read the actual code** and trace the scenario through it before you write the finding down - not the diff summary, the code.
3. **Verdict on every finding: CONFIRMED or PLAUSIBLE - and CONFIRMED is earned by running, not tracing.**
   - **CONFIRMED** - you wrote an executable repro for the failure scenario (a test, an assertion, a script, a curl), ran it against the current code, and watched it exhibit the wrong behavior. A red repro doesn't care what context wrote it - that is what makes this verdict trustworthy from the same session that implemented the slice. This blocks the slice. For mediums with no runtime, degrade exactly as slice's "when the check isn't a unit test" ladder does - the strongest objective check the medium allows.
   - **PLAUSIBLE** - you suspect it but could not demonstrate it (unread collaborator, unclear caller, a scenario you can't run). Tracing alone - however convincing - lands here. This does **not** block; `bd create` it and note the verdict. Never fake a repro to promote a finding.
4. **One mutation probe - the reviewer's red-green-red.** Same-context review misses more than it fabricates, so take one signal from something with no context window: break the most load-bearing changed line (one probe, two max), run the slice's checks, expect red, restore. Checks stay green -> that is a CONFIRMED coverage-gap finding ("the slice's net does not cover what it claims"), discovered by the test runner, not by judgment. Keep it seconds-cheap; the moment this grows toward a mutation-testing framework it has become ceremony.
5. **An empty findings list is a PASS, not a failed review.** Say so plainly. A clean slice getting a clean review is the system working, not the reviewer slacking. Do not invent a finding to look thorough.
6. **One round - and the repro closes the loop.** Implement -> review once -> fix CONFIRMED -> done. Each CONFIRMED finding's repro is the fix's acceptance test: after `/slice` fixes it, re-running the repro green closes the finding - no re-review round. Do **not** re-review after fixes unless a fix was *structural* (changed a signature, moved a seam, altered control flow). If a second review keeps surfacing new CONFIRMED defects, the slice was too big to review reliably - **shrink the next slice, don't add rounds.**
7. **Feed the self-check upstream.** Every CONFIRMED finding that survived to this review is a review the implementer's pre-review self-check should have caught. Append the one checklist line that would have prevented it to the repo's self-check list (see below). Over time the reviewer converges toward empty because the implementer already runs its playbook.

## Persona as lens (optional)

If `$ARGUMENTS` names a persona slug, borrow that voice via the `bdx:persona` primitive - the persona supplies **tone and what-they-notice**, this skill supplies the **binding finding-bar**. The voice is cosmetic; a persona's sharp opinion still only becomes a *finding* if it clears rules 1-3. A persona ranting about a style choice with no failure scenario produces zero findings, in their voice. Neutral (no slug) is fine and is the default.

## Self-check list (shared source of truth)

The implementer (`slice`) and this reviewer read the same living checklist so the loop actually shortcuts. Convention: **`.claude/self-check.md` at the git root.**

- If it exists, read it first - it names this repo's recurring CONFIRMED categories, and a finding in one of those categories is a strong CONFIRMED signal.
- When a CONFIRMED finding survives, **append** the checklist line that would have caught it (append-only; never rewrite prior lines). Phrase it as a checkable pre-write assertion, not a war story.
- If the file does not exist and a CONFIRMED finding survives, create it with that first line. No repo-specific content ships in this skill - the checklist is per-repo.

## Process

1. Parse `$ARGUMENTS`: an optional leading persona slug (matches a file in `$AGENT_HOME/personas/`), then the target. Missing target -> default to the working diff (`git diff`), then staged, then `HEAD`.
2. Resolve the target - `git diff` / `git show` for a ref, `bd show <id>` + its plan for a bd-id, a file read for a path. **The diff is the scope boundary** for rule 1.
3. Read `.claude/self-check.md` at the git root if present. If a persona slug was given, load it via `bdx:persona`.
4. Walk the changed code. For each candidate defect, trace a concrete failure scenario through the real code (rule 2), then try to demonstrate it with an executable repro - run it, watch it exhibit the failure (rule 3). Demonstrated -> CONFIRMED; trace-only -> PLAUSIBLE. Drop anything out of scope (rule 1) to the backlog.
5. Run the mutation probe (rule 4): break the most load-bearing changed line, run the slice's checks, expect red, restore. Green silence -> CONFIRMED coverage-gap finding.
6. Emit the review card (below). `bd create` each PLAUSIBLE finding and each out-of-scope item; put the bd-ids in the card.
7. For each CONFIRMED finding, append the preventing line to `.claude/self-check.md` (rule 7).
8. **Halt.** Do not fix the findings yourself and do not re-review - the footer hands back to `/slice`.

## Report format (match slice's terseness)

One fenced card. No preamble, no prose around it.

```
▸ review: <slice title>

  Scope     <what the diff changed · <=10 words>
  Lens      <persona slug | neutral>
  Verdict   PASS - no confirmed defects   |   <N> confirmed, <M> plausible
```

Then, only if there are findings, one block per finding, CONFIRMED first:

```
  ✗ CONFIRMED  <one-line defect>
     Scenario  <input/state -> wrong output or crash · one line>
     Repro     <command that exhibits it now> -> <red result · <=6 words>
     Code      <file:line>
     Fix       <smallest correction · <=10 words>

  ? PLAUSIBLE  <one-line suspicion>  -> bd-<id>
     Scenario  <what you couldn't rule out · one line>
```

Rules that keep it clean:
- **One line per field. Never wrap.** Align the value column.
- CONFIRMED blocks; PLAUSIBLE and out-of-scope are already backlogged with bd-ids - don't restate them as prose.
- No file dumps, no diffs, no "overall the code looks good" filler. The card is the whole review.

## Next-steps footer (hand back to the human)

Directly under the card, one short plain-prose line. Pick one state:

- **PASS** -> `Slice is clean. Run /slice for the next slice, or stop if the spine is complete.`
- **CONFIRMED findings** -> `<N> confirmed defect(s) block this slice. Run /slice to fix: <one-line what>. Each repro going green closes its finding; re-review only if a fix is structural.`
- **PASS but PLAUSIBLE backlogged** -> `Slice passes. <M> plausible item(s) filed (bd-<ids>) - not blocking. Run /slice for the next slice.`

Rules: 1-2 sentences, no headers, name the concrete next command, never roll into fixing or re-reviewing yourself.

## Composition

- Runs **after** a `/slice` lands - `slice` builds and verifies one increment, `slice-review` gates it once, then hands back. Together they replace the review-until-clean loop with implement -> review-once -> fix-confirmed -> next.
- Reuses `bdx:persona` for voice and the shared `.claude/self-check.md` for the checklist. It does not re-implement either.
- The pairing is a ratchet: findings that survive here become self-check lines the implementer runs next time, so the reviewer's job shrinks slice over slice.
- Deliberately **same-context and fast** - no fresh subagents here. Its findings earn trust from executable repros and the mutation probe, not from independence; phase-level independent review is `quality-audit`'s job at phase gates. Keeping this skill seconds-cheap is what keeps it running every slice.
