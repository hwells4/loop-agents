# AGENTS Constitution

Agent Pipelines agents are compilers for intent. This document is the constitution that constrains every run so agents can produce auditable, high-quality changes. For Codex-specific guidance (running pipelines without skills/hooks), see `docs/codex.md`.

## Execution Envelope

- **Access mode**: Start every run in read-only analysis. Escalate to write only after you know the target files and affected tests. Never run destructive git commands (reset/rebase) without explicit user approval.
- **Writable paths**: Only files inside this repository are writable. Treat the repo root as the sandbox; do not touch `~` except to read shared config under `~/.codex/`.
- **Network**: Assume network access is off. Do not hit remote resources (curl, package install, API calls) unless the task explicitly requires it and you have confirmed with the user.
- **Shell**: Default to `bash -lc "<command>"` with `set -euo pipefail` expectations mirrored in scripts.

## Definition of Done

Work is complete only after running the proof command below and reporting the result:

- **Proof command**: `scripts/tests/run_tests.sh --ci`
  - If a narrower target is provided (e.g., `./scripts/run.sh test staging --verbose`), run that too but the CI suite is the default.
- Capture stderr/stdout highlights for any failures and block closing the task until they are addressed or waivers are documented.

## Required Workflow Artifacts

Every run must produce:
1. **Short plan** outlining assumptions, affected subsystems, and the next discrete actions.
2. **Unified diff** (or summarized changes) tied to file paths so reviewers can grep the edits.
3. **Verification commands** exactly as executed (tests, lint, or formatters).
4. **Change narrative** explaining what changed and why, including any tradeoffs or skipped validations.

## Guidance & Input Contract

- Reference concrete repro data: failing test names, stack traces, file paths, and symbols. If the user cannot provide them, request the missing info rather than guessing.
- Keep instructions point-form. Skip narration and fluff; make everything greppable.
- When pulling context, prefer project primitives (`rg`, `scripts/run.sh status`, etc.) over ad-hoc commands to keep history consistent.

## Autonomy Ladder

- Begin in read-only or approval mode and earn trust by shipping repeatable loops (plan → edit → test).
- Once the workflow is stable (tests green twice in a row), you may automate that loop via scripts/pipelines, but reset to read-only whenever requirements change.

## Mission & Core Concepts

- Agent Pipelines is a Ralph loop orchestrator that runs autonomous tmux sessions where each iteration spins up a fresh agent to avoid context drift. Two-agent consensus (plateau completion) is the default guardrail against premature stopping.
- Everything is a pipeline: a loop is just a single-stage pipeline. Multi-stage pipelines chain prompts via `scripts/pipelines/*.yaml`, while single-stage configs live under `scripts/stages/<name>/`.
- Sessions write state into `.claude/pipeline-runs/{session}/`, including `progress-<session>.md`, per-iteration outputs, and `state.json` for crash detection/resume.

## CLI & Dependencies

Dependencies required on every workstation: `jq`, `claude`, `codex`, `tmux`, and `bd`. For Codex-specific guidance (running pipelines without skills/hooks), see `docs/codex.md`.

Common commands (all via `./scripts/run.sh`):

```bash
# Single-stage loop (3 paths)
./scripts/run.sh ralph auth 25
./scripts/run.sh loop ralph auth 25
./scripts/run.sh pipeline --single-stage ralph auth 25

# Multi-stage pipeline
./scripts/run.sh pipeline refine.yaml my-session

# Session ops
./scripts/run.sh ralph auth 25 --force        # override lock
./scripts/run.sh ralph auth 25 --resume       # continue crashed session
./scripts/run.sh status auth                  # inspect status/locks
./scripts/run.sh                              # list stages/pipelines

# Run under Codex provider
./scripts/run.sh ralph auth 25 --provider=codex --model=gpt-5.2-codex
```

## Skills & Slash Commands

Skills (under `skills/`) extend Codex/Claude; invoke them inside Claude via slash commands:

| Skill | Slash Command | Purpose |
|-------|---------------|---------|
| `start` | `/start [pipeline]` | Discover and launch pipelines |
| `sessions` | `/sessions [list|start]` | tmux session management |
| `work` | `/work [task]` | Quick-start Codex agent for implementation (fire-and-forget) |
| `monitor` | `/monitor [mode]` | Active debugging companion for pipeline sessions |
| `plan-refinery` | `/plan-refinery` | Iterative planning with Opus subagents |
| `create-prd` | `/agent-pipelines:create-prd` | Generate PRDs via guided discovery |
| `create-tasks` | `/agent-pipelines:create-tasks` | Break PRDs into beads |
| `pipeline-designer` | `/pipeline` | Architect new pipelines |
| `pipeline-creator` | `/pipeline create` | Scaffold stage.yaml + prompt.md |
| `pipeline-editor` | `/pipeline edit` | Modify existing stages/pipelines |
| `test-audit` | `/test-audit` | Audit test coverage and quality |
| `test-setup` | `/test-setup` | Set up testing infrastructure |

