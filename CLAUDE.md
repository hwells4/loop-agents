# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Loop Agents is a [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code. It runs autonomous, multi-iteration agent workflows in tmux sessions. Each iteration spawns a fresh Claude instance that reads accumulated progress to maintain context without degradation.

**Core philosophy:** Fresh agent per iteration prevents context degradation. Two-agent consensus prevents premature stopping. Planning tokens are cheaper than implementation tokens.

## Commands

```bash
# Run a loop directly
./scripts/run.sh loop work auth 25        # work loop, session "auth", max 25 iterations
./scripts/run.sh loop improve-plan my-session 5

# Run a pipeline (chains loops together)
./scripts/run.sh pipeline full-refine.yaml my-session

# Force start (override existing session lock)
./scripts/run.sh loop work auth 25 --force

# List available loops/pipelines
./scripts/run.sh
```

Dependencies: `jq`, `claude`, `tmux`, `bd` (beads CLI)

## Skills

Skills are Claude Code extensions in `skills/`. Each provides specialized workflows.

| Skill | Invocation | Purpose |
|-------|------------|---------|
| **sessions** | `/loop-agents:sessions` | Start/manage loops and pipelines in tmux |
| **plan-refinery** | `/plan-refinery` | Iterative planning with Opus subagents |
| **create-prd** | `/loop-agents:create-prd` | Generate PRDs through adaptive questioning |
| **create-tasks** | `/loop-agents:create-tasks` | Break PRD into executable beads |
| **pipeline-builder** | `/loop-agents:pipeline-builder` | Create custom loops and pipelines |

### Skill Structure

Each skill in `skills/{name}/` contains:
- `SKILL.md` - Skill definition with intake, routing, and success criteria
- `workflows/` - Step-by-step workflow files
- `references/` - Supporting documentation

## Slash Commands

Commands in `commands/` provide user-facing interfaces.

| Command | Usage | Description |
|---------|-------|-------------|
| `/loop` | `/loop`, `/loop status`, `/loop attach NAME` | Orchestration hub: plan, status, management |
| `/work` | `/work`, `/work auth` | Launch implementation loops |
| `/refine` | `/refine`, `/refine quick`, `/refine deep` | Run refinement pipelines |
| `/ideate` | `/ideate`, `/ideate 3` | Generate improvement ideas |

## Architecture

```
scripts/
├── engine.sh                 # Unified orchestrator (loops + pipelines)
├── run.sh                    # Entry point wrapper
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # JSON iteration history
│   ├── progress.sh           # Accumulated context files
│   ├── resolve.sh            # Template variable resolution
│   ├── parse.sh              # Claude output parsing
│   ├── notify.sh             # Desktop notifications + logging
│   ├── lock.sh               # Session locking (prevents duplicates)
│   └── completions/          # Stopping strategies
│       ├── beads-empty.sh    # Stop when no beads remain
│       ├── plateau.sh        # Stop when 2 agents agree
│       ├── fixed-n.sh        # Stop after N iterations
│       └── all-items.sh      # Stop after processing items
├── loops/                    # Loop type definitions
│   ├── work/                 # Implementation (beads-empty)
│   ├── improve-plan/         # Plan refinement (plateau)
│   ├── refine-beads/         # Bead refinement (plateau)
│   └── idea-wizard/          # Ideation (fixed-n)
└── pipelines/                # Multi-stage workflows
    └── *.yaml

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

## Core Concepts

### Loops

A loop = prompt template + completion strategy. Each iteration:
1. Resolves template variables (`${SESSION}`, `${ITERATION}`, `${PROGRESS_FILE}`, etc.)
2. Executes Claude with resolved prompt
3. Parses output for structured fields
4. Updates state file with results
5. Checks completion condition → stop or continue

### State vs Progress Files

**State file** (`.claude/loop-state-{session}.json`): JSON tracking iteration history for completion checks
```json
{"session": "auth", "iteration": 5, "history": [{"plateau": false}, {"plateau": true}]}
```

**Progress file** (`.claude/loop-progress/progress-{session}.txt`): Markdown with accumulated learnings. Fresh Claude reads this each iteration to maintain context.

**Lock file** (`.claude/locks/{session}.lock`): JSON preventing concurrent sessions with the same name. Contains PID, session name, and start time. Automatically cleaned up when process exits or dies.

### Completion Strategies

| Strategy | Implementation | Used By |
|----------|----------------|---------|
| `beads-empty` | Checks `bd ready --label=loop/{session}` returns 0 | work loop |
| `plateau` | Requires 2 consecutive agents to output `PLATEAU: true` | improve-plan, refine-beads |
| `fixed-n` | Runs exactly N iterations | idea-wizard |
| `all-items` | Processes each item in a list | batch processing |

### Pipelines

Chain loops together. Each stage's outputs become `${INPUTS}` for the next:
```yaml
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

| Variable | Description |
|----------|-------------|
| `${SESSION}` / `${SESSION_NAME}` | Session name |
| `${ITERATION}` | 1-based iteration number |
| `${INDEX}` | 0-based iteration index |
| `${PROGRESS}` / `${PROGRESS_FILE}` | Path to progress file |
| `${OUTPUT}` | Path to write output (pipelines) |
| `${INPUTS}` | Previous stage outputs (pipelines) |
| `${INPUTS.stage-name}` | Named stage outputs (pipelines) |

## Creating a New Loop

1. Create directory: `scripts/loops/{name}/`
2. Add `loop.yaml`:
```yaml
name: my-loop
description: What this loop does
completion: plateau      # beads-empty, plateau, fixed-n, all-items
delay: 3                 # seconds between iterations
min_iterations: 2        # for plateau: don't check before this
output_parse: plateau:PLATEAU reasoning:REASONING  # extract from output
```
3. Add `prompt.md` with template using variables above
4. Run verification with `/loop-agents:pipeline-builder`

## Recommended Workflow

**Feature implementation flow:**
1. `/loop plan` or `/loop-agents:create-prd` → Gather requirements, save to `docs/plans/`
2. `/loop-agents:create-tasks` → Break PRD into beads tagged `loop/{session}`
3. `/refine` → Improve plan and beads (default: 5+5 iterations)
4. `/work` → Autonomous implementation until all beads complete

## Key Patterns

**Fresh agent per iteration**: Avoids context degradation. Each Claude reads the progress file for accumulated context.

**Two-agent consensus** (plateau): Prevents single-agent blind spots. Both must independently confirm completion.

**Beads integration**: Work loop uses `bd` CLI to list/claim/close tasks. Beads are tagged with `loop/{session}`.

**Session isolation**: Each session has separate beads (`loop/{session}` label), progress file, state file, and tmux session.

## Debugging

```bash
# Watch a running loop
tmux attach -t loop-{session}

# Check loop state
cat .claude/loop-state-{session}.json | jq

# View progress file
cat .claude/loop-progress/progress-{session}.txt

# Check remaining beads
bd ready --label=loop/{session}

# Kill a stuck loop
tmux kill-session -t loop-{session}
```

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
./scripts/run.sh loop work my-session 10 --force
```

**Lock file format:**
```json
{"session": "auth", "pid": 12345, "started_at": "2025-01-10T10:00:00Z"}
```

**When you see "Session is already running":**
1. Check if the PID in the lock file is still alive: `ps -p <pid>`
2. If alive, the session is running - attach or kill it first
3. If dead, the lock is stale - remove it manually or use `--force`

## Environment Variables

Loops export:
- `CLAUDE_LOOP_AGENT=1` - Always true inside a loop
- `CLAUDE_LOOP_SESSION` - Current session name
- `CLAUDE_LOOP_TYPE` - Current loop type
