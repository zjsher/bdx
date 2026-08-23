# bdx

**Two coding disciplines that compose with Beads without replacing any part of it.**

bdx adds exactly two skills:

- `build-loop`: convert one settled Bead into a behavior/invariant/seam/proof
  contract, implement it with tight executable feedback, and gate the result.
- `quality-audit`: give the resulting code change one fresh-context, repro-gated
  security, performance, correctness, and maintainability review.

[Beads](https://github.com/gastownhall/beads) remains the complete work system. Its
[official skill](https://github.com/gastownhall/beads/tree/main/plugins/beads/skills/beads)
owns issue creation, planning fields, dependencies, claiming, notes, handoffs,
resumability, decisions, closure, history, memory, collaboration, and integrations.
bdx neither re-documents nor wraps those capabilities.

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

1. Use the official Beads workflow to select, define, and claim work.
2. Invoke `/bdx:build-loop <bead-id>` when the outcome is settled and can be proven
   with deterministic checks.
3. The build loop invokes `/bdx:quality-audit light` at its milestone boundary.
4. Return the evidence and remaining frontier to the official Beads workflow, which
   decides how to persist, split, block, hand off, or close the work.

bdx does not carry a second lifecycle between steps 1 and 4.

## Responsibility boundary

| Concern | Owner |
| --- | --- |
| Work selection, issue quality, task state, planning fields | Beads |
| Dependencies, resumability, handoffs, decisions, closure | Beads |
| Durable project memory and collaboration | Beads |
| External integrations and synchronization | Beads |
| Behavior/invariant/seam/proof implementation discipline | `build-loop` |
| Independent adversarial code review | `quality-audit` |

The distinction matters: Beads’ `audit` command records agent interactions, while
bdx’s `quality-audit` reviews a code change and requires executable evidence for a
confirmed finding. They solve different problems.

## Skills

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

- No Markdown task plans, context dumps, or completion summaries.
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

The test suite validates both plugin manifests, the exact two-skill surface, the
absence of hooks and provider-specific code, and the delegation boundary with the
official Beads workflow.

## License

MIT
