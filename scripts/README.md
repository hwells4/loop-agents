# Loop Scripts

Autonomous execution of multi-step plans with context management.

## Before you start

Generate your plan and tasks first:

```bash
# 1. Define what you're building
/loop-agents:prd

# 2. Break it into executable tasks (creates beads)
/loop-agents:create-tasks
```

This creates beads tagged `loop/{session-name}` that the loop can execute autonomously.

## How it works

```
/prd → /create-tasks → beads → loop.sh → Autonomous execution
```

1. **Plan**: `/loop-agents:prd` defines what you're building
2. **Tasks**: `/loop-agents:create-tasks` breaks it into beads with acceptance criteria
3. **Configure**: `prompt.md` contains instructions for how the agent should work
4. **Run**: `loop.sh` picks a task, implements it, commits, repeats
5. **Learn**: Progress file accumulates patterns across iterations

## Files

| File | Purpose |
|------|---------|
| `loop.sh` | Main loop - runs iterations until complete |
| `loop-once.sh` | Test mode - single iteration |
| `prompt.md` | Instructions for each iteration |

Progress files are stored in your project at `.claude/loop-progress/progress-{session}.txt`.

## Direct Usage

If running scripts directly (instead of via `/loop-agents:loop`):

```bash
# Test single iteration first
.claude/loop-agents/scripts/loop-once.sh my-feature

# Run autonomously (default 25 iterations)
.claude/loop-agents/scripts/loop.sh 25 my-feature

# Run with custom limit
.claude/loop-agents/scripts/loop.sh 50 my-feature

# Check remaining work
bd ready --label=loop/my-feature
```

## Multi-Agent Support

Multiple loops can run simultaneously in separate tmux sessions:

```bash
# Terminal 1: Auth feature
tmux new-session -d -s "loop-auth" ".claude/loop-agents/scripts/loop.sh 50 auth"

# Terminal 2: Dashboard feature (parallel)
tmux new-session -d -s "loop-dashboard" ".claude/loop-agents/scripts/loop.sh 50 dashboard"
```

Each session:
- Uses its own beads (`loop/auth` vs `loop/dashboard`)
- Has its own progress file
- Claims work with `bd update --status=in_progress`
- No file conflicts

## The Loop

Each iteration:
1. Agent reads progress file for context
2. Lists available tasks: `bd ready --label=loop/{session}`
3. Uses judgment to pick the most logical next task
4. Claims the task: `bd update <id> --status=in_progress`
5. Implements and verifies
6. Commits changes
7. Closes the task: `bd close <id>`
8. Updates progress file with learnings
9. Signals `<promise>COMPLETE</promise>` when `bd ready` returns empty

Fresh context each iteration prevents degradation on long runs.
