# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Start

| I want to... | Command |
|--------------|---------|
| Start any pipeline | `/start` |
| Implement a feature with Codex | `/work implement user auth` |
| Refine a plan | `/refine` |
| Generate improvement ideas | `/ideate` |
| Create a new pipeline | `/pipeline` |
| Check running sessions | `/sessions list` |

## Philosophy

This codebase will outlive you. Every shortcut becomes someone else's burden. Establish will be copied and corners you cut will be cut again. Please fight entropy and leave the codebase better than you found it.

## What This Is

Agent Pipelines is a [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code. It runs autonomous, multi-iteration agent workflows in tmux sessions. Each iteration spawns a fresh Claude instance that reads accumulated progress to maintain context without degradation.

**Core philosophy:** Fresh agent per iteration prevents context degradation. Two-agent consensus prevents premature stopping. Planning tokens are cheaper than implementation tokens.

**Everything is a pipeline.** A "loop" is just a single-stage pipeline. The unified engine treats all executions the same way.

## Commands

```bash
# Run a single-stage pipeline (3 equivalent ways)
./scripts/run.sh ralph auth 25                    # Shortcut: type session max
./scripts/run.sh loop ralph auth 25               # Explicit: loop type session max
./scripts/run.sh pipeline --single-stage ralph auth 25  # Engine syntax

# Run a multi-stage pipeline
./scripts/run.sh pipeline refine.yaml my-session

# Run a pipeline multiple times (3 full runs)
./scripts/run.sh pipeline refine.yaml my-session 3

# Force start (override existing session lock)
./scripts/run.sh ralph auth 25 --force

# Resume a crashed/failed session
./scripts/run.sh ralph auth 25 --resume

# Check session status
./scripts/run.sh status auth

# List available stages and pipelines
./scripts/run.sh
```

Dependencies: `jq`, `claude`, `tmux`, `bd` (beads CLI)

## Skills

Skills are Claude Code extensions in `skills/`. Each provides specialized workflows.

| Skill | Invocation | Purpose |
|-------|------------|---------|
| **start** | `/start` | Universal pipeline launcher with discovery |
| **sessions** | `/sessions` | Start/manage pipelines in tmux |
| **work** | `/work` | Quick-start Codex agent for implementation tasks |
| **plan-refinery** | `/plan-refinery` | Iterative planning with Opus subagents |
| **create-prd** | `/agent-pipelines:create-prd` | Generate PRDs through adaptive questioning |
| **create-tasks** | `/agent-pipelines:create-tasks` | Break PRD into executable beads |
| **pipeline-designer** | `/pipeline` | Design new pipeline architectures |
| **pipeline-creator** | `/pipeline create` | Create stage.yaml and prompt.md files |
| **pipeline-editor** | `/pipeline edit` | Modify existing stages and pipelines |

### Skill Structure

Each skill in `skills/{name}/` contains:
- `SKILL.md` - Skill definition with intake, routing, and success criteria (required)
- `workflows/` - Step-by-step workflow files (optional, for multi-step skills)
- `references/` - Supporting documentation (optional)

## Slash Commands

Commands in `commands/` provide user-facing interfaces.

| Command | Usage | Description |
|---------|-------|-------------|
| `/start` | `/start`, `/start ralph`, `/start refine.yaml` | Universal pipeline launcher with discovery |
| `/sessions` | `/sessions`, `/sessions list`, `/sessions start` | Session management: start, list, monitor, kill, cleanup |
| `/work` | `/work implement X`, `/work fix tests, 10 iterations` | Quick-start Codex agent for implementation |
| `/ralph` | `/ralph` | Quick-start work pipelines (interactive) |
| `/refine` | `/refine`, `/refine quick`, `/refine deep` | Run refinement pipelines |
| `/ideate` | `/ideate`, `/ideate 3` | Generate improvement ideas |
| `/robot-mode` | `/robot-mode`, `/robot-mode 2` | Audit CLI for agent-friendliness |
| `/readme-sync` | `/readme-sync`, `/readme-sync 2` | Sync README with codebase |
| `/pipeline` | `/pipeline`, `/pipeline edit` | Design, create, and edit pipelines |

## Architecture

**Everything is a pipeline.** The unified engine (`engine.sh`) runs all sessions the same way. A single-stage pipeline is what we colloquially call a "loop."

```
scripts/
├── engine.sh                 # Unified pipeline engine
├── run.sh                    # Entry point (converts all commands to pipeline calls)
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # JSON iteration history + crash recovery
│   ├── progress.sh           # Accumulated context files
│   ├── context.sh            # v3 context.json generation
│   ├── status.sh             # v3 status.json validation
│   ├── resolve.sh            # Template variable resolution
│   ├── notify.sh             # Desktop notifications + logging
│   ├── lock.sh               # Session locking (prevents duplicates)
│   ├── validate.sh           # Lint and dry-run validation
│   ├── test.sh               # Test framework utilities
│   ├── mock.sh               # Mock execution for testing
│   ├── provider.sh           # Provider abstraction (Claude, Codex)
│   ├── parallel.sh           # Parallel block execution
│   └── completions/          # Termination strategies
│       ├── beads-empty.sh    # Stop when queue empty (type: queue)
│       ├── plateau.sh        # Stop on consensus (type: judgment)
│       └── fixed-n.sh        # Stop after N iterations (type: fixed)
├── stages/                   # Stage definitions (single-stage pipeline configs)
│   ├── ralph/                # The original Ralph loop (fixed termination)
│   ├── codex-work/           # Codex implementation agent (fixed termination)
│   ├── improve-plan/         # Plan refinement (judgment termination)
│   ├── refine-tasks/         # Task refinement (judgment termination)
│   ├── elegance/             # Code elegance review (judgment termination)
│   ├── bug-discovery/        # Fresh-eyes bug exploration (fixed termination)
│   ├── bug-triage/           # Bug triage and elegant fix design (judgment termination)
│   ├── idea-wizard/          # Ideation (fixed termination)
│   ├── research-plan/        # Research-driven planning (judgment termination)
│   ├── test-scanner/         # Test coverage gap discovery (judgment termination)
│   └── fresh-eyes/           # Critical plan review with Codex xhigh (judgment termination)
└── pipelines/                # Multi-stage pipeline configs
    ├── refine.yaml           # 5+5 plan → task iterations
    ├── ideate.yaml           # Brainstorm improvements
    └── bug-hunt.yaml         # Discover → triage → refine → fix

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

## Core Concepts

### Pipelines

**Everything is a pipeline.** A pipeline runs one or more stages, each with its own prompt and completion strategy.

- **Single-stage pipeline** (aka "loop"): One stage that iterates until completion
- **Multi-stage pipeline**: Multiple stages chained together, outputs flow between stages

All sessions run in `.claude/pipeline-runs/{session}/` with unified state tracking.

### Stages

A stage = prompt template + termination strategy. Stages are defined in `scripts/stages/{name}/`. Each iteration:
1. Generates `context.json` with session metadata, paths, and inputs
2. Resolves template variables (`${CTX}`, `${PROGRESS}`, `${STATUS}`, etc.)
3. Executes Claude with resolved prompt
4. Agent writes `status.json` with decision (continue/stop/error)
5. Engine saves output snapshot to `iterations/NNN/output.md`
6. Checks termination condition → stop or continue

### Providers

Stages can use different AI agent providers. The default is Claude Code.

| Provider | Aliases | CLI | Default Model | Skip Permissions |
|----------|---------|-----|---------------|------------------|
| Claude Code | `claude`, `claude-code`, `anthropic` | `claude` | opus | `--dangerously-skip-permissions` |
| Codex | `codex`, `openai` | `codex` | gpt-5.2-codex | `--dangerously-bypass-approvals-and-sandbox` |

**Claude Models:**

| Model | Aliases | Description |
|-------|---------|-------------|
| `opus` | `claude-opus`, `opus-4`, `opus-4.5` | Most capable, best for complex tasks |
| `sonnet` | `claude-sonnet`, `sonnet-4` | Balanced capability and speed |
| `haiku` | `claude-haiku` | Fastest, best for simple tasks |

**Codex Models:**

| Model | Description |
|-------|-------------|
| `gpt-5.2-codex` | Default, most capable Codex model |
| `gpt-5-codex` | Previous generation |
| `gpt-5.1-codex-max` | Frontier agentic model |
| `gpt-5.1-codex-mini` | Cost-effective model |


**Codex reasoning effort:** Set via `CODEX_REASONING_EFFORT` env var. Default: `high`.

| Level | Use Case |
|-------|----------|
| `minimal` | Simple tasks, fastest |
| `low` | Straightforward code |
| `medium` | **Recommended daily driver** |
| `high` | Complex tasks (default) |
| `xhigh` | Maximum reasoning, slowest |

**Guidance:** Reserve `xhigh` for 1-2 iteration tasks (plan synthesis, task creation). For 5+ iteration loops, use `medium` or `high`—xhigh cost/latency adds up fast.

**Configuration:**
```yaml
# In stage.yaml
provider: codex  # or claude (default)
model: gpt-5.2-codex:xhigh  # Codex: model:reasoning (xhigh, high, medium, low, minimal)
```

### State vs Progress Files

**State file** (`.claude/pipeline-runs/{session}/state.json`): JSON tracking iteration history for completion checks and crash recovery
```json
{
  "session": "auth",
  "iteration": 5,
  "iteration_completed": 4,
  "iteration_started": "2025-01-10T10:05:00Z",
  "status": "running",
  "history": [{"plateau": false}, {"plateau": true}]
}
```

**Progress file** (`.claude/pipeline-runs/{session}/progress-{session}.md`): Markdown with accumulated learnings. Fresh Claude reads this each iteration to maintain context.

**Lock file** (`.claude/locks/{session}.lock`): JSON preventing concurrent sessions with the same name. Contains PID, session name, and start time.
```json
{
  "session": "auth",
  "pid": 12345,
  "started_at": "2025-01-10T10:00:00Z"
}
```

When a stale lock is cleaned up, the engine releases any `in_progress` beads labeled `pipeline/{session}` back to `open` so crashed sessions do not orphan claims.

### Termination Strategies

| Type | How It Works | Used By |
|------|--------------|---------|
| `queue` | Checks external queue (`bd ready`) is empty | (available for custom stages) |
| `judgment` | Requires N consecutive agents to write `decision: stop` | improve-plan, refine-tasks, elegance, research-plan |
| `fixed` | Runs exactly N iterations | ralph, bug-discovery, idea-wizard |

**v3 status format:** Agents write `status.json` with:
```json
{
  "decision": "continue",  // or "stop" or "error"
  "reason": "Explanation",
  "summary": "What happened this iteration",
  "work": { "items_completed": [], "files_touched": [] },
  "errors": []
}
```

### Multi-Stage Pipelines

Use `nodes:` for pipeline definitions (`stages:` is deprecated but still supported). Chain stages together with `inputs:`:
```yaml
name: full-refine
description: Refine plan then beads
nodes:
  - id: plan
    stage: improve-plan
    runs: 5
  - id: beads
    stage: refine-tasks
    runs: 5
    inputs:
      from: plan        # Reference previous node by id
      select: latest    # "latest" (default) or "all"
```

Agents access inputs via `context.json`:
```bash
# Read previous stage outputs
jq -r '.inputs.from_stage | to_entries[] | .value[]' ${CTX} | xargs cat
```

Available pipelines: `quick-refine.yaml` (3+3), `full-refine.yaml` (5+5), `deep-refine.yaml` (8+8)

### Parallel Blocks

Run multiple providers (Claude, Codex, etc.) concurrently with isolated contexts. Each provider runs stages sequentially within the block, but providers execute in parallel.

```yaml
name: parallel-refine
description: Compare Claude and Codex refinements
nodes:
  - id: setup
    stage: improve-plan
    termination:
      type: fixed
      iterations: 1

  - id: dual-refine
    parallel:
      providers: [claude, codex]
      stages:
        - id: plan
          stage: improve-plan
          termination:
            type: fixed
            iterations: 1
        - id: iterate
          stage: improve-plan
          termination:
            type: judgment
            consensus: 2
            max: 5

  - id: synthesize
    stage: elegance
    inputs:
      from_parallel: iterate  # Read outputs from both providers
```

**Directory structure:**
```
.claude/pipeline-runs/{session}/
├── stage-00-setup/...
├── parallel-01-dual-refine/
│   ├── manifest.json              # Aggregated outputs for downstream stages
│   ├── resume.json                # Per-provider crash recovery hints
│   └── providers/
│       ├── claude/
│       │   ├── progress.md        # Provider-isolated progress
│       │   ├── state.json         # Provider-specific state
│       │   ├── stage-00-plan/iterations/001/
│       │   └── stage-01-iterate/iterations/001..003/
│       └── codex/...
└── stage-02-synthesize/...
```

**Key behaviors:**
- Each provider has isolated progress and state (no cross-provider visibility within block)
- Stages within a block run sequentially per provider
- Providers execute concurrently (parallel)
- Block waits for all providers before proceeding
- Any provider failure fails the entire block
- `from_parallel` downstream can select specific providers or all

**Downstream consumption:**
```yaml
# Short form - gets all providers' outputs
inputs:
  from_parallel: iterate

# Full form with options
inputs:
  from_parallel:
    stage: iterate
    block: dual-refine           # Optional if only one parallel block
    providers: [claude]          # Filter to subset (default: all)
    select: history              # "latest" (default) or "history" (all iterations)
```

**Crash recovery:**
```bash
./scripts/run.sh pipeline my-pipeline.yaml my-session --resume
```
On resume, completed providers are skipped; only failed/incomplete providers restart.

## Template Variables

### v3 Variables (Preferred)

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to `context.json` with full iteration context |
| `${PROGRESS}` | Path to progress file |
| `${STATUS}` | Path where agent writes `status.json` |
| `${ITERATION}` | 1-based iteration number |
| `${SESSION_NAME}` | Session name |
| `${CONTEXT}` | Injected context text (from CLI `--context` or env `CLAUDE_PIPELINE_CONTEXT`) |
| `${OUTPUT}` | Path to write output (multi-stage pipelines, set via `output_path` in stage.yaml) |

## Input System

Agents receive inputs through `context.json`, which contains three input sources:

### Input Sources

**1. Initial Inputs** (`inputs.from_initial`): Files passed via CLI `--input` flags
```bash
./scripts/run.sh ralph auth 25 --input=docs/plan.md --input=requirements.txt
```

**2. Previous Stage Outputs** (`inputs.from_stage`): Outputs from earlier stages in multi-stage pipelines
```yaml
# In pipeline.yaml
nodes:
  - id: plan
    stage: improve-plan
    runs: 5
  - id: implement
    stage: ralph
    runs: 25
    inputs:
      from: plan        # References "plan" node by id
      select: latest    # "latest" (default) or "history" (all iterations)
```

**3. Parallel Block Outputs** (`inputs.from_parallel`): Outputs from multiple providers running in parallel
```yaml
# In pipeline.yaml
nodes:
  - id: dual-refine
    parallel:
      providers: [claude, codex]
      stages:
        - id: iterate
          stage: improve-plan
  - id: synthesize
    stage: elegance
    inputs:
      from_parallel: iterate  # Gets outputs from both providers
```

### Reading Inputs in Prompts

Agents access inputs by reading `context.json`:

```bash
# Read initial inputs (CLI --input files)
jq -r '.inputs.from_initial[]' ${CTX} | while read file; do
  echo "Reading: $file"
  cat "$file"
done

# Read previous stage outputs
jq -r '.inputs.from_stage | to_entries[] | .value[]' ${CTX} | xargs cat

# Read parallel block outputs (all providers)
jq -r '.inputs.from_parallel | to_entries[] | .value[]' ${CTX} | xargs cat

# Filter parallel outputs by provider
jq -r '.inputs.from_parallel.claude[]' ${CTX} | xargs cat
```

### Complete context.json Structure

```json
{
  "session": "auth",
  "pipeline": "multi-stage",
  "stage": {
    "id": "implement",
    "index": 1,
    "template": "ralph"
  },
  "iteration": 3,
  "paths": {
    "session_dir": ".claude/pipeline-runs/auth",
    "stage_dir": ".claude/pipeline-runs/auth/stage-01-implement",
    "progress": ".claude/pipeline-runs/auth/progress-auth.md",
    "output": ".claude/pipeline-runs/auth/stage-01-implement/output.md",
    "status": ".claude/pipeline-runs/auth/stage-01-implement/iterations/003/status.json"
  },
  "inputs": {
    "from_initial": [
      "docs/plans/auth-plan.md",
      "requirements.txt"
    ],
    "from_stage": {
      "plan": [
        ".claude/pipeline-runs/auth/stage-00-plan/iterations/005/output.md"
      ]
    },
    "from_parallel": {
      "claude": [
        ".claude/pipeline-runs/auth/parallel-01-dual/providers/claude/stage-00-iterate/iterations/003/output.md"
      ],
      "codex": [
        ".claude/pipeline-runs/auth/parallel-01-dual/providers/codex/stage-00-iterate/iterations/002/output.md"
      ]
    }
  },
  "limits": {
    "max_iterations": 25,
    "remaining_seconds": -1
  },
  "commands": {
    "test": "npm test",
    "lint": "npm run lint",
    "format": "npm run format",
    "types": "npm run typecheck"
  }
}
```

## Commands Passthrough

Pipelines can pass project-specific commands to agents via `context.json`. This allows generic stage prompts to work across different projects without hardcoding tool invocations.

### Defining Commands

Commands are defined at the pipeline or stage level:

```yaml
# In pipeline.yaml or stage.yaml
commands:
  test: npm test
  lint: npm run lint
  format: npm run format
  types: npm run typecheck
  build: npm run build
```

Or via CLI override:
```bash
./scripts/run.sh ralph auth 25 \
  --command=test="pytest tests/" \
  --command=lint="ruff check ."
```

### Using Commands in Prompts

Agents read commands from `context.json` and use them instead of hardcoded tool invocations:

```bash
# Read the test command (fallback to generic if not provided)
TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})

