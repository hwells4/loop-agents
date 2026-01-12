# Workflow: Start Session

Launch a new single-stage or multi-stage pipeline session in tmux background.

<required_reading>
**Read these reference files NOW:**
1. references/commands.md
</required_reading>

<process>
## Step 1: Gather Session Parameters

If session name not provided, ask:

```json
{
  "questions": [{
    "question": "What type of session do you want to start?",
    "header": "Type",
    "options": [
      {"label": "Work", "description": "Implement beads until queue empty (Recommended)"},
      {"label": "Refinement Pipeline", "description": "Multi-stage refinement (improve-plan + refine-beads)"},
      {"label": "Custom Stage", "description": "Run a specific stage type"}
    ],
    "multiSelect": false
  }]
}
```

**If Work:** Ask for session name and max iterations
**If Refinement Pipeline:** Ask which pipeline (quick/full/deep) and session name
**If Custom Stage:** Discover available stages and ask which one

### Discover Available Options

```bash
# List stage types
ls scripts/stages/

# List pipelines
ls scripts/pipelines/*.yaml 2>/dev/null | xargs -n1 basename
```

## Step 2: Validate Session Name

Session names must be lowercase with hyphens only.

```bash
# Check if valid
if [[ ! "$session" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "Invalid session name. Use lowercase letters, numbers, and hyphens."
    exit 1
fi
```

## Step 3: Check for Conflicts

```bash
# Check for existing lock
if [ -f ".claude/locks/${session}.lock" ]; then
    # Check if PID is alive
    pid=$(jq -r .pid ".claude/locks/${session}.lock")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Session is actively running"
        # Offer: attach, kill then restart, or choose different name
    else
        echo "Stale lock detected (process dead)"
        # Offer: resume, force restart, or cleanup first
    fi
fi

# Check for orphaned tmux session
if tmux has-session -t "pipeline-${session}" 2>/dev/null; then
    echo "tmux session exists"
    # Offer: attach, kill then restart
fi
```

### Conflict Resolution

Use AskUserQuestion if conflict detected:

```json
{
  "questions": [{
    "question": "Session 'auth' already has resources. How should I proceed?",
    "header": "Conflict",
    "options": [
      {"label": "Resume", "description": "Continue from where it crashed (--resume)"},
      {"label": "Force Restart", "description": "Kill existing and start fresh (--force)"},
      {"label": "Attach", "description": "Connect to the running session instead"},
      {"label": "Different Name", "description": "Choose a different session name"}
    ],
    "multiSelect": false
  }]
}
```

## Step 4: Validate Prerequisites

**For single-stage:**
```bash
# Check stage exists
if [ ! -d "scripts/stages/${stage}" ]; then
    echo "Stage '${stage}' not found"
    echo "Available stages:"
    ls scripts/stages/
    exit 1
fi
```

**For multi-stage pipeline:**
```bash
# Check pipeline exists
if [ ! -f "scripts/pipelines/${pipeline}" ]; then
    echo "Pipeline '${pipeline}' not found"
    echo "Available pipelines:"
    ls scripts/pipelines/*.yaml
    exit 1
fi
```

**For work sessions:** Check beads exist
```bash
bd ready --label="pipeline/${session}" 2>/dev/null | head -3
# If empty, warn user there are no beads to work on
```

## Step 5: Start the Session

**Single-stage (work, improve-plan, etc.):**
```bash
tmux new-session -d -s "pipeline-${session}" -c "$(pwd)" \
    "./scripts/run.sh ${stage} ${session} ${max_iterations}"
```

**Multi-stage pipeline:**
```bash
tmux new-session -d -s "pipeline-${session}" -c "$(pwd)" \
    "./scripts/run.sh pipeline ${pipeline} ${session}"
```

**With flags:**
```bash
# Resume after crash
./scripts/run.sh ${stage} ${session} ${max} --resume

# Force override existing lock
./scripts/run.sh ${stage} ${session} ${max} --force
```

## Step 6: Verify Startup

```bash
# Wait briefly for startup
sleep 2

# Verify tmux session exists
if ! tmux has-session -t "pipeline-${session}" 2>/dev/null; then
    echo "ERROR: Session failed to start"
    # Check for startup errors
    cat ".claude/pipeline-runs/${session}/state.json" 2>/dev/null | jq
    exit 1
fi

# Verify state file created
if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    echo "Session started successfully"
    cat ".claude/pipeline-runs/${session}/state.json" | jq '{session, status, iteration}'
else
    echo "WARNING: State file not yet created (may still be initializing)"
fi
```

## Step 7: Provide Next Actions

After successful start, show:

```
Session '${session}' started successfully.

Current status:
  Stage: ${stage}
  Iteration: 1/${max}
  Status: running

Next actions:
  • Monitor: tmux capture-pane -t pipeline-${session} -p | tail -50
  • Attach:  tmux attach -t pipeline-${session}  (Ctrl+b, d to detach)
  • Kill:    tmux kill-session -t pipeline-${session}
  • Status:  ./scripts/run.sh status ${session}
```

</process>

<success_criteria>
Start session workflow is complete when:
- [ ] Session type determined (work, pipeline, custom)
- [ ] Session name validated (lowercase, hyphens only)
- [ ] Conflicts detected and resolved
- [ ] Prerequisites validated (stage/pipeline exists)
- [ ] Session started in tmux
- [ ] Startup verified (tmux session exists)
- [ ] Clear next actions provided to user
</success_criteria>
