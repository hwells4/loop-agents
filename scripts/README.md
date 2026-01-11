# Unified Engine

One engine for iterative AI agent workflows.

## Architecture

```
scripts/
├── engine.sh              # The engine
├── run.sh                 # Entry point
├── lib/                   # Shared utilities
│   ├── yaml.sh
│   ├── state.sh
│   ├── progress.sh
│   ├── resolve.sh
│   ├── parse.sh
│   ├── notify.sh
│   ├── lock.sh            # Session locking
│   └── completions/       # Stopping conditions
├── loops/                 # Loop definitions
│   ├── work/
│   ├── improve-plan/
│   ├── refine-beads/
│   └── idea-wizard/
└── pipelines/             # Multi-stage pipelines
    └── *.yaml
```

## Concepts

**Loop**: A prompt + completion strategy, run N iterations until done.

**Pipeline**: Multiple loops chained together.

## Usage

```bash
# Run a loop
./scripts/run.sh loop work auth 25
./scripts/run.sh loop improve-plan my-session 5

# Run a pipeline
./scripts/run.sh pipeline full-refine.yaml my-session

# Force start (override existing lock)
./scripts/run.sh loop work auth 25 --force

# List available
./scripts/run.sh
```

## Session Locking

Sessions are protected by lock files to prevent duplicate concurrent sessions with the same name. Lock files are stored in `.claude/locks/` and contain:

```json
{"session": "auth", "pid": 12345, "started_at": "2025-01-10T10:00:00Z"}
```

**Automatic behavior:**
- Lock acquired when a loop/pipeline starts
- Lock released when it completes (success or failure)
- Stale locks (dead PIDs) are cleaned up automatically on startup

**Manual lock management:**
```bash
# List active locks
ls .claude/locks/

# View lock details
cat .claude/locks/auth.lock | jq

# Clear a stale lock (if process is dead)
rm .claude/locks/auth.lock
```

**Force flag:**
Use `--force` to override an existing lock. This is useful when:
- A previous run crashed and left a stale lock
- You want to replace a running session

```bash
./scripts/run.sh loop work auth 25 --force
```

**Error messages:**
When a lock conflict occurs, you'll see:
```
Error: Session 'auth' is already running (PID 12345)
  Use --force to override
```

## Creating a Loop

Each loop has two files:

`scripts/loops/<name>/loop.yaml` - when to stop:
```yaml
name: my-loop
description: What this loop does
completion: plateau  # or beads-empty, fixed-n, all-items
delay: 3
```

`scripts/loops/<name>/prompt.md` - what Claude does each iteration:
```markdown
# My Agent

Session: ${SESSION_NAME}
Iteration: ${ITERATION}

## Task
...

## Output
PLATEAU: true/false
REASONING: [why]
```

## Pipeline Format

Pipelines chain loops together:

```yaml
name: my-pipeline
description: What this does

stages:
  - name: plan
    loop: improve-plan    # references scripts/loops/improve-plan/
    runs: 5

  - name: custom
    runs: 4
    prompt: |
      Inline prompt for one-off stages.
      Previous: ${INPUTS}
      Write to: ${OUTPUT}
```

## Variables

| Variable | Description |
|----------|-------------|
| `${SESSION_NAME}` | Session name |
| `${ITERATION}` | Current iteration (1-based) |
| `${PROGRESS_FILE}` | Path to progress file |
| `${OUTPUT}` | Path to write output |
| `${PERSPECTIVE}` | Current perspective (fan-out) |
| `${INPUTS.stage-name}` | Outputs from named stage |
| `${INPUTS}` | Outputs from previous stage |

## Completion Strategies

| Strategy | Stops When |
|----------|------------|
| `beads-empty` | No beads remain |
| `plateau` | 2 agents agree it's done |
| `fixed-n` | N iterations complete |
| `all-items` | All items processed |
