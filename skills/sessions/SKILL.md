---
name: sessions
description: Run and manage autonomous loop agents and pipelines in tmux sessions. Start sessions, monitor output, attach/detach, list running sessions, kill sessions, and clean up stale work. Use when running autonomous tasks in the background.
---

## CRITICAL: Everything Is A Pipeline

A "loop" is a **single-stage pipeline**. The unified engine treats them identically.

- **Single-stage session** = what we call a "loop" (e.g., `work`, `improve-plan`)
- **Multi-stage session** = what we call a "pipeline" (e.g., `full-refine.yaml`)

All sessions run in `.claude/pipeline-runs/{session}/` with the same state tracking.

## What This Skill Does

Runs autonomous sessions in tmux background. You can:
- Start any session (single-stage loops OR multi-stage pipelines)
- Monitor running sessions without attaching
- Attach to watch live, detach to continue in background
- List all running sessions with status
- Kill sessions
- Clean up stale or orphaned sessions

## Session Lifecycle

Every session runs in an isolated directory with its own state. The engine automatically tracks everything.

**Run Directory:** `.claude/pipeline-runs/{session}/`

Each session gets:
- `state.json` - Iteration tracking, crash recovery info
- `progress-{session}.md` - Accumulated context for fresh agents
- Lock file at `.claude/locks/{session}.lock`

**Check session status:**
```bash
./scripts/run.sh status {session-name}
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
      {"label": "Start Session", "description": "Run a loop or pipeline in tmux background"},
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
| "Start Session" | `workflows/start.md` |
| "Monitor" | `workflows/monitor.md` |
| "Attach" | `workflows/attach.md` |
| "List" | `workflows/list.md` |
| "Kill" | `workflows/kill.md` |
| "Cleanup" | `workflows/cleanup.md` |

**After reading the workflow, follow it exactly.**

## Quick Reference

```bash
# Discover available stages (single-stage options)
ls scripts/loops/

# Discover available pipelines (multi-stage options)
ls scripts/pipelines/*.yaml

# Start a single-stage session (all equivalent)
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh TYPE NAME MAX"
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh loop TYPE NAME MAX"

# Start a multi-stage session
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh pipeline FILE.yaml NAME"

# Start with force (override existing lock)
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh TYPE NAME MAX --force"

# Resume a crashed session
tmux new-session -d -s loop-NAME -c "$(pwd)" "./scripts/run.sh TYPE NAME MAX --resume"

# Check session status
./scripts/run.sh status NAME

# Peek at output (safe, doesn't attach)
tmux capture-pane -t SESSION_NAME -p | tail -50

# Attach to session
tmux attach -t SESSION_NAME
# Detach: Ctrl+b, then d

# List sessions
tmux list-sessions 2>/dev/null | grep -E "^(loop-|pipeline-)"

# Kill session
tmux kill-session -t SESSION_NAME

# Check session state (all sessions use unified path)
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
| start.md | Start any session (single-stage or multi-stage) in tmux |
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