User-facing slash commands under `commands/` should be referenced verbatim:
- `/elegance`
- `/ideate`
- `/monitor`
- `/pipeline`
- `/ralph`
- `/readme-sync`
- `/refine`
- `/robot-mode`
- `/sessions`
- `/start`
- `/work`

## Termination Strategies

| Type | Behavior | When to Use |
|------|----------|-------------|
| `fixed` | Run exactly N iterations | Implementation loops, brainstorming |
| `judgment` | LLM judge evaluates progress; requires N consecutive stops | Plan refinement, review stages |
| `queue` | Stop when external queue (`bd ready`) is empty | Work-clearing loops |

**Judgment termination** uses an LLM judge to evaluate iteration history and trend detection. The judge auto-enables for `type: judgment` stages and analyzes status.json decisions to determine plateau.

```yaml
termination:
  type: judgment
  min_iterations: 2     # Start checking after this many
  consensus: 2          # Consecutive stops needed
  max: 10               # Hard cap (optional)
```

Agents write `status.json` with: `decision` (continue/stop/error), `reason`, `summary`, `work`, `errors`.

## Operational Playbooks

### Feature Implementation
1. `/sessions plan` or `/agent-pipelines:create-prd` → Gather requirements, save to `docs/plans/`
2. `/agent-pipelines:create-tasks` → Break PRD into beads tagged `pipeline/{session}`
3. `/refine` → Run refinement pipeline (default: 5+5 iterations)
4. `/ralph` → Run Ralph loop until all beads complete

### TDD Implementation
```bash
./scripts/run.sh pipeline tdd-implement.yaml my-feature
```
Stages: plan-tdd (5) → elegance (1) → create-beads (1) → refine-tasks (3) → ralph (30) → code-review (1) → test-review (1)

### Bug Hunting
```bash
./scripts/run.sh pipeline bug-hunt.yaml my-session
```
Stages: Discover (8) → Elegance (≤5) → Refine (3) → Fix (25)

### Test Coverage Discovery
```bash
./scripts/run.sh pipeline test-gap-discovery.yaml my-session
```
Stages: scan (3) → analyze (2) → plan (1)

### Parallel Documentation Audit
```bash
./scripts/run.sh pipeline parallel-docs.yaml my-session
```
Runs Claude and Codex in parallel to audit docs, then synthesizes and implements fixes.

### Critical Review
Use `fresh-eyes` stage with Codex xhigh reasoning for maximum scrutiny of plans before implementation.

## Debugging & Recovery

- Attach to tmux: `tmux attach -t pipeline-<session>`.
- Inspect progress/state: `cat .claude/pipeline-runs/<session>/progress-<session>.md` or `state.json | jq`.
- Resume after crash: rerun with `--resume`; engine tracks `iteration_started`/`iteration_completed`.
- Check session status: `./scripts/run.sh status <session>` shows locks, state, and progress.

### Session Locks

Locks prevent concurrent sessions with the same name. Uses flock when available, falls back to shlock or noclobber.

```bash
ls .claude/locks/                          # List active locks
cat .claude/locks/<session>.lock | jq      # View lock details (PID, start time)
./scripts/run.sh ralph auth 25 --force     # Override stale lock
```

When a stale lock is cleaned up, the engine releases any `in_progress` beads labeled `pipeline/<session>` back to `open`.

### Crash Recovery

Sessions automatically detect and recover from crashes (API timeouts, network issues, SIGKILL).

```bash
# After crash, resume from last completed iteration
./scripts/run.sh ralph auth 25 --resume

# For parallel blocks, completed providers are skipped on resume
./scripts/run.sh pipeline multi.yaml my-session --resume
```

## Providers & Models

Stages can use different AI providers. Claude Code is the default.

| Provider | CLI Flag | Default Model | Skip Permissions Flag |
|----------|----------|---------------|----------------------|
| Claude | `--provider=claude` | opus | `--dangerously-skip-permissions` |
| Codex | `--provider=codex` | gpt-5.2-codex | `--dangerously-bypass-approvals-and-sandbox` |

