# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Agent Pipelines is a [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code. It runs autonomous, multi-iteration agent workflows in tmux sessions. Each iteration spawns a fresh Claude instance that reads accumulated progress to maintain context without degradation.

**Core philosophy:** Fresh agent per iteration prevents context degradation. Two-agent consensus prevents premature stopping. Planning tokens are cheaper than implementation tokens.

**Everything is a pipeline.** A "loop" is just a single-stage pipeline. The unified engine treats all executions the same way.

## Commands

```bash
# Run a single-stage pipeline (3 equivalent ways)
./scripts/run.sh work auth 25                    # Shortcut: type session max
./scripts/run.sh loop work auth 25               # Explicit: loop type session max
./scripts/run.sh pipeline --single-stage work auth 25  # Engine syntax

# Run a multi-stage pipeline
./scripts/run.sh pipeline full-refine.yaml my-session

# Force start (override existing session lock)
./scripts/run.sh work auth 25 --force

# Resume a crashed/failed session
./scripts/run.sh work auth 25 --resume

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
| **sessions** | `/sessions` | Start/manage pipelines in tmux |
| **plan-refinery** | `/plan-refinery` | Iterative planning with Opus subagents |
| **create-prd** | `/agent-pipelines:create-prd` | Generate PRDs through adaptive questioning |
| **create-tasks** | `/agent-pipelines:create-tasks` | Break PRD into executable beads |
| **pipeline-builder** | `/agent-pipelines:pipeline-builder` | Create custom stages and pipelines |

### Skill Structure

Each skill in `skills/{name}/` contains:
- `SKILL.md` - Skill definition with intake, routing, and success criteria
- `workflows/` - Step-by-step workflow files
- `references/` - Supporting documentation

## Slash Commands

Commands in `commands/` provide user-facing interfaces.

| Command | Usage | Description |
|---------|-------|-------------|
| `/sessions` | `/sessions`, `/sessions list`, `/sessions start` | Session management: start, list, monitor, kill, cleanup |
| `/work` | `/work`, `/work auth` | Launch work pipelines |
| `/refine` | `/refine`, `/refine quick`, `/refine deep` | Run refinement pipelines |
| `/ideate` | `/ideate`, `/ideate 3` | Generate improvement ideas |

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
│   └── completions/          # Termination strategies
│       ├── beads-empty.sh    # Stop when queue empty (type: queue)
│       ├── plateau.sh        # Stop on consensus (type: judgment)
│       └── fixed-n.sh        # Stop after N iterations (type: fixed)
├── loops/                    # Stage definitions (single-stage pipeline configs)
│   ├── work/                 # Implementation (queue termination)
│   ├── improve-plan/         # Plan refinement (judgment termination)
│   ├── refine-beads/         # Bead refinement (judgment termination)
│   ├── elegance/             # Code elegance review (judgment termination)
│   └── idea-wizard/          # Ideation (fixed termination)
└── pipelines/                # Multi-stage pipeline configs
    └── *.yaml

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

### Termination Strategies

| Type | How It Works | Used By |
|------|--------------|---------|
| `queue` | Checks external queue (`bd ready`) is empty | work stage |
| `judgment` | Requires N consecutive agents to write `decision: stop` | improve-plan, refine-beads, elegance |
| `fixed` | Runs exactly N iterations | idea-wizard |

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

Chain stages together. Each stage's outputs become `${INPUTS}` for the next:
```yaml
name: full-refine
description: Refine plan then beads
stages:
  - name: plan
    loop: improve-plan
    runs: 5
  - name: beads
    loop: refine-beads
    runs: 5
```

Available pipelines: `quick-refine.yaml` (3+3), `full-refine.yaml` (5+5), `deep-refine.yaml` (8+8)

## Template Variables

### v3 Variables (Preferred)

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to `context.json` with full iteration context |
| `${PROGRESS}` | Path to progress file |
| `${STATUS}` | Path where agent writes `status.json` |
| `${ITERATION}` | 1-based iteration number |
| `${SESSION_NAME}` | Session name |

### Legacy Variables (Deprecated, still work)

| Variable | Description |
|----------|-------------|
| `${SESSION}` | Same as `${SESSION_NAME}` |
| `${INDEX}` | 0-based iteration index |
| `${PROGRESS_FILE}` | Same as `${PROGRESS}` |
| `${OUTPUT}` | Path to write output (multi-stage pipelines) |
| `${INPUTS}` | Previous stage outputs (multi-stage pipelines) |

## Creating a New Stage

Stages are single-stage pipeline definitions. Create one to add a new pipeline type.

1. Create directory: `scripts/stages/{name}/`
2. Add `loop.yaml`:
```yaml
name: my-stage
description: What this stage does

termination:
  type: judgment        # queue, judgment, or fixed
  min_iterations: 2     # for judgment: start checking after this many
  consensus: 2          # for judgment: consecutive stops needed

delay: 3                # seconds between iterations
```
3. Add `prompt.md` with template using v3 variables (`${CTX}`, `${PROGRESS}`, `${STATUS}`)
4. Ensure prompt instructs agent to write `status.json` with decision
5. Run verification: `./scripts/run.sh lint loop {name}`

## Recommended Workflow

**Feature implementation flow:**
1. `/loop plan` or `/agent-pipelines:create-prd` → Gather requirements, save to `docs/plans/`
2. `/agent-pipelines:create-tasks` → Break PRD into beads tagged `pipeline/{session}`
3. `/refine` → Run refinement pipeline (default: 5+5 iterations)
4. `/work` → Run work pipeline until all beads complete

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
./scripts/run.sh work auth 25 --resume
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
./scripts/run.sh work my-session 10 --force
```

**When you see "Session is already running":**
1. Check if the PID in the lock file is still alive: `ps -p <pid>`
2. If alive, the session is running - attach or kill it first
3. If dead, the lock is stale - use `--resume` to continue or `--force` to restart

## Environment Variables

Pipelines export:
- `CLAUDE_PIPELINE_AGENT=1` - Always true inside a pipeline
- `CLAUDE_PIPELINE_SESSION` - Current session name
- `CLAUDE_PIPELINE_TYPE` - Current stage type