# Run tests
$TEST_CMD

# Check if a specific command is configured
if jq -e '.commands.format' ${CTX} > /dev/null; then
  FORMAT_CMD=$(jq -r '.commands.format' ${CTX})
  echo "Running formatter: $FORMAT_CMD"
  $FORMAT_CMD
fi
```

**Common command keys:**
- `test` - Run test suite
- `lint` - Run linter
- `format` - Format code
- `types` - Type checking
- `build` - Build project

This pattern allows stages like `ralph` and `test-review` to work across JavaScript, Python, Ruby, and other ecosystems without modification.

## Creating a New Stage

Stages are single-stage pipeline definitions. Create one to add a new pipeline type.

1. Create directory: `scripts/stages/{name}/`
2. Add `stage.yaml`:
```yaml
name: my-stage
description: What this stage does

termination:
  type: judgment        # queue, judgment, or fixed
  min_iterations: 2     # for judgment: start checking after this many
  consensus: 2          # for judgment: consecutive stops needed
  iterations: 3         # for fixed: default max iterations (optional)

delay: 3                # seconds between iterations

# Optional fields:
provider: claude                    # claude or codex (default: claude)
model: opus                         # model name (Codex: model:reasoning like gpt-5.2-codex:xhigh)
prompt: prompts/custom.md           # custom prompt path (default: prompt.md)
output_path: docs/output-${SESSION}.md  # direct output to specific file
```
3. Add `prompt.md` (or custom path) with template using v3 variables (`${CTX}`, `${PROGRESS}`, `${STATUS}`)
4. Ensure prompt instructs agent to write `status.json` with decision
5. Run verification: `./scripts/run.sh lint loop {name}`

## Recommended Workflows

**Feature implementation flow:**
1. `/sessions plan` or `/agent-pipelines:create-prd` → Gather requirements, save to `docs/plans/`
2. `/agent-pipelines:create-tasks` → Break PRD into beads tagged `pipeline/{session}`
3. `/refine` → Run refinement pipeline (default: 5+5 iterations)
4. `/ralph` → Run Ralph loop until all beads complete

**Bug hunting flow:**
```bash
./scripts/run.sh pipeline bug-hunt.yaml my-session
```
1. **Discover** (8 iterations): Agents randomly explore code, trace execution flows, find bugs with fresh eyes
2. **Elegance** (up to 5): Triage bugs, find patterns, design elegant solutions, create beads
3. **Refine** (3 iterations): Polish the beads
4. **Fix** (25 iterations): Implement the fixes

## Key Patterns

**Fresh agent per iteration**: Avoids context degradation. Each Claude reads the progress file for accumulated context.

**Two-agent consensus** (plateau): Prevents single-agent blind spots. Both must independently confirm completion.

**Beads integration**: Work stage uses `bd` CLI to list/claim/close tasks. Beads are tagged with `pipeline/{session}`.

**Session isolation**: Each session has separate beads (`pipeline/{session}` label), progress file, state file, and tmux session.

## Debugging

```bash
# Watch a running pipeline
tmux attach -t pipeline-{session}

