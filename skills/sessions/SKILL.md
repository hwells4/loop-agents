---
name: sessions
description: Manage autonomous loop agent sessions running in tmux background. Start, list, monitor, attach, kill, and clean up pipeline sessions.
---

<objective>
Provide a unified interface for managing loop agent sessions. Sessions are autonomous pipelines that run in tmux, executing iteratively until completion. This skill handles the full lifecycle: starting new sessions, monitoring progress, managing conflicts, and cleaning up resources.
</objective>

<essential_principles>
## Everything Is A Pipeline

A "loop" is a single-stage pipeline. The unified engine treats them identically.
- **Single-stage**: `./scripts/run.sh work auth 25`
- **Multi-stage**: `./scripts/run.sh pipeline full-refine.yaml myproject`

Both use the same directory structure, state files, and lock management.

## Session Resources

Each session creates three resources that must stay synchronized:
1. **Lock file** (`.claude/locks/{session}.lock`) - Prevents duplicates
2. **State file** (`.claude/pipeline-runs/{session}/state.json`) - Tracks progress
3. **tmux session** (`pipeline-{session}`) - Runs the actual process

Problems occur when these get out of sync (crashes, force-kills, network issues).

## Naming Conventions

- Session names: lowercase, hyphens only (`auth`, `billing-refactor`)
- tmux sessions: `pipeline-{session}`
- Beads labels: `pipeline/{session}`

## Validation First

Always check prerequisites before action:
- Stage/pipeline exists
- No conflicts (or user resolved them)
- Required dependencies available
</essential_principles>

<usage>
```
/sessions                    # Interactive - choose action
/sessions start              # Start a new session
/sessions list               # Show all running sessions
/sessions monitor auth       # Peek at session output
/sessions attach auth        # Connect to watch live
/sessions kill auth          # Terminate a session
/sessions cleanup            # Handle stale resources
/sessions status auth        # Check session status
```
</usage>

<intake>
If no subcommand provided, use AskUserQuestion:

```json
{
  "questions": [{
    "question": "What would you like to do with loop sessions?",
    "header": "Action",
    "options": [
      {"label": "Start", "description": "Launch a new session (single-stage or multi-stage pipeline)"},
      {"label": "List", "description": "Show all running sessions with status"},
      {"label": "Monitor", "description": "Peek at session output without attaching"},
      {"label": "Attach", "description": "Connect to watch session live (read-only)"},
      {"label": "Kill", "description": "Terminate a running session"},
      {"label": "Cleanup", "description": "Handle stale locks, orphaned sessions, zombies"}
    ],
    "multiSelect": false
  }]
}
```
</intake>

<routing>
| Response | Workflow |
|----------|----------|
| "Start" or `start` | `workflows/start-session.md` |
| "List" or `list` | `workflows/list-sessions.md` |
| "Monitor" or `monitor` | `workflows/monitor-session.md` |
| "Attach" or `attach` | `workflows/attach-session.md` |
| "Kill" or `kill` | `workflows/kill-session.md` |
| "Cleanup" or `cleanup` | `workflows/cleanup.md` |
| `status {name}` | `workflows/check-status.md` |

**Intent-based routing (if user provides clear intent):**
- "start a work loop", "run pipeline" → `workflows/start-session.md`
- "what's running", "show sessions" → `workflows/list-sessions.md`
- "check on auth", "peek at" → `workflows/monitor-session.md`
- "watch auth live", "attach to" → `workflows/attach-session.md`
- "stop auth", "kill session" → `workflows/kill-session.md`
- "fix stale", "clear locks", "cleanup" → `workflows/cleanup.md`

**After reading the workflow, follow it exactly.**
</routing>

<quick_start>
**Start a work session:**
```bash
./scripts/run.sh work my-session 25
```

**Check what's running:**
```bash
tmux list-sessions 2>/dev/null | grep -E "^loop-"
```

**Peek at output:**
```bash
tmux capture-pane -t pipeline-{session} -p | tail -50
```

**Full status check:**
```bash
./scripts/run.sh status {session}
```
</quick_start>

<reference_index>
All domain knowledge in `references/`:

**Commands:** commands.md - All bash commands for session management
**Stage Types:** Available via `ls scripts/stages/`
**Pipelines:** Available via `ls scripts/pipelines/*.yaml`
</reference_index>

<workflows_index>
| Workflow | Purpose |
|----------|---------|
| start-session.md | Launch a new single-stage or multi-stage session |
| list-sessions.md | Show all running sessions with status |
| monitor-session.md | Peek at session output without attaching |
| attach-session.md | Connect to watch session live |
| kill-session.md | Terminate a running session |
| cleanup.md | Handle stale locks, orphaned sessions, zombies |
| check-status.md | Get detailed status of a specific session |
</workflows_index>

<success_criteria>
Any session operation should:
- [ ] Validate all prerequisites
- [ ] Handle edge cases (crashes, conflicts, stale state)
- [ ] Provide clear feedback on what happened
- [ ] Offer logical next actions
- [ ] Not leave orphaned resources
</success_criteria>