**Codex reasoning effort**: Use colon syntax `model:reasoning` (e.g., `gpt-5.2-codex:xhigh`). Levels: `minimal`, `low`, `medium`, `high` (default), `xhigh`. Reserve `xhigh` for 1-2 iteration tasks (plan synthesis, critical review). For 5+ iteration loops, use `medium` or `high`—xhigh cost/latency adds up fast.

## Environment & Context Variables

- Pipelines export `CLAUDE_PIPELINE_AGENT=1`, `CLAUDE_PIPELINE_SESSION`, and `CLAUDE_PIPELINE_TYPE`. Override defaults via `CLAUDE_PIPELINE_PROVIDER`, `CLAUDE_PIPELINE_MODEL`, `CLAUDE_PIPELINE_CONTEXT`, or CLI `--provider/--model/--context`. Precedence: CLI → env → pipeline config → stage config → defaults.
- Prompts should consume v3 template vars: `${CTX}` (context.json path), `${PROGRESS}`, `${STATUS}`, `${ITERATION}`, `${SESSION_NAME}`, `${CONTEXT}`, `${OUTPUT}`. Legacy names (`${SESSION}`, `${INDEX}`, etc.) still resolve but should be avoided.
- `context.json` describes inputs from CLI (`inputs.from_initial`), previous stages (`inputs.from_stage`), parallel providers (`inputs.from_parallel`), and command passthroughs (e.g., `.commands.test`). Read it with `jq` instead of hardcoding repo-specific assumptions.
- When exposing repo commands to agents, define them in pipeline/stage YAML (`commands.test`, `commands.lint`, etc.) or pass them via CLI `--command` overrides so Codex can run the correct tooling without guesswork.

## Parallel Blocks

Run multiple providers concurrently with isolated contexts. Each provider runs stages sequentially; providers execute in parallel.

```yaml
nodes:
  - id: dual-refine
    parallel:
      providers: [claude, codex]
      stages:
        - id: iterate
          stage: improve-plan
          termination: { type: judgment, consensus: 2, max: 5 }
  - id: synthesize
    stage: elegance
    inputs:
      from_parallel: iterate  # Reads outputs from both providers
```

Key behaviors:
- Providers have isolated progress/state (no cross-visibility within block)
- Block waits for all providers before proceeding
- Any provider failure fails the entire block
- On `--resume`, completed providers are skipped

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with git (run at session end)

For full workflow details: `bd prime`

## Specialized Agents

Agents live in `agents/` at the plugin root (per Claude Code plugin structure):

| Agent | Purpose |
|-------|---------|
| **pipeline-architect** | Design pipeline architectures, termination strategies, I/O flow, and parallel blocks. |
| **stage-creator** | Create stage.yaml and prompt.md files for new stages. |
| **pipeline-assembler** | Assemble multi-stage pipeline configurations. |

Invoke via Task tool: `subagent_type: "pipeline-architect"` with requirements summary.

## Available Stages

Stages are defined in `scripts/stages/<name>/`. Each has `stage.yaml` (config) and `prompt.md` (agent instructions).

### Implementation Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `ralph` | claude | fixed | The original Ralph loop—work through beads |
| `codex-work` | codex | fixed | Codex implementation agent |
| `tdd-work` | claude | fixed | Strict TDD implementation loop—tests first |

### Planning & Refinement Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `improve-plan` | claude | judgment | Plan refinement |
| `refine-tasks` | claude | judgment | Task/bead refinement |
| `research-plan` | claude | judgment | Research-driven planning |
| `create-tasks` | claude | fixed | Break plans into beads |
| `tdd-plan-refine` | claude | judgment | TDD plan refinement |
| `tdd-create-beads` | claude | fixed | Create beads for TDD workflow |

### Review & Quality Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `elegance` | claude | judgment | Code elegance review |
| `code-review` | claude | judgment | Implementation quality review |
| `fresh-eyes` | codex (xhigh) | judgment | Critical plan review with maximum reasoning |

### Testing Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `test-scanner` | claude | judgment | Test coverage gap discovery |
| `test-analyzer` | claude | judgment | Analyze and prioritize test gaps |
| `test-planner` | claude | fixed | Convert analysis into actionable beads |
| `test-review` | claude | judgment | Review test implementation quality |

### Bug & Discovery Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `bug-discovery` | claude | fixed | Fresh-eyes bug exploration |
| `bug-triage` | claude | judgment | Bug triage and fix design |
| `idea-wizard` | claude | fixed | Ideation and brainstorming |
| `idea-wizard-loom` | claude | fixed | Extended ideation with loom context |