# Check pipeline state
cat .claude/pipeline-runs/{session}/state.json | jq

# View progress file
cat .claude/pipeline-runs/{session}/progress-{session}.md

# Check remaining beads
bd ready --label=pipeline/{session}

# Kill a stuck pipeline
tmux kill-session -t pipeline-{session}

# Check session status (active, failed, completed)
./scripts/run.sh status {session}
```

### Crash Recovery

Sessions automatically detect and recover from crashes (API timeouts, network issues, SIGKILL).

**When a session crashes**, you'll see:
```
Session 'auth' failed at iteration 5/25
Last successful iteration: 4
Error: Claude process terminated unexpectedly
Run with --resume to continue from iteration 5
```

**To resume:**
```bash
./scripts/run.sh ralph auth 25 --resume
```

**How crash detection works:**
1. On startup, engine checks: lock exists + PID dead = crashed
2. State file tracks `iteration_started` and `iteration_completed` for precise resume
3. For hung sessions (PID alive but stuck), use `tmux attach` to diagnose

### Session Locks

Locks prevent running duplicate sessions with the same name. They are automatically released when a session ends normally or its process dies.

```bash
# List active locks
ls .claude/locks/

# View lock details (PID, start time)
cat .claude/locks/{session}.lock | jq

# Check if a session is locked
test -f .claude/locks/{session}.lock && echo "locked" || echo "available"

