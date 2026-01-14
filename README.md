# Agent Pipelines

Agent Pipelines is a Claude Code plugin for building and running [Ralph Loops](https://ghuntley.com/ralph/). It adds a composable engine that lets you:

- **Loop on anything.** Each stage can iterate on plan files, task queues, codebases, URL lists, CSVs. Whatever.
- **Chain stages together.** Planning → task refinement → implementation.
- **Mix providers across stages.** Use Claude for planning and Codex for implementation in the same workflow.
- **Run providers in parallel.** Spin up Claude and Codex on the same stage, have each iterate separately, then synthesize the results.
- **Stop when it makes sense.** Fixed count, two-agent consensus, or queue empty.

## Install

```bash
claude plugin marketplace add https://github.com/hwells4/agent-pipelines
claude plugin install agent-pipelines@dodo-digital
```

**Dependencies:** [`tmux`](https://github.com/tmux/tmux), [`jq`](https://github.com/jqlang/jq), [`yq`](https://github.com/mikefarah/yq), [`bd`](https://github.com/steveyegge/beads) (beads CLI)

## Example

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Stage 1         │     │ Stage 2         │     │ Stage 3         │
│ ─────────────── │     │ ─────────────── │     │ ─────────────── │
│ Plan            │ ──▶ │ Refine Tasks    │ ──▶ │ Implement       │
│ 5 iterations    │     │ 5 iterations    │     │ until empty     │
│ judgment stop   │     │ judgment stop   │     │ queue stop      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```
## This is a Pipeline

Each stage in a pipeline is its own Ralph loop. It takes inputs, manages its own state, and when it finishes, passes outputs and accumulated learnings to the next stage. The stages are independent, so one can use Claude for planning while the next uses Codex for implementation.

Each iteration spawns a fresh agent that reads a progress file containing accumulated learnings, patterns discovered, and work completed.

## How Stages Work

A stage has three parts: a prompt template, a provider, and a termination strategy.

**Prompt templates** are standardized prompts that receive context about the current session: what iteration you're on, where to read inputs, where to write outputs. You can inject additional context about the specific task, which makes stages reusable across different projects.

**Providers** are the AI agents that execute each iteration. Claude Code is the default, but you can also spin up Codex agents. The orchestrator is always Claude Code, but the workers can be either.

**Termination strategies** determine when a stage stops:

| Strategy | How it stops | Use it for |
|----------|--------------|------------|
| **Fixed** | After exactly N iterations | Traditional Ralph loops |
| **Judgment** | When two agents independently agree they've plateaued | Planning, exploration, subjective quality |
| **Queue** | When an external task queue is empty | Working through beads |

Judgment requires two-agent consensus because one agent might think the plan is done while the second catches what's missing.

## Commands

| Command | Purpose |
|---------|---------|
| `/sessions` | Start, list, monitor, and kill running pipelines |
| `/sessions plan` | Turn a feature idea into a PRD and break it into tasks |
| `/refine` | Run plan and task refinement until two agents agree it's ready |
| `/ralph` | Work through a task queue until it's empty |
| `/pipeline` | Create custom stages and pipelines |

## Built-in Pipelines

| Pipeline | What it does |
|----------|--------------|
| `refine` | 5 plan iterations → 5 task iterations |
| `ideate` | 3 brainstorming iterations |
| `bug-hunt` | Discovery (8) → Triage (2) → Refine (3) → Fix (25) |

## Built-in Stages

| Stage | Stops when | Purpose |
|-------|------------|---------|
| `ralph` | Fixed N | Work through tasks in a beads queue |
| `improve-plan` | 2 agents agree | Read a plan, find gaps, add detail |
| `refine-tasks` | 2 agents agree | Split large tasks, merge small ones, clarify scope |
| `elegance` | 2 agents agree | Look for unnecessary complexity and remove it |
| `bug-discovery` | Fixed N | Explore the codebase with no agenda, just looking for what's wrong |
| `bug-triage` | 2 agents agree | Group related bugs, find patterns, design fixes |
| `idea-wizard` | Fixed N | Brainstorm improvements and rank them |
| `research-plan` | 2 agents agree | Search the web to fill gaps in a plan |
| `test-scanner` | 2 agents agree | Find untested code paths and edge cases |

## Parallel Execution

Sometimes you want multiple perspectives on the same problem. Parallel blocks let you spin up different providers (Codex with extra-high reasoning and Claude Opus, for example), have each iterate on a plan separately, then bring the results together in a final synthesis stage.

Each provider runs in isolation with its own progress file, so they don't influence each other mid-loop. The orchestrator waits for all providers to finish before moving to the next stage.

## More Than Work

Ralph loops can do more than implement tasks. Try them for plan refinement, bug review, research iteration, or codebase exploration. Anywhere multiple passes improve quality, loops help.

## Getting Started

```bash
claude plugin marketplace add https://github.com/hwells4/agent-pipelines
claude plugin install agent-pipelines@dodo-digital
```

Then in Claude Code:
1. `/sessions plan` - describe your feature, get a PRD and tasks
2. `/refine` - iterate on the plan until two agents agree it's solid
3. `/ralph` - implement the tasks until the queue is empty

Pipelines run in tmux, so they keep going even if you close Claude Code.

---

**Full reference:** [CLAUDE.md](CLAUDE.md)

## License

MIT
