# Agentic coding loops: why rigorous loops take all day

Research date: 2026-08-06

## Bottom line

`slice-loop` is slow for a structural reason: it is a high-assurance workflow that serially repeats implementation, executable verification, deliberate test mutation, self-review, fresh-context audit, durable bookkeeping, and periodic cold handoff. That is a defensible way to handle risky changes. It is not a good default throughput path for ordinary feature work.

The strongest first-party evidence is almost a controlled comparison of this exact design. Anthropic's planner/generator/evaluator application harness took **6 hours and $200**, versus **20 minutes and $9** for a solo agent. The evaluator version was better, but it was more than 20 times as expensive. With a stronger model, Anthropic then removed the sprint construct and changed from per-sprint evaluation to one end-of-run evaluator pass. Their conclusion was that an evaluator is useful only beyond the boundary of what the current model handles reliably alone; inside that boundary it is unnecessary overhead. ([Anthropic, 2026](https://www.anthropic.com/engineering/harness-design-long-running-apps))

So the answer to “am I missing something?” is: probably not a magic optimization. The workflow is buying assurance with latency exactly as designed. The likely mistake is using the maximum-assurance path too broadly.

## What the primary sources agree on

### 1. Every extra agentic layer must earn its latency

Anthropic explicitly says agentic systems trade latency and cost for performance, prompt chaining trades latency for accuracy, and complexity should be added only when it demonstrably improves outcomes. Evaluator-optimizer loops are a fit only when evaluation criteria are clear and repeated refinement has measurable value. ([Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents))

