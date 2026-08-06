# bdx

**Every agent session writes a markdown plan/summary keyed by a `bd` issue. The session ends; the record stays, and ordinary feature work moves through one tight build loop.**

![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-D97757?logo=anthropic&logoColor=white) ![beads](https://img.shields.io/badge/beads-task_glue-9333EA) ![dolt](https://img.shields.io/badge/dolt-versioned_storage-1E40AF) ![status](https://img.shields.io/badge/status-experimental-yellow)

A running agent session holds a lot of working memory - the plan, what got tried, what was rejected and why. The moment the session ends, all of that evaporates. bdx couples every [`bd` (beads)](https://github.com/gastownhall/beads) task to durable markdown - plans, mid-stream context dumps, summaries - keyed by bd-id and stored in `$AGENT_HOME` so [Obsidian graph view](https://help.obsidian.md/Plugins/Graph+view) can show how tasks, decisions, and knowledge correlate across projects.

On top of that record sits an implementation discipline. [`build-loop`](#implementing-features) is the default: lock the design, keep one implementer in context, verify each coherent behavior with tight executable feedback, persist only meaningful milestones, then run one fresh review at the goal boundary. `slice-loop` is the higher-assurance feature for risky work that earns repeated independent review and a per-slice audit trail.

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

Or install the Codex plugin:

```bash
codex plugin marketplace add zeejers/bdx && codex plugin add bdx@bdx-marketplace
```

## Usage

Default feature path:

```
plan → attach → build-loop → close
```

**1. Plan.** Chat with the agent about what you want to build, then `/bdx:plan` to plan from the discussion (or `/bdx:plan "feature in one line"`). You get back a beads issue (e.g. `bd-abc`) plus a plan file at `$AGENT_HOME/plan/bd-abc-<slug>.md`.

**2. Attach.** From any supported agent session, `/bdx:attach bd-abc`. The session loads the plan, every prior context dump, and the latest summary into turn-1 context - the agent picks up with full history.

> From a fresh terminal, `bdc bd-abc` launches `claude` with the task already attached.

**3. Build.** Run `/bdx:build-loop bd-abc` (or name a phase/goal). The agent locks a compact design contract, implements coherent behavior in one continuous context, runs narrow checks as it goes, ticks only completed plan outcomes, and performs one fresh review at the goal boundary.

**4. Track or hand off.** Peek at the plan anytime to see what's done. `/bdx:check bd-abc "<step>"` is the cheap manual progress primitive. About to log out mid-goal? `/bdx:dump` snapshots head-state to `$AGENT_HOME/context/`; the next `/bdx:attach` pulls it back in.

**5. Close.** Finish the work, then `/bdx:close bd-abc` writes a summary to `$AGENT_HOME/summary/`, attributes decisions to agent vs user, and closes the bd issue with a one-line resolution. The plugin's `PreToolUse` hook blocks bare `bd close` so you can't accidentally skip the writeup.

## Implementing features

The lifecycle skills answer "where does the record live?"; the implementation skills answer "how does the work land?" `build-loop` is the ordinary default. Reach for more ceremony only when the risk or review requirement earns it.

**`/bdx:build-loop`** implements a planned feature through one tight, design-gated loop. Before editing, it locks the observable outcome, invariants, existing seam, executable check, and non-goals. One implementer then adds coherent behavior, runs the narrowest deterministic check plus a cheap end-to-end heartbeat, and continues without per-increment reviewers, report cards, ledger rows, or Beads comments. Completed plan outcomes, material decisions, blockers, and resumable handoffs remain durable. At the requested goal boundary it runs the broader relevant gate plus one fresh `quality-audit light` review.

`build-loop` halts on an unresolved consequential decision, the same failure twice, an unverifiable acceptance signal, degraded context, or its behavioral bound. It also stops and recommends `slice-loop` before changing authentication, authorization, tenancy, money, deletion, migrations, crash recovery, distributed concurrency, irreversible external effects, cross-repository state machines, weak/subjective test oracles, or anything that must be audited increment by increment. You can explicitly accept the lighter assurance tradeoff and continue, but the boundary review then stays mandatory.

**`/bdx:skeleton`** is that walking skeleton on its own, ceremony stripped - the thinnest end-to-end path that actually runs, built fast with no ledger, no bd, no per-step review. It's the compressed front-half of `slice` for when a *running thing* is the win and wall-clock matters: spikes, prototypes, demos, timed interviews, or the opening move before you switch to `slice` for rigor. Verify once at the end (it runs), emit a short note, hand off. Re-invoke `/bdx:skeleton <next step>` to thicken the spine in the same fast mode - it detects a running spine and never rebuilds it, re-running one end-to-end check per increment as a keep-it-green heartbeat; `new` forces a fresh spine.

**`/bdx:slice`** implements exactly one slice per invocation, then halts. The first slice on a fresh task is always the *walking skeleton* - the thinnest end-to-end path that actually runs - and every slice after that thickens the spine. Each slice ships with an executable pass/fail check (a test, an assertion, a script that exits non-zero), and the agent must prove the check can fail before claiming it passes. One row goes into the plan's decision ledger, then it stops and hands control back to you.

**`/bdx:slice-review`** closes the slice with a review that runs exactly one round. Reviewers told to "find what's wrong" manufacture speculative findings rather than report an empty list; slice-review inverts the contract - every finding needs a concrete failure scenario and a CONFIRMED/PLAUSIBLE verdict, an empty findings list is a PASS, only CONFIRMED blocks, PLAUSIBLE goes to the backlog. Optionally borrows a saved persona (`$AGENT_HOME/personas/`) as its lens.

**`/bdx:slice-loop`** is the high-assurance feature. It runs the slice/review pair autonomously until a goal is met - "until phase 5-6 complete", "until the plan is done", or a bd-id's remaining checkboxes. A lean parent session spawns worker subagents that each run a quota of slice → slice-review iterations and retire fresh, with a mechanism-level quality audit at every handoff. That serial assurance is intentionally slower: use it when a defect can cross a security, tenancy, money, deletion, migration, recovery, or audit boundary and the per-slice evidence is worth the wall-clock cost.

The trade is a ceremony dial. `skeleton` is the throwaway-fast end: a running spine, one check, no durable trail. `build-loop` is the production default: durable milestones, tight checks, one boundary review. `slice` keeps your judgment visible after every defensible increment. `slice-loop` autonomously pays the full per-slice assurance cost. Same spine-first instinct; different evidence budgets.

## Skills (`/bdx:<name>`)

**Happy path** - the five you'll reach for daily:

- `plan` - open a new bd task + paired plan file.
- `attach` - resume an existing bd task in a fresh session: load plan + prior contexts/summaries, flip status to in_progress.
- `check` - tick a checkbox on the plan with no other side effects. Cheap mid-task progress.
- `dump` - snapshot session head-state so you can log out fearlessly. Sweeps the plan for done checkboxes too.
- `close` - finalize the task: write a summary if missing, then `bd close`.

**Implementation loop** - see [Implementing features](#implementing-features):

- `build-loop` - default planned feature workflow: lock the design, implement in one tight loop, persist milestones, and run one fresh boundary review.
- `skeleton` - build the thinnest end-to-end running spine fast, zero ceremony, verify once that it runs, hand off. The compressed front-half of `slice`.
- `slice` - implement one bounded, verifiable increment (walking-skeleton first), verify with an executable check, log to the decision ledger, halt.
- `slice-review` - review the landed slice in exactly one round under a constrained finding-contract; empty findings = PASS.
- `slice-loop` - high-assurance autonomous feature execution: orchestrate slice ⇄ slice-review via worker subagents with quality audits at every handoff.
- `care` - inject the "what you care about" index: ~40 named failure/quality anchors (bad inputs, races, instance death, tenancy, seams...) that widen the active agent's attention before a review or a thicken run. Point it at a custom index (`/care path/to/index.md`, or a name in `$AGENT_HOME/care/`) to swap in a domain-specific list. A lens, not a license - findings still need the finding-contract, and implementation-side concerns go to Deferred, never into unasked code.

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

Override by exporting `AGENT_HOME` before launching your agent harness - e.g. `export AGENT_HOME="$HOME/Dropbox/Notes/agent"` to sync plans across machines.

## Permissions

Every `/bdx:*` skill fires `bd` subcommands and writes to `$AGENT_HOME/`. The Quickstart installer configures both Claude Code and Codex automatically.

For Claude Code, the installer merges this into `~/.claude/settings.json`:

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

For Codex, the installer appends an idempotent managed block to `$CODEX_HOME/rules/bdx.rules` (`CODEX_HOME` defaults to `~/.codex`):

```python
prefix_rule(
    pattern = ["bd"],
    decision = "allow",
    justification = "bdx skills use Beads task tracking and its configured Dolt store",
    match = ["bd ready", "bd show bd-123", "bd dolt push"],
    not_match = ["bdx ready"],
)
```

Codex loads user rules at startup, so restart it after installing bdx. The exact-token `bd` prefix does not allow similarly named commands such as `bdx`.

The rule **pre-approves** an explicit host-execution request; it does not automatically move a default shell call outside Codex's workspace sandbox. Every bdx skill that invokes `bd` therefore carries a Codex-only execution contract requiring `sandbox_permissions: "require_escalated"` (and `prefix_rule: ["bd"]` for direct commands). This includes read-only commands because a sandboxed process cannot reach a host Dolt listener on loopback. Claude Code and other harnesses ignore that Codex-only contract and continue using their normal execution path.

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

- **`SessionStart`** → `capture-session-id.sh` records a harness-qualified identity such as `"claude-code:<uuid>"` or `"codex:<uuid>"` for `sessions:` frontmatter. It exports `$BDX_SESSION_ID` when the host supports persistent hook environment updates and otherwise injects the value into session context. Set `BDX_HARNESS=<slug>` to identify another hook-compatible host; undetected hosts use `"unknown:<id>"`.
- Resume a recorded session by splitting the prefix from the id: `claude --resume <id>` for `claude-code:` or `codex resume <id>` for `codex:`.
- **`SessionStart`** → `bdx-ensure-agent-home.sh` resolves `$AGENT_HOME`, auto-creates the subdir layout, and exports the value.
- **`SessionStart:startup`** → `bd-auto-attach.sh` if `$BD_ID` is set, auto-loads plan/context/summary, appends the harness-qualified session identity to `sessions:`, flips bd status `open → in_progress`, and emits the bundle as `additionalContext` on turn 1.
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
