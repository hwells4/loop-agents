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
./scripts/run.sh ralph my-session 25
```

**With advanced options:**
```bash
# Use Codex provider
./scripts/run.sh ralph my-session 25 --provider=codex --model=o3

# Inject context
./scripts/run.sh ralph my-session 25 --context="Focus on error handling"

# Pass initial inputs
./scripts/run.sh ralph my-session 25 --input docs/plan.md --input docs/requirements.md
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
| **Ralph** | `./scripts/run.sh ralph NAME MAX` | All beads complete |
| **Improve Plan** | `./scripts/run.sh improve-plan NAME MAX` | 2 agents agree |
| **Refine Beads** | `./scripts/run.sh refine-tasks NAME MAX` | 2 agents agree |
| **Pipeline** | `./scripts/run.sh pipeline FILE NAME` | All stages complete |

## Session Resources

Each session creates:
- **Lock file:** `.claude/locks/{session}.lock`
- **State file:** `.claude/pipeline-runs/{session}/state.json`
- **Progress file:** `.claude/pipeline-runs/{session}/progress-{session}.md`
- **tmux session:** `pipeline-{session}`
- **Parallel blocks** (if used): `parallel-{XX}-{name}/providers/{provider}/`

### Parallel Block Layout

When pipelines use parallel blocks, additional directories are created:

```
.claude/pipeline-runs/{session}/
├── stage-00-setup/
├── parallel-01-dual-refine/
│   ├── manifest.json              # Aggregated outputs
│   ├── resume.json                # Crash recovery hints
│   └── providers/
│       ├── claude/
│       │   ├── progress.md
│       │   ├── state.json
│       │   └── stage-00-plan/iterations/001/
│       └── codex/
│           ├── progress.md
│           ├── state.json
│           └── stage-00-plan/iterations/001/
└── stage-02-synthesize/
```

## Crash Recovery

If a session crashes:
```bash
# Check status
./scripts/run.sh status NAME

# Resume from last checkpoint
./scripts/run.sh ralph NAME MAX --resume

# Force restart (discard progress)
./scripts/run.sh ralph NAME MAX --force
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