The Agentless research system reached competitive repository-repair results with a deliberately simple localization → repair → validation pipeline, showing that complex autonomous control is not automatically better than a small, interpretable workflow. ([Xia et al., 2024](https://arxiv.org/abs/2407.01489))

Practical implication: maintain a solo baseline. Add planner, per-slice reviewer, mutation probe, or checkpoint audit only where an evaluation shows that layer catches material failures the simpler path misses.

### 2. Nested evaluator loops multiply wall-clock time

Anthropic's frontend generator/evaluator used 5–15 cycles and took up to four hours because each evaluator actively drove the application. In its full-stack experiment, each sprint negotiated a contract, implemented it, self-evaluated, underwent separate QA, and iterated until it passed. The resulting harness was “bulky, slow, and expensive.” Anthropic later removed sprint decomposition and moved evaluation to a single end-of-run pass on the stronger model. ([Anthropic, 2026](https://www.anthropic.com/engineering/harness-design-long-running-apps))

This is directly relevant to `slice-loop`: a default run may land eight slices; every slice invokes `slice` and `slice-review`; every worker handoff invokes a fresh `quality-audit`; and all workers run serially. Each slice also proves its check can fail, then the review runs another mutation probe. The cost is not just “coding eight small changes.” It is several complete feedback cycles around each change, plus fresh-agent rereads every few slices.

### 3. Bound work by outcomes, iterations, and no-progress conditions

Anthropic recommends environmental ground truth on each step, human checkpoints for blockers or judgment, and explicit stopping conditions such as a maximum number of iterations. ([Building Effective Agents](https://www.anthropic.com/engineering/building-effective-agents)) Its managed outcome loops default to three evaluation iterations and cap them at twenty. ([Claude managed-agent outcomes](https://platform.claude.com/docs/en/managed-agents/define-outcomes)) OpenAI's Agents SDK likewise treats `max_turns` as a normal guard and raises `MaxTurnsExceeded`; unlimited turns are an explicit opt-out. ([OpenAI Agents SDK](https://openai.github.io/openai-agents-python/running_agents/))

An iteration cap alone is not enough. A useful loop should also stop when the same failure recurs, a correction has failed twice, the acceptance criterion is ambiguous, or the next action requires product judgment. Claude Code's first-party guidance says that after more than two corrections on the same issue, a fresh context with a better prompt generally beats continuing through accumulated failed approaches. ([Claude Code best practices](https://code.claude.com/docs/en/best-practices))

### 4. Task sizing matters more than elaborate orchestration

OpenAI says Codex works best on well-scoped work comparable to about one teammate-hour or a few hundred lines, with a large change planned before implementation and prompts structured like a good issue: files, constraints, examples, and acceptance criteria. ([How OpenAI uses Codex](https://openai.com/business/guides-and-resources/how-openai-uses-codex/)) Claude Code similarly recommends a self-contained spec that names files and interfaces, says what is out of scope, and ends with an end-to-end verification step. ([Claude Code best practices](https://code.claude.com/docs/en/best-practices))

This does not mean every acceptance criterion should become several tiny slices. Excessively fine slicing creates repeated discovery, test startup, mutation, review, logging, and handoff costs. A better unit is one coherent behavior with one externally observable acceptance criterion, not one file, layer, or checklist item.

### 5. Verification needs a cheap inner loop and a broader outer loop

Long-running work needs a reliable test oracle: an existing suite, a reference implementation, or a measurable objective. Anthropic recommends continuously growing the tests but gives a deliberately narrow pre-commit example, `pytest tests/ -x -q`, so feedback stops at the first failure. ([Long-running Claude for scientific computing](https://www.anthropic.com/research/long-running-Claude)) OpenAI's agent-first repository likewise made UI state, logs, metrics, and traces directly legible so agents could reproduce and validate behavior without waiting on humans. ([Harness engineering](https://openai.com/index/harness-engineering/))

The implication is two-speed verification:

- Inner loop: the smallest deterministic test, typecheck, healthcheck, or scenario that proves the current behavior.
- Outer loop: the broader suite and fresh-context review at a meaningful phase or final boundary.

Running broad tests, deliberate mutation, same-context review, and independent audit on every tiny edit is assurance stacking. It is appropriate for security, tenancy, money, deletion, migrations, and otherwise poorly observable behavior; it is usually excessive for ordinary product plumbing with a strong test oracle.

### 6. Fresh context is useful, but handoffs are not free

Anthropic identifies context rot and recommends compaction, structured notes, and fresh subagents for long-horizon work. ([Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)) Its later harness study says full resets can improve coherence but add orchestration complexity, token overhead, and latency, and it removed resets when the stronger model no longer needed them. ([Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps))

OpenAI's Codex harness similarly uses a short `AGENTS.md` as a map into progressively disclosed repository docs rather than loading a monolithic manual, and keeps execution plans and decision logs as durable repository artifacts. ([Harness engineering](https://openai.com/index/harness-engineering/))

`slice-loop` already gets the durable-state part right: plan boxes, decision rows, bd comments, and handoff reports make work recoverable. The questionable part is retiring workers after a fixed three-slice quota regardless of actual context health. Fixed-count resets can repeatedly pay cold-read cost even when a worker remains coherent.

### 7. Parallelism should follow dependency structure

Anthropic reports that parallel subagents dramatically improve breadth-first research, but use about fifteen times the tokens of chat and are a poor fit when agents share context or have many dependencies. It specifically notes that most coding tasks have fewer truly parallelizable branches than research. ([Multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system))

OpenAI's Symphony uses the issue tracker as a dependency graph: unblocked tasks run concurrently in isolated workspaces, while dependent tasks wait. ([Symphony](https://openai.com/index/open-source-codex-orchestration-symphony/)) Claude Code recommends parallel worktrees for independent sessions and a fresh writer/reviewer pattern for final review. ([Claude Code best practices](https://code.claude.com/docs/en/best-practices))

The right parallelism is therefore not “run dependent slices simultaneously.” It is:

- parallel discovery, documentation lookup, or alternative prototypes;
- parallel work on truly independent issue-graph branches in isolated worktrees;
- one fresh reviewer while the main worker is otherwise idle;
- sequential work for tightly coupled state or causal debugging.

## Comparison with the current bdx skills

| Current mechanism | What it buys | Why it is slow | Evidence-aligned adjustment |
| --- | --- | --- | --- |
| `slice`: smallest verifiable increment | Tight scope and visible proof | Repeats setup and a red/green mutation for every small increment | Size slices around one coherent behavior, not one implementation layer |
| `slice-review` after every slice | Catches local defects | Same-context review is explicitly considered weak, yet it also runs another mutation probe | Keep for high-risk slices; otherwise rely on the deterministic check and one fresh review at the phase boundary |
| Fresh `quality-audit` every worker handoff | Independent mechanism review | Cold reread plus possible test execution every few slices | Audit once per meaningful phase/final boundary unless evidence marks the region risky |
| Worker retirement after three slices | Avoids context degradation | Fixed cold-start tax even when context is healthy | Rotate on measured context/no-progress signals or at a coherent phase seam |
| Strictly serial workers | Prevents edit conflicts and respects dependencies | Total duration is the sum of every implementation and review cycle | Express the plan as a dependency graph and parallelize only independent branches |
| `--max 8` and H1–H7 | Prevents runaway work | Bounds slices, not turns, test runtime, or repeated no-progress attempts | Add per-worker turn/runtime budgets and a “same failure twice” halt |
| Durable plan, ledger, bd comments | Reliable recovery and auditability | Some bookkeeping and reread cost | Keep; this is well aligned with both Anthropic and OpenAI guidance |
| `--fast` changes model tier/quota | Reduces inference cost | Leaves the expensive per-slice review and checkpoint topology intact | Treat it as a cost preset, not a latency preset |

The comparison above is an inference from the cited sources and the current files `skills/slice-loop/SKILL.md`, `skills/slice/SKILL.md`, `skills/slice-review/SKILL.md`, and `skills/quality-audit/SKILL.md`; it is not a benchmark of bdx itself.

## Recommended operating model

### Default feature path

1. Clarify acceptance criteria and settle consequential design questions.
2. Build the thinnest end-to-end path with `skeleton` or one coherent implementation pass.
3. Continue in coherent behavioral chunks, each with a narrow deterministic check.
4. Run the broader suite at a phase boundary.
5. Run one fresh-context `quality-audit light` or code review over the phase/final diff.
6. Fix only demonstrated correctness or requirement gaps; allow at most two repair cycles before returning to a human with evidence.

### Use full `slice-loop` when

- the change touches authorization, tenancy, money, destructive operations, data migrations, or reliability boundaries;
- the acceptance signal is weak or subjective;
- the work must be defended increment by increment;
- the feature is beyond what the selected model has handled reliably alone;
- a failed slice is expensive enough that repeated independent assurance is worth the latency.

### If using `slice-loop` now

- Make the plan's boxes vertical outcomes, not separate code/test/docs layers.
- Use the narrowest relevant test per slice; reserve the full suite for phase/final gates.
- Prefer `--fast` only for a settled, mechanical plan; it does not remove structural review latency.
- Consider `--audit-every 2` for low-risk mechanical phases, accepting the explicitly reduced independent coverage; never thin audits for security, tenancy, money, or deletion work.
- Stop after two failed correction cycles on the same issue and restart with a sharper task or ask for human judgment.
- Split independent plan branches into separate tracked tasks/worktrees rather than serializing all of them through one loop.

## Measure before redesigning

Instrument a representative run with one duration per stage:

- worker boot and repository orientation;
- implementation/tool time;
- targeted verification;
- deliberate mutation probes;
- same-context slice review;
- checkpoint audit;
- full-suite/CI time;
- issue/ledger/handoff bookkeeping;
- retries and repeated failure signatures.

Then compare three modes on similar completed tasks: solo implementation + final review; skeleton + phase review; full slice-loop. Track acceptance-test pass, material post-review defects, rework, total agent turns, test invocations, and wall-clock duration. Remove a layer only when the simpler mode preserves the outcomes you care about. This follows Anthropic's recommendation to re-examine harness components as models improve and strip away pieces that are no longer load-bearing. ([Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps))

## Conclusion

The repo is not missing an outer-loop trick. It is applying a high-assurance stack to each small increment, then applying another independent assurance layer every few increments, all serially. Half-day feature runs are a predictable result.

The better default is **one capable implementer, narrow executable feedback while building, and one fresh independent review at a meaningful boundary**. Keep `slice-loop` as the expensive mode for changes whose risk justifies it.
