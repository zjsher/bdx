# bdx

**Thin Beads ergonomics plus focused build and review disciplines.**

bdx adds six skills:

- `plan`: shape implementation-ready work in native Beads fields and relationships.
- `dump`: append a compact, resumable handoff to a native Bead.
- `close`: verify completion, persist final evidence, and close through Beads.
- `render`: open a disposable Markdown view of a Bead and its referenced Beads.
- `build-loop`: convert one settled Bead into a behavior/invariant/seam/proof
  contract, implement it with tight executable feedback, and gate the result.
- `quality-audit`: give the resulting code change one fresh-context, repro-gated
  security, performance, correctness, and maintainability review.

[Beads](https://github.com/gastownhall/beads) remains the complete work system. Its
[official skill](https://github.com/gastownhall/beads/tree/main/plugins/beads/skills/beads)
owns issue creation, planning fields, dependencies, claiming, notes, handoffs,
resumability, decisions, closure, history, memory, collaboration, and integrations.
The thin bdx lifecycle skills compose those capabilities without replacing their
storage, semantics, or command guidance.

## Install

Install Beads and its official skill first. Run `bd setup` for each agent harness and
follow the current output of `bd prime`; Beads intentionally treats that generated
guidance as the CLI source of truth.

Install bdx for Claude Code:

```bash
claude plugin marketplace add zeejers/bdx
claude plugin install bdx@bdx-marketplace
```

Or for Codex:

```bash
codex plugin marketplace add zeejers/bdx
codex plugin add bdx@bdx-marketplace
```

## Workflow

1. Use `/bdx:plan` when work needs to be shaped into native Beads fields and links.
2. Use the official Beads workflow to select and claim work.
3. Invoke `/bdx:build-loop <bead-id>` when the outcome is settled and can be proven
   with deterministic checks.
4. The build loop invokes `/bdx:quality-audit light` at its milestone boundary.
5. Use `/bdx:dump` to pause with a durable handoff or `/bdx:close` to verify and
   finish the Bead. Use `/bdx:render` whenever a disposable joined view helps.

Every durable write in this flow lands in Beads.

## Responsibility boundary

| Concern | Owner |
| --- | --- |
| Work selection, issue quality, task state, planning fields | Beads |
| Dependencies, resumability, handoffs, decisions, closure | Beads |
| Durable project memory and collaboration | Beads |
| External integrations and synchronization | Beads |
| Planning, handoff, and closure ergonomics | `plan`, `dump`, and `close`, backed by Beads |
| Disposable joined Markdown projection | `render` |
| Behavior/invariant/seam/proof implementation discipline | `build-loop` |
| Independent adversarial code review | `quality-audit` |

The distinction matters: Beads’ `audit` command records agent interactions, while
bdx’s `quality-audit` reviews a code change and requires executable evidence for a
confirmed finding. They solve different problems.

## Skills

### `/bdx:plan`

Create or refine an implementation-ready Bead using native description, design,
acceptance, and relationship data. It produces no plan file.

### `/bdx:dump`

Append a concise native handoff containing current state, evidence, decisions,
remaining work, and the exact next action.

### `/bdx:close`

Check the Bead's acceptance boundary, persist final evidence and follow-ups, then
close it through the current official Beads workflow. Failed proof leaves it open
with a durable handoff.

### `/bdx:render`

Traverse a Bead's native references cycle-safely, render every collected field and
comment to a unique file under the OS temp directory, and open it. The result is a
read-only snapshot and never becomes project state.

### `/bdx:build-loop`

The production-default implementation loop:

1. Accept one already-selected Bead and its settled outcome from the Beads workflow.
2. Lock `Behavior / Invariant / Seam / Proof` before editing.
3. Implement one coherent behavior at a time.
4. Run the tightest deterministic check after each behavior.
5. Run the broader gate and `/bdx:quality-audit light` at the milestone boundary.
6. Return observable evidence and the exact remaining frontier to Beads.

### `/bdx:quality-audit`

A fresh-context adversarial review with security, performance, correctness, and
maintainability lenses. Findings must name a concrete cost; only executable repros
earn `CONFIRMED`. `PLAUSIBLE` findings are advisory, and an empty list is a valid
pass.

## What bdx intentionally does not contain

- No durable Markdown task plans, context dumps, or completion summaries. `render`
  creates only a disposable read-only projection under the OS temp directory.
- No `$AGENT_HOME`, session registry, task database, launcher, or background process.
- No lifecycle hooks and no hooks that block native Beads commands.
- No duplicated Beads commands, field mappings, templates, or integration guidance.
- No provider credentials, API clients, state mappings, pollers, caches, or adapters.

This makes bdx integration-agnostic by construction: every integration supported by
the installed Beads version remains available without bdx knowing it exists.

Large specifications, ADRs, research reports, and customer documents may still be
Markdown when the document itself is a deliverable. They are not a parallel task
store.

## Development

```bash
make test
```

The test suite validates both plugin manifests, the exact six-skill surface, the
absence of hooks and provider-specific code, and the delegation boundary with the
official Beads workflow.

## License

MIT
