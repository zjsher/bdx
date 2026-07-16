# bdx

**Every Claude Code session writes a markdown plan/summary keyed by a `bd` issue. The session ends; the record stays, and the work is handled in reviewable slices.**

![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-D97757?logo=anthropic&logoColor=white) ![beads](https://img.shields.io/badge/beads-task_glue-9333EA) ![dolt](https://img.shields.io/badge/dolt-versioned_storage-1E40AF) ![status](https://img.shields.io/badge/status-experimental-yellow)

A running agent session holds a lot of working memory - the plan, what got tried, what was rejected and why. The moment the session ends, all of that evaporates. bdx couples every [`bd` (beads)](https://github.com/gastownhall/beads) task to durable markdown - plans, mid-stream context dumps, summaries - keyed by bd-id and stored in `$AGENT_HOME` so [Obsidian graph view](https://help.obsidian.md/Plugins/Graph+view) can show how tasks, decisions, and knowledge correlate across projects.

On top of that record sits an implementation discipline: [`slice`](#implementing-in-slices) lands work in bounded, verifiable increments; `slice-review` closes each one in a single contract-bound round; `slice-loop` executes a whole plan autonomously while preserving the per-slice audit trail. Same durable state, two speeds - you in the loop, or the loop on its own.

This is my current ideal agent coding workflow, and it has served me well.

## Quickstart

Bootstraps `bd`, `dolt`, `BEADS_DIR`, and `AGENT_HOME` in one shot. Safe to re-run.

```bash
curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/install.sh | bash
```

Then install the Claude Code plugin:

```bash
claude plugin marketplace add zeejers/bdx && claude plugin install bdx@bdx-marketplace
```

## Usage

Happy path:

```
plan → attach → (work: slice ⇄ slice-review, ticking with check / dump?) → close
```

**1. Plan.** Chat with the agent about what you want to build, then `/bdx:plan` to plan from the discussion (or `/bdx:plan "feature in one line"`). You get back a beads issue (e.g. `bd-abc`) plus a plan file at `$AGENT_HOME/plan/bd-abc-<slug>.md`.

**2. Attach.** From any Claude session, `/bdx:attach bd-abc`. The session loads the plan, every prior context dump, and the latest summary into turn-1 context - the agent picks up with full history.

> From a fresh terminal, `bdc bd-abc` launches `claude` with the task already attached.

**3. Track progress.** As steps finish, run `/bdx:check bd-abc "<step>"` to tick the matching checkbox on the plan. Peek at the plan anytime to see what's done. About to log out? `/bdx:dump` snapshots head-state to `$AGENT_HOME/context/` and ticks any obviously-done boxes; the next `/bdx:attach` pulls it back in.

**4. Close.** Finish the work, then `/bdx:close bd-abc` writes a summary to `$AGENT_HOME/summary/`, attributes decisions to agent vs user, and closes the bd issue with a one-line resolution. The plugin's `PreToolUse` hook blocks bare `bd close` so you can't accidentally skip the writeup.

## Implementing in slices

The lifecycle skills answer "where does the record live?"; the slice skills answer "how does the work land?" - in bounded, verifiable, defensible increments instead of one monolithic autonomous build.

**`/bdx:slice`** implements exactly one slice per invocation, then halts. The first slice on a fresh task is always the *walking skeleton* - the thinnest end-to-end path that actually runs - and every slice after that thickens the spine. Each slice ships with an executable pass/fail check (a test, an assertion, a script that exits non-zero), and the agent must prove the check can fail before claiming it passes. One row goes into the plan's decision ledger, then it stops and hands control back to you.

**`/bdx:slice-review`** closes the slice with a review that runs exactly one round. Reviewers told to "find what's wrong" manufacture speculative findings rather than report an empty list; slice-review inverts the contract - every finding needs a concrete failure scenario and a CONFIRMED/PLAUSIBLE verdict, an empty findings list is a PASS, only CONFIRMED blocks, PLAUSIBLE goes to the backlog. Optionally borrows a saved persona (`$AGENT_HOME/personas/`) as its lens.

**`/bdx:slice-loop`** runs the pair autonomously until a goal is met - "until phase 5-6 complete", "until the plan is done", or a bd-id's remaining checkboxes. A lean parent session spawns worker subagents that each run a quota of slice → slice-review iterations and retire fresh (so no worker degrades from context exhaustion), with a mechanism-level quality audit at every handoff. You give up the per-slice approval gate; you keep the full audit trail - ticked plan boxes, decision-ledger rows, per-slice bd comments. It halts back to the human when boxes hide design decisions rather than execution.

The trade: `slice` keeps your judgment visible between increments (pairing, high-visibility changes, anything you want to stay in control of); `slice-loop` is for when the design is settled and what's left is execution.

## Skills (`/bdx:<name>`)

**Happy path** - the five you'll reach for daily:

- `plan` - open a new bd task + paired plan file.
- `attach` - resume an existing bd task in a fresh session: load plan + prior contexts/summaries, flip status to in_progress.
- `check` - tick a checkbox on the plan with no other side effects. Cheap mid-task progress.
- `dump` - snapshot session head-state so you can log out fearlessly. Sweeps the plan for done checkboxes too.
- `close` - finalize the task: write a summary if missing, then `bd close`.

**Implementation loop** - see [Implementing in slices](#implementing-in-slices):

- `slice` - implement one bounded, verifiable increment (walking-skeleton first), verify with an executable check, log to the decision ledger, halt.
- `slice-review` - review the landed slice in exactly one round under a constrained finding-contract; empty findings = PASS.
- `slice-loop` - orchestrate slice ⇄ slice-review autonomously via worker subagents until a stated goal is met, with quality audits at every handoff.

**Less common:**

- `summarize` - write the durable post-implementation record to `$AGENT_HOME/summary/`. Usually invoked by `close`; standalone-callable when you want the writeup before closing. Runs on sonnet and skips persona reviews by default; pass `--personas` for an inline review pass, or `--deep` to run it on opus. `close` forwards both flags.
- `scope` - retrofit an existing bd (no plan, no project label) into the lifecycle. Use when a bd was created bare via phone capture or `bd create`.
- `triage` - drain inbox + unscoped-bd queues into structured tasks. Hands off to `plan` or `scope`.
- `label` - apply plain labels or namespaced external refs (`jira:`, `linear:`, `gh:`, `figma:`); namespaced refs propagate into the plan's frontmatter.
- `manifest` - register or update a project entry in `$AGENT_HOME/manifest.md` so `plan`/`scope` can validate labels against it.
- `persona` - invoke a saved reviewer voice over a target (file, bd-id, diff, prose). Used by `summarize` under `--personas` / `--deep`.

## `$AGENT_HOME`

Durable markdown lives under `$AGENT_HOME` (default `~/.bdx-agent/`). The hook auto-creates the layout:

```
$AGENT_HOME/
├── plan/       # long-form plans (the execution prompt)
├── context/    # mid-stream state dumps
├── summary/    # post-implementation writeups
└── inbox/      # mobile-capture seeds
```

Override by exporting `AGENT_HOME` before launching `claude` - e.g. `export AGENT_HOME="$HOME/Dropbox/Notes/agent"` to sync plans across machines.

## Permissions

Every `/bdx:*` skill fires `bd` subcommands and writes to `$AGENT_HOME/`. The Quickstart installer adds the right allowlist to `~/.claude/settings.json` automatically. To do it by hand:

```json
{
  "permissions": {
    "allow": [
      "Bash(bd:*)",
      "Read(~/.bdx-agent/**)",
      "Write(~/.bdx-agent/**)",
      "Edit(~/.bdx-agent/**)"
    ]
  }
}
```

If you've overridden `AGENT_HOME`, swap that path in. Claude Code expands `~` but not shell env vars.

---

## Under the hood

### Lifecycle (full state machine)

```
        capture                                 work
   ┌──────────────┐                  ┌─────────────────────────────────┐
   │ inbox / bare │   triage         │                                 │
   │ bd create    │ ─────────► plan ─┤ attach ──► check / dump? ───┐   │
   └──────────────┘     │            │   ▲                         │   │
                        │            │   │       resume cold       │   │
                        └─► scope ───┤   └─────────────────────────┘   │
                                     │                                 │
                                     │            work done            │
                                     └─► summarize ──► close           │
                                                                       │
                                            (terminal) ────────────────┘
```

The plan stays close to its original shape - it's the prompt, and the diff `plan ↔ summary` is "what we set out to do" vs "what shipped." `check`, `dump`, and `summarize` may all tick `- [ ]` boxes (with optional `→ <divergence>` annotations) so the plan stays a live progress view. None of them rewrite plan prose.

### Hooks

- **`SessionStart`** → `capture-session-id.sh` exposes the session UUID as `$CLAUDE_SESSION_ID` so artifacts can record which session produced them in `sessions:` frontmatter, enabling `claude --resume <uuid>`.
- **`SessionStart`** → `bdx-ensure-agent-home.sh` resolves `$AGENT_HOME`, auto-creates the subdir layout, and exports the value.
- **`SessionStart:startup`** → `bd-auto-attach.sh` if `$BD_ID` is set, auto-loads plan/context/summary, appends the session UUID to `sessions:`, flips bd status `open → in_progress`, and emits the bundle as `additionalContext` on turn 1.
- **`PreToolUse:Bash`** → `block-bare-bd-close.sh` blocks direct `bd close` so you're forced through `/bdx:close`.

### Launcher

`scripts/bdc <bd-id>` sets `BD_ID`, derives a slug from the bd title, and runs `claude -n "<bd-id>-<slug>"`. Symlink to `~/bin/bdc` or alias it.

### Local plugin dev

```bash
claude --plugin-dir ~/src/github.com/bdx
```

### Optional starter content

Drop-ins under [`examples/`](./examples/):
- `examples/manifest.md` → `$AGENT_HOME/manifest.md` - sample project manifest used by `plan`/`scope` to validate labels in monorepos.
- `examples/personas/` → `$AGENT_HOME/personas/` - example reviewer voices (DHH, Linus) for `summarize`.

The Quickstart installer offers to seed these at step 5/5.

### Escape hatches

- `BD_ID` unset → SessionStart hook is a silent no-op
- `BDX_ALLOW_BARE_BD_CLOSE=1 bd close bd-abc` → bypass the close guard once

### Prerequisites

- `bd` (beads) CLI on `$PATH` - [gastownhall/beads](https://github.com/gastownhall/beads)
- `dolt` on `$PATH` - beads' storage backend ([dolthub/dolt](https://github.com/dolthub/dolt))
- `jq`, `bash`, POSIX `awk`

The Quickstart script handles `bd` and `dolt` for you.

### Uninstall

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zeejers/bdx/refs/heads/development/scripts/uninstall.sh)
```

Reverses everything except your shell profile exports. Destructive ops default to *no*; `--dry-run` previews.

## FAQ

### Why am I installing dolt for an issue tracker?

You're not - you're installing it for `bd`. [Beads](https://github.com/gastownhall/beads) is the issue tracker; it ships with [Dolt](https://github.com/dolthub/dolt) (a SQL DB with git-style branching) as its storage backend. That's what makes tasks, comments, and status persist across sessions, machines, and branches - sync `$AGENT_HOME` via Dropbox/iCloud and your agents have a real persistence layer, not a chat log.

### Do I need a separate dolt server running?

`bd` auto-starts one transparently in the background the first time it needs one. `bd dolt status` shows it. Default mode is shared-server - one process serves every project on the machine.

### Can I skip dolt and use SQLite?

Beads has a `no-db` JSONL-only mode (set `no-db: true` in `~/.beads/config.yaml`), but you lose the branchable history. The installer's `--skip-dolt` flag exists if you want to go that route.
