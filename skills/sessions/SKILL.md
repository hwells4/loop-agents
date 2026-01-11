---
name: sessions
description: Run and manage autonomous loop agents and pipelines in tmux sessions. Start loops, start pipelines, monitor output, attach/detach, list running sessions, kill sessions, and clean up stale work. Use when running autonomous tasks in the background.
---

## What This Skill Does

Runs autonomous loop agents and multi-stage pipelines in tmux background sessions. You can:
- Start any loop type (work, improve-plan, refine-beads, idea-wizard, custom)
- Start pipelines (multi-stage workflows that chain loops together)
- Monitor running sessions without attaching
- Attach to watch live, detach to continue in background
- List all running sessions with status
- Kill sessions
- Clean up stale or orphaned sessions

## Session Lifecycle

Every tmux session you start MUST be tracked. When you start a session, update the state file. When it completes or you kill it, clean up.

**State File:** `.claude/loop-sessions.json`
```json
{
  "sessions": {
    "loop-auth": {
      "type": "loop",
      "loop_type": "work",
      "started_at": "2025-01-10T10:00:00Z",
      "project_path": "/path/to/project",
      "max_iterations": 50,
      "status": "running"
    },
    "pipeline-refine": {
      "type": "pipeline",
      "pipeline_file": "full-refine.yaml",
      "started_at": "2025-01-10T11:00:00Z",
      "project_path": "/path/to/project",
      "status": "running"
    }
  }
}
```

**Naming Conventions:**
- Loops: `loop-{feature-name}` (lowercase, hyphens)
- Pipelines: `pipeline-{name}` (lowercase, hyphens)

**Stale Session Warning:** Sessions running > 2 hours should trigger a warning.

**Never Leave Orphans:** Before ending a conversation where you started a session, remind the user about running sessions.

## Intake

Use the AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Action",
    "options": [
      {"label": "Start Loop", "description": "Run a loop agent in tmux background"},
      {"label": "Start Pipeline", "description": "Run a multi-stage pipeline in tmux"},
      {"label": "Monitor", "description": "Peek at output from a running session"},
      {"label": "Attach", "description": "Connect to watch a session live"},
      {"label": "List", "description": "Show all running sessions"},
      {"label": "Kill", "description": "Terminate a running session"},
      {"label": "Cleanup", "description": "Find and handle stale sessions"}
    ],
    "multiSelect": false
  }]
}
```

**Wait for response before proceeding.**

## Routing

| Response | Workflow |
|----------|----------|
| "Start Loop" | `workflows/start-loop.md` |
| "Start Pipeline" | `workflows/start-pipeline.md` |
| "Monitor" | `workflows/monitor.md` |
| "Attach" | `workflows/attach.md` |
| "List" | `workflows/list.md` |
| "Kill" | `workflows/kill.md` |
| "Cleanup" | `workflows/cleanup.md` |

**After reading the workflow, follow it exactly.**

## Quick Reference

```bash
# Discover available loops
ls scripts/loops/

# Discover available pipelines
ls scripts/pipelines/*.yaml

# Start a loop
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh loop TYPE NAME MAX"

# Start a loop with force (override existing lock)
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh loop TYPE NAME MAX --force"

# Start a pipeline
tmux new-session -d -s pipeline-NAME -c "$(pwd)" "./scripts/run.sh pipeline FILE.yaml NAME"

# Peek at output (safe, doesn't attach)
tmux capture-pane -t SESSION_NAME -p | tail -50

# Attach to session
tmux attach -t SESSION_NAME
# Detach: Ctrl+b, then d

# List sessions
tmux list-sessions 2>/dev/null | grep -E "^(loop-|pipeline-)"

# Kill session
tmux kill-session -t SESSION_NAME

# Check loop state
cat .claude/loop-state-NAME.json | jq '.status'

# Check pipeline state
cat .claude/pipeline-runs/NAME/state.json | jq '.status'

# Check session locks
ls .claude/locks/
cat .claude/locks/NAME.lock | jq

# Clear stale lock
rm .claude/locks/NAME.lock
```

## Reference Index

| Reference | Purpose |
|-----------|---------|
| references/tmux.md | Complete tmux command reference |
| references/state-files.md | State file operations and schema |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| start-loop.md | Start any loop type in tmux |
| start-pipeline.md | Start a pipeline in tmux |
| monitor.md | Safely peek at output |
| attach.md | Connect to watch live |
| list.md | Show all running sessions |
| kill.md | Terminate a session |
| cleanup.md | Find and handle stale sessions |

## Success Criteria

- [ ] User selected action (or provided direct command)
- [ ] Correct workflow executed
- [ ] Session state file updated appropriately
- [ ] User shown clear instructions for next steps
- [ ] No orphaned sessions left untracked
