---
name: monitor
description: Active debugging companion for pipeline sessions - watches, validates, and verifies operations in real-time
---

<objective>
Actively debug running pipeline sessions by watching tmux output, validating state files, reading iteration outputs as they happen, and verifying everything operates correctly. This is a hands-on debugging companion, not just a status checker.
</objective>

<essential_principles>
## Philosophy
The monitor skill is an ACTIVE debugging companion. Unlike `/sessions` which shows status snapshots, `/monitor` follows along in real-time:

1. **Watch, don't just check** - Follow iterations as they complete, not just point-in-time status
2. **Validate everything** - Check files exist, JSON is valid, paths are correct
3. **Read the content** - Actually look at what agents are outputting
4. **Alert on issues** - Proactively surface problems before they cascade
5. **Stay attached** - Maintain awareness of the session throughout

## Key Files to Monitor
```
.claude/locks/{session}.lock              # Lock: PID, start time
.claude/pipeline-runs/{session}/
├── state.json                            # Iteration tracking, history
├── progress-{session}.md                 # Accumulated learnings
├── stage-NN-{stage}/iterations/NNN/
│   ├── context.json                      # Input context (check: inputs, commands)
│   ├── output.md                         # Agent output
│   └── status.json                       # Decision (continue/stop/error)
└── parallel-NN-{block}/                  # Parallel block (if present)
    ├── manifest.json                     # Aggregated outputs
    ├── resume.json                       # Per-provider recovery hints
    └── providers/
        ├── claude/
        │   ├── progress.md               # Provider-isolated progress
        │   ├── state.json                # Provider-specific state
        │   └── stage-NN-{stage}/iterations/NNN/
        └── codex/
            ├── progress.md
            ├── state.json
            └── stage-NN-{stage}/iterations/NNN/
```

## Health Checks
- Lock file exists and PID is alive
- State.json is valid JSON with required fields
- iteration_completed matches directory count
- status.json has valid decision enum
- Progress file is growing
- context.json contains inputs and commands objects
- For parallel blocks: manifest.json exists, all providers have subdirectories
</essential_principles>

<usage>
```
/monitor                    # Interactive: choose what to monitor
/monitor start             # Start a pipeline and actively watch it
/monitor attach            # Attach to running session and debug
/monitor validate          # Validate all state files for a session
/monitor watch             # Watch iterations complete in real-time
/monitor health            # Quick health check of a session
```
</usage>

<intake>
If no subcommand provided, use AskUserQuestion:
```json
{
  "questions": [{
    "question": "What would you like to monitor?",
    "header": "Monitor Mode",
    "options": [
      {"label": "Start & Watch", "description": "Start a new pipeline and actively watch it run"},
      {"label": "Attach & Debug", "description": "Attach to a running session and debug it"},
      {"label": "Validate State", "description": "Check all state files are correct and valid"},
      {"label": "Watch Iterations", "description": "Follow iteration outputs in real-time"},
      {"label": "Health Check", "description": "Quick health check of session resources"}
    ],
    "multiSelect": false
  }]
}
```
</intake>

<routing>
| Response / Subcommand | Workflow |
|----------------------|----------|
| "Start & Watch" or `start` | `workflows/start-and-watch.md` |
| "Attach & Debug" or `attach` | `workflows/attach-debug.md` |
| "Validate State" or `validate` | `workflows/validate-state.md` |
| "Watch Iterations" or `watch` | `workflows/watch-iterations.md` |
| "Health Check" or `health` | `workflows/health-check.md` |

**Intent-based routing:**
- "start a pipeline and watch" → start-and-watch
- "debug session X" → attach-debug
- "check state files" → validate-state
- "follow along" → watch-iterations
- "is X healthy" → health-check
</routing>

<quick_start>
```bash
# Check if session is running
tmux has-session -t pipeline-{session} 2>/dev/null && echo "RUNNING" || echo "NOT RUNNING"

# Peek at tmux output (non-blocking)
tmux capture-pane -t pipeline-{session} -p | tail -50

# Validate state file
cat .claude/pipeline-runs/{session}/state.json | jq .

# Check lock file
cat .claude/locks/{session}.lock | jq .

# Count completed iterations
ls .claude/pipeline-runs/{session}/stage-*/iterations/ 2>/dev/null | wc -l

# Read latest iteration output
latest=$(ls -d .claude/pipeline-runs/{session}/stage-*/iterations/*/ 2>/dev/null | tail -1)
cat "$latest/output.md"

# Read latest status decision
cat "$latest/status.json" | jq -r '.decision'
```
</quick_start>

<workflows_index>
| Workflow | Purpose |
|----------|---------|
| start-and-watch.md | Start a pipeline and actively monitor it through startup and first iterations |
| attach-debug.md | Attach to running session and perform active debugging |
| validate-state.md | Comprehensive validation of all state files |
| watch-iterations.md | Real-time monitoring of iteration outputs |
| health-check.md | Quick health check of session resources |
</workflows_index>

<success_criteria>
- [ ] Session resources verified (tmux, lock, state files exist)
- [ ] State file JSON is valid with all required fields
- [ ] Iteration count matches state tracking
- [ ] Latest iteration output read and summarized
- [ ] Any issues or anomalies surfaced to user
- [ ] Clear next steps provided based on findings
</success_criteria>