### Documentation Stages
| Stage | Provider | Termination | Purpose |
|-------|----------|-------------|---------|
| `doc-updater` | claude | judgment | Systematically update documentation |
| `readme-sync` | claude | fixed | Keep README aligned with codebase |
| `robot-mode` | claude | fixed | Design CLI interfaces for agent ergonomics |

Use `./scripts/run.sh` (no args) to list all available stages and pipelines.

## Project Structure & Module Organization

```
scripts/
├── engine.sh                 # Unified pipeline engine
├── run.sh                    # CLI entry point (converts all commands to pipeline calls)
├── lib/                      # Shared utilities
│   ├── compile.sh            # Pipeline YAML→plan.json compilation
│   ├── context.sh            # v3 context.json generation
│   ├── deciders.sh           # Termination decision logic
│   ├── deps.sh               # Dependency checking (jq, tmux, etc.)
│   ├── events.sh             # Append-only event log (events.jsonl)
│   ├── judge.sh              # LLM judge for plateau detection
│   ├── list.sh               # List stages/pipelines
│   ├── lock.sh               # Session locking (flock-based)
│   ├── mock.sh               # Mock execution for testing
│   ├── notify.sh             # Desktop notifications + logging
│   ├── parallel.sh           # Parallel block execution
│   ├── paths.sh              # Path utilities
│   ├── progress.sh           # Accumulated context files
│   ├── provider.sh           # Provider abstraction (Claude, Codex)
│   ├── resolve.sh            # Template variable resolution
│   ├── result.sh             # Iteration result handling
│   ├── runtime.sh            # Unified v3 runtime executor
│   ├── spy.sh                # Debugging/inspection utilities
│   ├── stage.sh              # Stage loading utilities
│   ├── state.sh              # JSON iteration history + crash recovery
│   ├── status.sh             # v3 status.json validation
│   ├── test.sh               # Test framework utilities
│   ├── validate.sh           # Lint and dry-run validation
│   ├── yaml.sh               # YAML→JSON conversion
│   └── completions/          # Termination strategies
│       ├── beads-empty.sh    # Stop when queue empty (type: queue)
│       ├── plateau.sh        # Stop on consensus (type: judgment)
│       └── fixed-n.sh        # Stop after N iterations (type: fixed)
├── stages/                   # Stage definitions
├── pipelines/                # Multi-stage pipeline configs
├── prompts/                  # Shared prompt templates
└── tests/                    # Test suites and fixtures

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
agents/                       # Specialized agent definitions
docs/                         # Reference documentation
```

## Build, Test, and Development Commands

- `./scripts/run.sh pipeline bug-hunt.yaml overnight` — run the bundled multi-stage pipeline.
- `./scripts/run.sh loop ralph auth 25` — kick off a single stage in tmux (default).
- `./scripts/run.sh lint [loop|pipeline] [name]` — schema-check stage or pipeline definitions.
- `./scripts/run.sh test [name] --verbose` or `scripts/tests/run_tests.sh --ci` — execute regression suites.
- `./scripts/run.sh status <session>` — inspect locks before resuming or forcing reruns.
- `./scripts/run.sh list [count]` — list recent pipeline runs (default: 10).
- `./scripts/run.sh tail <session> [lines]` — stream event log for observability.

## Coding Style & Naming Conventions

Bash is the canonical implementation language; keep shebangs at `#!/bin/bash`, enable `set -euo pipefail`, and favor snake_case helpers that declare locals explicitly. YAML uses two-space indents, lowercase kebab-case directories, and descriptive `description` lines surfaced by `run.sh`. Prompts and Markdown should stay imperative and concise, mirroring the `commands/*.md` tone.

## Testing Guidelines

Shell suites follow the `scripts/tests/test_*.sh` pattern and rely on fixtures under `scripts/tests/fixtures`. Add or update fixtures when state machines or prompt IO change, and lean on the shared helpers already sourced at the top of each test file for assertions. Always run `./scripts/run.sh test <target>` before submitting, and capture tmux output when validating new sessions.

## Commit & Pull Request Guidelines

Commits follow conventional prefixes seen in history (`feat:`, `docs:`, etc.) and should stay focused on one stage or helper tweak. Reference the bd issue ID in the commit body and PR description, summarize intent, list validation commands, and attach key CLI or tmux snippets for reviewer context. Call out every touched stage/pipeline so automation runners know which lint/test paths to rerun.
