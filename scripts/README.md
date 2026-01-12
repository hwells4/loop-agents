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
│   ├── context.sh         # v3 context.json generation
│   ├── status.sh          # v3 status.json handling
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

# Resume a crashed/failed session
./scripts/run.sh loop work auth 25 --resume

# Check session status
./scripts/run.sh status auth

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

## Crash Recovery

Sessions automatically detect and recover from crashes (API timeouts, network issues, SIGKILL, etc).

### How It Works

1. **Lock Files**: Each session has a lock file with PID and start time
2. **Iteration Tracking**: State file tracks `iteration_started` and `iteration_completed`
3. **Failure Detection**: On startup, the engine checks:
   - Lock file exists but PID is dead = crashed
   - Lock file exists and PID is alive = active (don't interfere)
   - State has incomplete iteration = can resume

### When a Session Crashes

If Claude crashes mid-iteration, you'll see on next attempt:
```
Session 'auth' failed at iteration 5/25
Last successful iteration: 4
Error: Claude process terminated unexpectedly
Run with --resume to continue from iteration 5
```

### Resuming a Failed Session

```bash
# Resume from last successful iteration
./scripts/run.sh loop work auth 25 --resume
```

Output:
```
Resuming session 'auth' from iteration 5
Previous run: iterations 1-4 completed
```

### Checking Session Status

```bash
# Check status of any session
./scripts/run.sh status auth
```

Output varies by status:
- **Active**: `Session running (PID 12345)`
- **Failed**: `Session crashed (PID 12345 dead, started 2025-01-10T10:00:00Z)`
- **Completed**: `Session completed: all beads processed`

### State File Format

The state file (`.claude/state.json`) now includes:
```json
{
  "session": "auth",
  "status": "running",
  "iteration": 5,
  "iteration_started": "2025-01-10T10:05:00Z",
  "iteration_completed": 4,
  "history": [...]
}
```

Fields:
- `status`: "running", "failed", or "complete"
- `iteration_started`: Timestamp when current iteration began (null if between iterations)
- `iteration_completed`: Last successfully completed iteration number

### Lock File Format

Lock files (`.claude/locks/{session}.lock`):
```json
{
  "session": "auth",
  "pid": 12345,
  "started_at": "2025-01-10T10:00:00Z"
}
```

## Creating a Loop

Each loop has two files:

`scripts/stages/<name>/loop.yaml` - when to stop:
```yaml
name: my-loop
description: What this loop does
termination:
  type: judgment    # or queue, fixed
  consensus: 2      # for judgment: consecutive stops needed
  min_iterations: 2 # for judgment: start checking after this many
delay: 3
```

`scripts/stages/<name>/prompt.md` - what Claude does each iteration:
```markdown
# My Agent

Read context from: ${CTX}
Iteration: ${ITERATION}

## Task
...

## Output
Write status to ${STATUS}:
{"decision": "continue|stop|error", "reason": "..."}
```

## Pipeline Format

Pipelines chain loops together:

```yaml
name: my-pipeline
description: What this does

stages:
  - name: plan
    loop: improve-plan    # references scripts/stages/improve-plan/
    runs: 5

  - name: custom
    runs: 4
    prompt: |
      Inline prompt for one-off stages.
      Previous: ${INPUTS}
      Write to: ${OUTPUT}
```

## Variables (v3)

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to context.json with full iteration context |
| `${STATUS}` | Path where agent writes status.json |
| `${PROGRESS}` | Path to progress file |
| `${ITERATION}` | Current iteration (1-based) |
| `${SESSION_NAME}` | Session name |
| `${INPUTS.stage-name}` | Outputs from named stage (pipelines) |
| `${INPUTS}` | Outputs from previous stage (pipelines) |

## Termination Types (v3)

| Type | Stops When |
|------|------------|
| `queue` | External queue empty (`bd ready`) |
| `judgment` | N agents write `decision: stop` |
| `fixed` | N iterations complete |
