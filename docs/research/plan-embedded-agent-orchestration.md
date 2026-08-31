# Plan-embedded agent orchestration: common shape, framework-specific contract

Research date: 2026-08-31

## Bottom line

Embedding machine-readable YAML beside natural-language Markdown is an established and increasingly common agent-authoring pattern. A versioned list of phases with dependencies, assigned agents or skills, approval gates, and completion checks also uses concepts shared by mature workflow systems.

The proposed `Orchestration` block is **not an industry-standard agent-orchestration format**, however. It would be a bdx-specific declarative DSL with good industry precedent. No reviewed standard defines this combination of `phases`, `pre_skills`, `runner.skill`, `done_when`, `proof`, `human_gate_after`, and `finish.skills`, and no major agent runtime could execute it without a bdx adapter.

That is not a reason to avoid it. It is a reason to name it honestly—**bdx orchestration manifest v1**—and specify the execution semantics that the attractive YAML currently leaves implicit.

## What is actually converging

| Source | Authoring and execution model | What it establishes |
| --- | --- | --- |
| OpenAI Codex | `AGENTS.md` supplies layered project instructions; reusable skills are `SKILL.md` files; subagent delegation is requested in prompts or instructions and orchestrated by Codex; project custom agents are TOML files. | Markdown instructions, reusable skills, specialized runners, and subagents are first-class, but Codex does not define a plan-embedded phase/DAG schema. ([AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [skills](https://learn.chatgpt.com/docs/build-skills), [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)) |
| Agent Skills | A standardized `SKILL.md` has constrained YAML frontmatter plus an unrestricted Markdown instruction body. The standard covers capability packaging and discovery, not orchestration graphs. | YAML metadata plus Markdown is portable; arbitrary workflow topology is not. Its skill `name` grammar allows lowercase letters, numbers, and hyphens—not host-qualified names such as `bdx:care`, which therefore remain a bdx/Codex resolution convention. ([specification](https://agentskills.io/specification)) |
| GitHub custom agents | An agent profile is Markdown with YAML frontmatter for description, model, tools, MCP servers, and invocation policy, followed by behavioral instructions. | Strong cross-product precedent for one human-readable file that combines structured agent configuration and prose, but it defines one agent rather than a multi-phase plan. ([configuration](https://docs.github.com/en/copilot/reference/custom-agents-configuration)) |
| GitHub Agentic Workflows (`gh-aw`) | A Markdown workflow contains YAML frontmatter for triggers, permissions, tools, engine, jobs, timeouts, and outputs, then Markdown instructions; a compiler validates it and produces an executable Actions lockfile. Custom jobs support `needs` and `if`. | This is the closest direct precedent for bdx: declarative YAML and natural-language instructions in one Markdown source, with a validator/compiler and an external runtime. Its schema is still GitHub-specific. ([workflow structure](https://github.github.com/gh-aw/reference/workflow-structure/), [jobs](https://github.github.com/gh-aw/reference/steps-jobs/)) |
| CrewAI | Current projects use ordered JSONC task definitions; classic YAML remains supported. Tasks define description, expected output, agent, upstream context, human review, guardrails, retries, and output shape. Crews select sequential or hierarchical processes, while Flows use code for event-driven branching and state. | Task, runner, dependency, completion contract, human review, validation, and retry are common concepts, but even one framework has evolved between YAML, JSONC, and code-first orchestration. ([tasks](https://docs.crewai.com/en/concepts/tasks), [processes](https://docs.crewai.com/en/concepts/processes), [flows](https://docs.crewai.com/en/concepts/flows)) |
| LangGraph | `StateGraph` composes typed state, function nodes, and normal or conditional edges in code. Checkpoints persist run state; interrupts pause and resume for human input; retry, timeout, and error-handler policies are explicit per node. | Production orchestration requires more than topology: durable state, pause/resume, retry classification, timeouts, and post-exhaustion behavior are part of the contract. LangGraph expresses those semantics in code, not YAML. ([Graph API](https://docs.langchain.com/oss/python/langgraph/graph-api), [persistence](https://docs.langchain.com/oss/python/langgraph/persistence), [interrupts](https://docs.langchain.com/oss/python/langgraph/interrupts), [fault tolerance](https://docs.langchain.com/oss/python/langgraph/fault-tolerance)) |

The common vocabulary is therefore real:

- phase/task/node;
- dependency/edge/`needs`/context;
- runner/agent/engine/skill;
- expected output, guardrail, check, or artifact;
- human approval or interrupt;
- retries, timeouts, failure routing, and cancellation;
- run ID, state, checkpoints, attempts, and resumability.

The syntax and exact semantics are not shared.

## What MCP and A2A do—and do not—standardize

MCP standardizes how an LLM host integrates external resources, prompts, and tools. Its architecture explicitly leaves complex orchestration with the host; its newer optional extensions add asynchronous task handles and skills-over-MCP, but do not define a plan DAG authoring format. ([MCP specification](https://modelcontextprotocol.io/specification/latest), [architecture](https://modelcontextprotocol.io/specification/2026-07-28/architecture))

A2A 1.0 standardizes communication between independent, opaque agent systems: discovery, messages, artifacts, long-running task state, streaming, cancellation, and input/auth-required interruptions. Its “opaque execution” principle means collaborating agents need not expose internal plans, memory, tools, or implementation. It is a wire protocol around a task, not a format for the task's internal phases. ([A2A 1.0 specification](https://a2a-protocol.org/latest/specification/))

Neither standard makes the proposed manifest portable. They could become runner transports beneath it.

## Gaps in the proposed v1 contract

| Current field or shape | Ambiguity to settle before execution |
| --- | --- |
| `strategy: sequential` plus `depends_on` | Listed order and dependency edges are two scheduling authorities. Choose one. A clean model is a DAG with `max_parallel: 1` for today's shared-workspace execution; reject cycles and unknown dependencies at validation time. |
| `runner.skill` plus free-form `args` | Define whether `args` is prompt text, a shell-like string, or parsed parameters. Prefer `prompt:` for opaque agent text or a typed `with:` mapping; never silently interpret it as shell. Define how host-qualified skill names resolve and whether plugin/skill versions can be pinned. |
| `pre_skills` | Define ordering, failure behavior, output propagation, and whether these run in the same agent context as the runner. Otherwise a context-injection skill such as `care` may not influence the worker it is meant to prime. |
| `entry_gate` and `done_when` | These are useful acceptance statements but not deterministic predicates. Separate descriptive `acceptance:` from executable `checks:` and explicit human `approval:`. Record which evaluator decides each item and what evidence it emits. |
| `proof: ["command"]` | Define working directory, environment, timeout, expected exit/result, permission behavior, and evidence capture. Placeholders such as `<project>` should fail validation in an executable plan. |
| `human_gate_after: true` | A boolean omits who may decide, the prompt/evidence shown, approve/reject/modify outcomes, timeout, and resume behavior. An approval must durably pause the run and preserve the decision. GitHub Actions environments and LangGraph interrupts both treat approval as runtime state, not just a label. ([GitHub environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments), [LangGraph interrupts](https://docs.langchain.com/oss/python/langgraph/interrupts)) |
| No retry/error policy | Define attempt limits, retryable failures, backoff, timeout, `halt`/`continue`/fallback behavior, and idempotency expectations. CrewAI guardrail retries and LangGraph retry/timeout/error-handler composition show that these are separate concerns. |
| No run-state model | Define phase states, attempts, evidence, approval decisions, run identity, crash recovery, and resume rules. Keep this runtime journal separate from the immutable manifest and choose one canonical store; do not duplicate it across Beads, plan fields, and logs. |
| `finish.skills` | Define ordering and conditions. `summarize` and `close` must run only after required phases and the audit pass; cleanup or a failure dump belongs in an explicit `always`/`on_failure` path. |
| `version: 1` only | Separate manifest API version from executor and invoked-skill compatibility. A v1 document can still change behavior if `bdx:build-loop` resolves to a materially different installed version. |

## Recommendation for `bdx:plan`

Adopt the feature, but position it as a **small, validated bdx DSL inspired by agentic workflow conventions**, not as standards compliance.

For v1:

1. Generate exactly one machine-readable YAML document under a fixed `## Orchestration` heading, in a fenced `yaml` block. Do not support both an in-body block and a second frontmatter representation. GitHub Agentic Workflows and Agent Skills put configuration in frontmatter, but bdx frontmatter already serves Beads/Obsidian indexing and contains tool-maintained projections; keeping the executable definition in its own section preserves that ownership boundary.
2. Give it an unambiguous identity such as `api_version: bdx.dev/orchestration/v1` and publish a JSON Schema plus a validator. Validation should catch duplicate IDs, cycles, missing dependencies, invalid skill references, unresolved command placeholders, malformed gates, and an unreachable or unconditional close.
3. Use one topology model. Recommended: `strategy: {kind: dag, max_parallel: 1}` plus `needs:`. This represents a linear plan without preventing safe independent branches later.
4. Keep three completion lanes distinct: natural-language `acceptance`, deterministic `checks`, and durable human `approval`. A phase completes only when every required lane passes.
5. Add default and per-phase `timeout`, `retry`, and `on_failure` policies. Default to one attempt and halt unless a phase explicitly declares safe retry semantics.
6. Specify an external, append-only runtime record with run/phase/attempt IDs, timestamps, evidence references, failures, and approval decisions. The plan owns the definition; the run record owns execution state; Beads continues to own task status.
7. Compile each phase to a concrete invocation contract before executing it. Treat skills as bdx runner references, not as a portable Agent Skills field. Record the resolved runner/skill version in the run record.
8. Make the finish path conditional: audit, require audit success, summarize, then close. Define separate `on_failure` and `always` hooks.

Start narrow. A sequential/DAG executor over explicit bdx skill invocations, deterministic checks, and human gates is enough for v1. Conditional branching, parallel write workers, compensation, dynamic task generation, and cross-agent A2A runners should wait until the runtime state and failure model are proven.

## Verdict

The best classification is:

- **Markdown + YAML for agent configuration:** established convention;
- **tasks, dependencies, runners, gates, and checks:** common orchestration vocabulary;
- **this exact plan-embedded schema:** framework-specific bdx DSL;
- **cross-vendor standard for internal agent plans:** does not currently exist in the reviewed primary sources.

The proposed block is therefore directionally aligned with the industry and unusually readable. Its value comes from being a crisp bdx contract—not from pretending other runtimes already understand it.
