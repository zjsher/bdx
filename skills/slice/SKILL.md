---
name: slice
description: Drive implementation in bounded, verifiable, defensible increments - one slice per turn, walking-skeleton first, verify-and-narrate, then halt. Use when you want visible, reviewable, senior-looking implementation instead of a monolithic autonomous build - high-visibility pairing, interviews, or any change you want to stay in control of. Pairs after a plan/spec step.
---

# slice

Implement in **reviewable units, not deployable units.** One slice, verified, narrated, then stop. This is the opposite of "begin implementing the whole plan" - it keeps the human's judgment visible and every line defensible.

## Core contract (do not violate)

1. **One slice per invocation.** Never implement the whole plan in a single run.
2. **First invocation on a fresh task = build the WALKING SKELETON**: the thinnest end-to-end path that actually runs and can be demoed. Not "item 1 of a sequential plan" - the *spine*. (URL shortener: `POST /shorten` -> in-memory store -> `GET /:code` -> 302. Nothing else.)
3. A **slice** = the smallest change that (a) moves the spine forward and (b) can be verified on its own. If proving it takes more than ~1 verify step, it's too big: split it.
4. **Verify with an executable, pass/fail check - not an eyeball.** Every slice lands with something that *can fail on its own*: a unit test, an assertion, or a script that exits non-zero on mismatch. Run it, show the result. A command that only prints output but can never fail is not verification - and neither is a test that passes because of how you configured its own mock. **Prove it can fail:** break the exact thing the check names, watch it go red, restore. A check you never saw fail is a claim, not a check. Prefer checks that **persist and re-run** so the skeleton stays green as later slices thicken it - a growing regression net, not one-off commands. (Weight scales: a curl that greps for the expected status and exits non-zero otherwise counts; you don't need a full framework for the skeleton.) Claim nothing you did not run.
5. **Log, then HALT.** Append one row to the decision ledger (see below), then stop. Do not roll into the next slice.

## Slice-sizing rules

- **Thin end-to-end beats layer-complete.** A working redirect beats a flawless storage layer with nothing calling it.
- **Seams over implementations.** Put storage / integrations / external calls behind an interface and stub the impl, so they are swappable without a rewrite. Name the swap you enabled.
- **Defer, don't build.** Auth, analytics, rate limiting, scale-hardening, exotic edge cases: name them as *deferred*, never implement them unasked.

## When the check isn't a unit test

"Enforceable" means an objective, repeatable pass/fail signal - not necessarily a unit
test. It degrades to the strongest check the slice's medium allows:

- **Code** -> test / assertion / script that exits non-zero on mismatch.
- **Config / infra** -> `validate` / `plan` / lint / dry-run / a healthcheck that fails on drift.
- **Schema / contract / data** -> parse-and-validate, a contract test, a migration that applies and rolls back clean.
- **Docs / content** -> builds or renders without error, link-check passes.

If a slice genuinely has *no* observable outcome to check, it is almost never a slice -
it is a **decision** (log it in the plan's Decision log, don't fake a test) or it is
incomplete until paired with the code that consumes it. "Untestable" is usually a sign
the unit is really planning, not implementation.

## When the slice's contract is "nothing changes"

Extractions, moves, renames, seam-introductions: real slices - they move the spine by
making the next one possible - but their contract is *behavior-identical*, so there is
no new behavior to check. **The existing suite is the verification.** Land it as:

- the existing tests pass, and
- a **mutation proving the new seam is load-bearing**: break the seam, watch the
  *existing* tests fail, restore. That is what rules out "I moved code and quietly
  changed it."

If you had to touch the existing tests, say exactly why: a changed *collaborator*
(a mock now standing in for a new dependency) is legitimate; a changed *assertion*
means behavior moved and the slice isn't behavior-preserving after all. If coverage
moved between files, show both suites and say "relocated, not dropped."

**Do not author new tests to fill a quota.** This section exists because rule 4 reads
as "produce a new check" and a refactor has none to produce - so the tempting move is
to invent one, and an invented test asserts whatever passes. That is precisely where
fake tests come from. Nothing new to check is the *expected* state here, not a gap.

## Anti-gold-plating guard (run continuously)

Ask: *is this the spine, or am I polishing?* If it is robustness / scale / elegance nobody asked for yet, move it to "deferred" and say so out loud. Beautiful code on the wrong thing is a failed slice, not a good one. (No collision-resistant base62 with a bloom filter while the redirect still doesn't work.)

**Not a one-time gate at slice start.** Almost nothing gets gold-plated at slice start - you're too focused on the spine. It gets added *mid-slice*, in service of something that felt principled ten seconds earlier ("I shouldn't silently drop this"). Re-ask the question every time you add a field, a param, or a branch.

**The guard covers what you write in the tests, too.** Of every check: *what mutation makes this fail?* If the answer is "none" or "only the mock", delete it. If its name claims a branch (`rejects a pinless target`), point at the line implementing that branch - if you can't, the test is a sentence and the name is a lie. Coverage manufactured to satisfy this skill is the skill failing, not passing.

**When you write a comment explaining why something dead is fine, delete the thing.** ("Never branched on", "kept for symmetry", "diagnostics only".) Articulating the justification discharges the discomfort that should have killed it - the comment is a deletion notice you filed instead of acting on.

## Pre-review self-check (run before you HALT)

Before emitting the card, self-review the slice's diff against this repo's living
self-check list - **`.claude/self-check.md` at the git root, if it exists.** It names the
categories that have repeatedly turned into *confirmed* defects here (RBAC bypass, missing
`await`, whatever this repo's pattern is). Fix anything it names *before* you report - the
point is that the downstream reviewer finds nothing because you already ran its playbook.

- No `.claude/self-check.md` -> skip this silently. The list is per-repo and starts empty;
  it is grown by the reviewer, not seeded by this skill.
- This is a self-check, not a second implementation pass. It catches the recurring
  category, it does not invite gold-plating - the anti-gold-plating guard still binds.
- The list is a **ratchet**: when `slice-review` later confirms a defect that survived this
  check, it appends the line that would have caught it. Next slice, this check catches it.
  You don't edit the list here; you just run it.

## Decisions in the user's language

A slice surfaces decisions in three places: the card's `Tradeoff` / `Risk` lines,
the footer's "run /slice to build X" pick, and any `AskUserQuestion` you raise
mid-slice. At all three, frame the choice as a **plain tradeoff, not the
mechanism** — what it costs vs. buys for the product — and define any technical
term the first time it appears, in one clause, as if the reader has never seen a
distributed system.

- `Tradeoff` / `Risk`: "chose the safe-but-slower path" beats "fenced the write
  behind an epoch guard." Name the *stake* (safety, cost, speed, do-it-later),
  not the internal.
- Footer / `AskUserQuestion`: every option gets a one-line plain-English version
  and its product impact. The person approving must be able to *weigh* it, not
  just trust it. If a term is unavoidable, gloss it inline.

This governs the moment of **deciding**, not the whole card — the `Built` /
`Verified` lines can stay precise and technical. Jargon between you and the code
is fine while you work; it's a problem only when it's the language a decision is
dressed in. This is the slice-specific application of a firm standing rule in the
user's global `~/.claude/CLAUDE.md` ("PRESENT DECISIONS IN PLAIN LANGUAGE"),
which applies everywhere, not just slices.

## Report format (terseness is the feature)

After the slice, output **one fenced card** - no preamble, no prose wrapped around it -
followed only by the next-steps footer (see below). Shape:

```
▸ <2-4 word slice title>

  Built     <what runs now that didn't before · <=10 words>
  Verified  <command> -> <result · <=6 words>
  Tradeoff  <chose X over Y · <=10 words · omit line if none>
  Risk      <weakest point / what you'd harden first · <=10 words>
  Next      <smallest next slice · <=10 words>   |   done · spine complete
```

Rules that keep it clean:
- **One line per field. Never wrap, never a second sentence, never a paragraph.**
- Align values in a column (labels padded to the same width).
- **Omit a line entirely** rather than pad it with filler. Empty Tradeoff/Risk -> drop it.
- **Built and Next are mandatory.** Everything else earns its place or disappears.
- The only code in the card is the one `Verified` command. No file dumps, no diffs.
- If you're tempted to explain more, that detail belongs in the code or a follow-up
  answer when asked - not in the card.

## Next-steps footer (tell the human what to do now)

Directly under the card, print a short plain-prose footer telling the human what to do
next. The card's `Next` line names the next *slice*; the footer names the next *human
action*. Pick exactly one state:

- **Spine still growing** ->
  `Review the diff above. When it looks right, run /slice to build: <next slice>.`
- **Spine complete, feature functionally complete** ->
  `Feature is functionally complete. Suggested: review the deferred list in the decision log, then run a post-implementation audit (/quality-audit or /code-review).`
- **Spine complete, deferred items remain that the user may want** ->
  `Spine is complete and working. Deferred: <items>. Run /slice <item> to pick one up, or stop here if not needed.`
- **Blocked** (verify failed, decision needed, missing input) ->
  `Blocked: <one-line reason>. <what the human must decide or provide>.`

Rules:
- 1-3 sentences, no headers, no bullets, no restating the card.
- Always name the concrete command to run next (`/slice ...`, an audit skill, or nothing).
- Never continue into the next slice yourself - the footer is the handoff, then halt.

## Decision ledger (persist what you traded away)

After emitting the card, append **one row** to the task's decision ledger - the running
ADR where tradeoffs / risks / deferrals accumulate so they can be reviewed, fed to a
later audit, or read aloud when presenting.

**The ledger lives in the plan file - always.** Append a `## Decision log` section to
the plan file this task was planned from, and add rows there. The plan is the per-task
ADR (one per bd, found by `grep <bd-id>`); keeping the log with the spec means one doc
carries both what you intended and what you traded away.

Rules:
- Add the `## Decision log` header + table on the first slice; append one row per slice after.
- Same terseness as the card: `<=10 words` per cell, `-` for a genuinely empty cell.
- **Append only.** Never rewrite prior rows - the log is the history of what you chose.
- If writing is impossible, skip silently and add a one-line `Ledger:` note under the
  card instead. Never block the slice on the log.

Section appended to the plan file:

    ## Decision log

    | # | Slice          | Decision · tradeoff              | Risk                    | Deferred            |
    |---|----------------|---------------------------------|-------------------------|---------------------|
    | 1 | skeleton       | in-memory store over Redis      | no persistence on crash | auth, analytics     |
    | 2 | redirect       | 302 over 301, no cache          | -                       | custom alias        |

## Arguments

`$ARGUMENTS` may name a specific slice, or the overall task, or be empty:
- **Names the task, no skeleton yet** -> build the walking skeleton.
- **Names a specific slice** -> build exactly that slice, nothing adjacent.
- **Empty** -> propose the next slice from current state, then build that one.

## Composition

- Runs *after* a plan/spec step (e.g. a scoped spine). It does not plan; it executes one increment of a plan.
- Pairs with an adversarial pre-gate (defend the slice's design) and a post-implementation audit (security / scale pass) once the spine is complete.
- **Pairs with `/slice-review` per slice.** slice builds and verifies one increment; slice-review gates it once under a finding-contract (concrete failure scenario required, CONFIRMED blocks / PLAUSIBLE backlogged, empty = PASS, one round), then hands back. That replaces review-until-clean - which terminates by exhaustion against an adversary that must always find something - with implement -> review-once -> fix-confirmed -> next. Confirmed findings ratchet into `.claude/self-check.md`, which this skill's pre-review self-check then runs, so the reviewer converges toward empty.
