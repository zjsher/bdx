---
name: review-slice
description: Review a slice that /slice just landed under a constrained finding-contract - each finding needs a concrete failure scenario and a CONFIRMED/PLAUSIBLE verdict, an empty findings list is a PASS, only CONFIRMED blocks, PLAUSIBLE goes to the backlog, and the review runs exactly one round. Optionally borrows a saved persona as its lens. Use to close a slice without the review-until-clean loop that terminates by exhaustion instead of correctness.
user-invocable: true
argument-hint: [persona-slug] [target: diff|staged|HEAD|bd-id|path]
---

# review-slice

Review one slice under a contract that only fires on **real defects in what this slice changed.** This is the counterweight to an open-ended adversarial review: a reviewer told to "find what's wrong" treats an empty report as failing its job, so it manufactures speculative edge cases and you spend rounds whittling them down. This skill changes the reviewer's contract so an empty findings list is the *expected* outcome of a good slice - which is what makes one round enough.

## Core contract (do not violate)

1. **Scope gate - defects in THIS slice only.** A finding must be a defect in what the diff changed. Pre-existing issues, "while you're here" cleanups, and architecture opinions are **out of scope** - `bd create` them and move on. If you cannot point at a changed line, it is not a finding.
2. **Every finding needs a concrete failure scenario.** Specific input/state -> specific wrong output or crash. "This could be fragile" is not a finding. "Called with `organizationId` the user doesn't belong to, this returns another org's rows" is. **Re-read the actual code** and trace the scenario through it before you write the finding down - not the diff summary, the code.
3. **Verdict on every finding: CONFIRMED or PLAUSIBLE.**
   - **CONFIRMED** - you traced the failure through the real code and it is genuinely reachable. This blocks the slice.
   - **PLAUSIBLE** - you suspect it but could not fully verify (unread collaborator, unclear caller). This does **not** block; `bd create` it and note the verdict.
4. **An empty findings list is a PASS, not a failed review.** Say so plainly. A clean slice getting a clean review is the system working, not the reviewer slacking. Do not invent a finding to look thorough.
5. **One round.** Implement -> review once -> fix CONFIRMED -> done. Do **not** re-review after fixes unless a fix was *structural* (changed a signature, moved a seam, altered control flow). If a second review keeps surfacing new CONFIRMED defects, the slice was too big to review reliably - **shrink the next slice, don't add rounds.**
6. **Feed the self-check upstream.** Every CONFIRMED finding that survived to this review is a review the implementer's pre-review self-check should have caught. Append the one checklist line that would have prevented it to the repo's self-check list (see below). Over time the reviewer converges toward empty because the implementer already runs its playbook.

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
4. Walk the changed code. For each candidate defect, trace a concrete failure scenario through the real code (rule 2) and assign a verdict (rule 3). Drop anything out of scope (rule 1) to the backlog.
5. Emit the review card (below). `bd create` each PLAUSIBLE finding and each out-of-scope item; put the bd-ids in the card.
6. For each CONFIRMED finding, append the preventing line to `.claude/self-check.md` (rule 6).
7. **Halt.** Do not fix the findings yourself and do not re-review - the footer hands back to `/slice`.

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
- **CONFIRMED findings** -> `<N> confirmed defect(s) block this slice. Run /slice to fix: <one-line what>. Re-review only if a fix is structural.`
- **PASS but PLAUSIBLE backlogged** -> `Slice passes. <M> plausible item(s) filed (bd-<ids>) - not blocking. Run /slice for the next slice.`

Rules: 1-2 sentences, no headers, name the concrete next command, never roll into fixing or re-reviewing yourself.

## Composition

- Runs **after** a `/slice` lands - `slice` builds and verifies one increment, `review-slice` gates it once, then hands back. Together they replace the review-until-clean loop with implement -> review-once -> fix-confirmed -> next.
- Reuses `bdx:persona` for voice and the shared `.claude/self-check.md` for the checklist. It does not re-implement either.
- The pairing is a ratchet: findings that survive here become self-check lines the implementer runs next time, so the reviewer's job shrinks slice over slice.