# Clear a stale lock manually (only if process is dead)
rm .claude/locks/{session}.lock

# Force start despite existing lock
./scripts/run.sh ralph my-session 10 --force
```

**When you see "Session is already running":**
1. Check if the PID in the lock file is still alive: `ps -p <pid>`
2. If alive, the session is running - attach or kill it first
3. If dead, the lock is stale - use `--resume` to continue or `--force` to restart

## Environment Variables

**Exported by pipelines:**
- `CLAUDE_PIPELINE_AGENT=1` - Always true inside a pipeline
- `CLAUDE_PIPELINE_SESSION` - Current session name
- `CLAUDE_PIPELINE_TYPE` - Current stage type

**Override provider/model/context:**
- `CLAUDE_PIPELINE_PROVIDER` - Override provider (claude, codex)
- `CLAUDE_PIPELINE_MODEL` - Override model (opus, o3, etc.)
- `CLAUDE_PIPELINE_CONTEXT` - Inject text into prompt via `${CONTEXT}` variable

CLI flags take precedence over env vars:
```bash
# CLI flags (highest priority)
./scripts/run.sh ralph auth 25 --provider=codex --model=gpt-5.1-codex-max

# Inject context into the prompt (useful for agents)
./scripts/run.sh ralph auth 25 --context="Read docs/plan.md before starting"

# Environment variables
CLAUDE_PIPELINE_PROVIDER=codex ./scripts/run.sh ralph auth 25

# Combined (CLI wins for provider, env wins for model)
CLAUDE_PIPELINE_MODEL=sonnet ./scripts/run.sh ralph auth 25 --provider=claude
```

**Precedence:** CLI flags → Env vars → Pipeline config → Stage config → Built-in defaults
