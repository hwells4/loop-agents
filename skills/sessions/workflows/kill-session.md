# Workflow: Kill Session

Terminate a running session and clean up its resources.

<required_reading>
**Read these reference files NOW:**
1. references/commands.md
</required_reading>

<process>
## Step 1: Get Session Name

If session name not provided, list available and ask:

```bash
# Get sessions with tmux or locks
sessions=$(
    (tmux list-sessions 2>/dev/null | grep -E "^loop-" | cut -d: -f1 | sed 's/^loop-//';
     ls .claude/locks/*.lock 2>/dev/null | xargs -n1 basename | sed 's/\.lock$//') | sort -u
)

if [ -z "$sessions" ]; then
    echo "No sessions to kill."
    exit 0
fi
```

Use AskUserQuestion if multiple sessions:

```json
{
  "questions": [{
    "question": "Which session do you want to kill?",
    "header": "Session",
    "options": [
      {"label": "auth", "description": "work - iteration 5/25 (RUNNING)"},
      {"label": "old-feature", "description": "work - iteration 12/15 (STALE LOCK)"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Confirm Termination

Use AskUserQuestion to confirm:

```json
{
  "questions": [{
    "question": "Kill session '${session}'? This will stop execution immediately.",
    "header": "Confirm",
    "options": [
      {"label": "Yes, kill it", "description": "Terminate session and clean up resources"},
      {"label": "No, cancel", "description": "Keep session running"}
    ],
    "multiSelect": false
  }]
}
```

If user cancels, exit gracefully.

## Step 3: Show Current State

Before killing, show what we're terminating:

```bash
# Get state info
if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    echo "Session state:"
    jq '{
        type: .loop_type,
        iteration: .iteration,
        iteration_completed: .iteration_completed,
        status: .status,
        started: .started_at
    }' ".claude/pipeline-runs/${session}/state.json"
fi

# Check beads progress for work sessions
loop_type=$(jq -r '.loop_type // ""' ".claude/pipeline-runs/${session}/state.json" 2>/dev/null)
if [ "$loop_type" = "work" ]; then
    remaining=$(bd ready --label="pipeline/${session}" 2>/dev/null | wc -l)
    completed=$(bd list --label="pipeline/${session}" --status=closed 2>/dev/null | wc -l)
    echo ""
    echo "Beads progress: ${completed} completed, ${remaining} remaining"
fi
```

## Step 4: Kill the Session

```bash
# Kill tmux session
if tmux has-session -t "pipeline-${session}" 2>/dev/null; then
    tmux kill-session -t "pipeline-${session}"
    echo "✓ Killed tmux session pipeline-${session}"
else
    echo "• tmux session not found (already dead)"
fi

# Remove lock file
if [ -f ".claude/locks/${session}.lock" ]; then
    rm ".claude/locks/${session}.lock"
    echo "✓ Removed lock file"
else
    echo "• No lock file found"
fi
```

## Step 5: Update State File

Mark session as terminated (don't delete - preserves history):

```bash
if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    # Update status to killed
    jq '.status = "killed" | .killed_at = now | .killed_at |= todate' \
        ".claude/pipeline-runs/${session}/state.json" > /tmp/state.json \
        && mv /tmp/state.json ".claude/pipeline-runs/${session}/state.json"
    echo "✓ Updated state file (status: killed)"
fi
```

## Step 6: Provide Next Actions

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SESSION '${session}' TERMINATED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Progress saved to:
  .claude/pipeline-runs/${session}/progress-${session}.md

Next actions:
  • Resume: ./scripts/run.sh ${type} ${session} ${max} --resume
  • Start fresh: ./scripts/run.sh ${type} ${session} ${max} --force
  • View progress: cat .claude/pipeline-runs/${session}/progress-${session}.md
  • Check beads: bd list --label=pipeline/${session}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
</process>

<success_criteria>
Kill session workflow is complete when:
- [ ] Session name obtained
- [ ] User confirmed termination
- [ ] Current state shown before kill
- [ ] tmux session killed (if exists)
- [ ] Lock file removed (if exists)
- [ ] State file updated (status: killed)
- [ ] Progress file preserved
- [ ] Next actions provided (resume, restart, view)
</success_criteria>
