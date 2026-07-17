---
name: skeleton
description: Build the thinnest end-to-end path that actually runs, fast, with zero ceremony - no ledger, no bd, no per-step review. The walking-skeleton phase of /slice extracted and compressed for wall-clock. Use when a *running* spine is the goal and speed matters more than a defensible audit trail - spikes, prototypes, demos, timed interviews, or the first move before switching to /slice for rigor.
user-invocable: true
argument-hint: [what to build]
---

# skeleton

Get the **spine running end-to-end, fast.** The thinnest path that actually executes and can be demoed - then stop, or hand off. This is `/slice`'s walking-skeleton philosophy with every piece of ceremony that costs wall-clock removed. Reach for it when the win is _a thing that runs_, not _a defensible increment_.

## What this drops on purpose (vs /slice)

`/slice` is deliberately heavy - it buys a per-increment audit trail. This skill keeps the good half and cuts the cost. It does **not**:

- write a decision ledger or a formal slice card,
- track anything in `bd`,
- review each step (no `/slice-review` per increment),
- run the break-it-watch-red-restore proof on every check,
- halt for approval between increments.

If you need any of that - a high-stakes change, a review trail, a defensible history - **start with `/slice` instead, not this.** Choosing speed here is choosing to skip the trail, and that is the whole point. Don't half-reinstate the ceremony you came here to avoid.

## Core contract (do not violate)

1. **One spine, end-to-end, running.** The thinnest path that executes and can be demoed - not "item 1 of a plan," the _spine_. (URL shortener: `POST /shorten` -> in-memory store -> `GET /:code` -> 302. Nothing else.) If it doesn't run end-to-end, it isn't done; if it does more than run end-to-end, it's too much.
2. **Speed over ceremony.** Move. No ledger, no bd, no per-step card, no prove-it-can-fail ritual. The one gate is rule 4.
3. **Stub everything off the spine behind a seam.** Storage, auth, integrations, external calls, edge cases -> put them behind an interface and stub the impl, so they're swappable later without a rewrite. Name each as _deferred_. Never build them unasked.
4. **Verify once, at the end: the whole thing runs.** A single end-to-end check - one command, one request, one demo - that proves the spine is alive. Run it, show the result. Not per-step; not a full test suite. Just: it runs. Claim nothing you did not run.
5. **Narrate lightly, then hand off.** Emit the short note below - what runs, what's stubbed, what's deferred, what's next - and stop. Don't roll into thickening it unless asked.

## Anti-gold-plating guard (this is the whole discipline here)

Every time you add a field, a param, a branch, or a layer, ask: _does the spine need this to run, right now?_ If it's robustness, elegance, scale, or an edge case nobody demoed yet - it's deferred, say so, move on. Under a clock this is where the time actually leaks: not at the start (you're focused on the spine) but mid-build, in service of something that felt principled ten seconds ago. A beautiful storage layer with nothing calling it is a failed skeleton. A working redirect over an in-memory map is a done one.

## Report format (lighter than slice's card)

After the skeleton runs, output **one fenced note** - no preamble, no prose around it - then the handoff footer. Shape:

```
▸ skeleton: <2-4 word what-runs>

  Runs       <the end-to-end path that works now · <=10 words>
  Verified   <command> -> <it runs · <=6 words>
  Stubbed    <seams standing in for real impls · <=10 words · omit if none>
  Deferred   <named, not built · <=10 words>
  Next       <thinnest thickening step · <=10 words>
```

Rules:

- **One line per field. Never wrap.** Align the value column.
- Omit `Stubbed` if genuinely nothing is stubbed. `Runs`, `Verified`, and `Next` are mandatory.
- The only code in the note is the one `Verified` command. No diffs, no file dumps.

## Handoff footer (tell the human what's next)

Directly under the note, one short plain-prose line. The skeleton is alive - name the human's next move. Pick one:

- **Keep the spine, add rigor** -> `Skeleton runs. Switch to /slice to thicken it one verifiable increment at a time, or /slice-loop to finish the plan autonomously.`
- **Keep cranking fast** -> `Skeleton runs. Say the word and I'll thicken it - <next step> - same fast mode, no ceremony.`
- **Good enough** -> `Skeleton runs and demos. Stop here, or pick a deferred item to build next: <items>.`
- **Blocked** -> `Blocked: <one-line reason>. <what the human must decide or provide>.`

Keep it to 1-2 sentences, name the concrete command, never roll into the next step yourself.

## Thickening in fast mode (when you keep cranking)

If asked to continue past the skeleton *without* switching to `/slice`, stay fast but keep verification alive. This is the fast-and-complete lane - more working behavior per minute, checks you can show going green - not the audit-trail lane. The rule: **the checks accumulate, the paperwork doesn't.**

- **Re-run the one end-to-end check after every addition.** The skeleton's `Verified` command becomes a keep-it-green heartbeat - run it each increment so a thickening step that breaks the spine surfaces immediately. Cheapest regression net there is: one command, re-run.
- **Promote to a persisted check only where it's cheap.** When an increment adds behavior the end-to-end check can't see - a branch, an error path, a computed value - drop in a single assertion or a one-line script for exactly that, *if it costs seconds, not a framework.* Add the one check that would catch this increment regressing; don't build a suite.
- **Prove-it-can-fail stays selective here.** On the one load-bearing piece, break its check once and watch it go red before restoring - a check you never saw fail is a claim, not a check. Skip the ritual on the trivial ones. This is the single place skeleton borrows `/slice`'s rigor, and only there.
- **Still no ledger, no bd, no review pass.** The moment you actually need those - a defensible trail, a real review, someone auditing each step - that need *is* the signal to switch to `/slice`, not to bolt the ceremony onto this skill. Fast mode that grows paperwork is just `/slice` with worse discipline.

This is the lane for a timed build - interview, demo, spike: land more real behavior, show green checks, keep one or two that can genuinely fail, and never spend a minute on a record no one in the room will read.

## Decisions in the user's language

If a real tradeoff surfaces mid-skeleton - in the `Next`/`Deferred` lines or an `AskUserQuestion` - frame it as a **plain tradeoff, not the mechanism**: what it costs vs. buys for the product, and define any technical term the first time it appears in one clause. "Chose the throwaway in-memory store so it runs today; loses everything on restart" beats naming the internal. This is the skeleton-specific application of the standing rule in the user's global `~/.claude/CLAUDE.md` ("PRESENT DECISIONS IN PLAIN LANGUAGE").

## Arguments

`$ARGUMENTS` names what to build, or is empty:

- **Names the task/thing** -> build its walking skeleton.
- **Empty** -> infer the spine from the current context or a plan in scope, state it in one line, then build it.

## Composition

- This is the **compressed front-half of `/slice`'s first invocation** - same walking-skeleton philosophy, ceremony stripped for wall-clock.
- **Hands off to `/slice`** (per-increment rigor + review trail), **`/slice-loop`** (autonomous finish), or nothing. Once the spine runs, those thicken it; this skill only gets it alive.
- **When to reach for which:** `skeleton` when a _running thing fast_ is the win - spike, prototype, demo, timed interview, or the opening move of any build. `/slice` when _defensibility per increment_ is the win - high-stakes change, review trail needed, someone watching each step. Same spine-first instinct; opposite ceremony budget.
- Deliberately shares **nothing** with the bd lifecycle or `.claude/self-check.md`. Those belong to the slice flow; adding them back here defeats the purpose. If you want them, you wanted `/slice`.
