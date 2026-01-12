---
description: Manage autonomous pipeline sessions in tmux
---

# /sessions

Manage pipeline sessions: start, list, monitor, attach, kill, and cleanup. Sessions are autonomous pipelines running in tmux background.

## Usage

```
/sessions                    # Interactive - choose action
/sessions start              # Start a new session
/sessions list               # Show all running sessions
/sessions monitor NAME       # Peek at output without attaching
/sessions attach NAME        # Connect to watch live (Ctrl+b d to detach)
/sessions kill NAME          # Terminate a session
/sessions cleanup            # Handle stale locks and orphaned resources
/sessions status NAME        # Detailed status of a session
```

## Quick Start

**Start a work session:**
```bash
./scripts/run.sh work my-session 25
```

**Check what's running:**
```bash
tmux list-sessions 2>/dev/null | grep -E "^pipeline-"
```

**Peek at output:**
```bash
tmux capture-pane -t pipeline-{session} -p | tail -50
```

## Session Types

| Type | Command | Stops When |
|------|---------|------------|
| **Work** | `./scripts/run.sh work NAME MAX` | All beads complete |
| **Improve Plan** | `./scripts/run.sh improve-plan NAME MAX` | 2 agents agree |
| **Refine Beads** | `./scripts/run.sh refine-beads NAME MAX` | 2 agents agree |
| **Pipeline** | `./scripts/run.sh pipeline FILE NAME` | All stages complete |

## Session Resources

Each session creates:
- **Lock file:** `.claude/locks/{session}.lock`
- **State file:** `.claude/pipeline-runs/{session}/state.json`
- **Progress file:** `.claude/pipeline-runs/{session}/progress-{session}.md`
- **tmux session:** `pipeline-{session}`

## Crash Recovery

If a session crashes:
```bash
# Check status
./scripts/run.sh status NAME

# Resume from last checkpoint
./scripts/run.sh work NAME MAX --resume

# Force restart (discard progress)
./scripts/run.sh work NAME MAX --force
```

## Cleanup

Handle stale resources:
```bash
# Run cleanup workflow
/sessions cleanup

# Manual: clear stale lock
rm .claude/locks/{session}.lock

# Manual: kill orphaned tmux
tmux kill-session -t pipeline-{session}
```

---

**Invoke the sessions skill for:** $ARGUMENTS
