# Workflow: Launch Pipeline

Configure and launch a selected stage or pipeline in tmux.

<required_context>
This workflow may receive partial context from natural language parsing:

| Field | Required | Source |
|-------|----------|--------|
| `stage` or `pipeline` | Yes | Parsed from user input or ask |
| `session` | Yes | Parsed, derived from branch, or ask |
| `max_iterations` | For stages | Parsed or use defaults |
| `provider` | No | Parsed ("with codex") or stage default |
| `context` | No | Parsed focus area |

**Examples of partial context:**
- `{stage: "ralph", session: "auth", max: 25}` → Ready to launch
- `{stage: "improve-plan", session: "billing"}` → Need iterations
- `{stage: "bug-discovery"}` → Need session name
</required_context>

<process>
## Step 1: Validate Selection

```bash
# For stages
if [ -d "scripts/stages/${selected_name}" ]; then
  echo "Stage '${selected_name}' found"
  cat "scripts/stages/${selected_name}/stage.yaml"
else
  echo "Stage not found"
  ls scripts/stages/
fi

# For pipelines
if [ -f "scripts/pipelines/${selected_name}" ]; then
  echo "Pipeline '${selected_name}' found"
  cat "scripts/pipelines/${selected_name}"
else
  echo "Pipeline not found"
  ls scripts/pipelines/*.yaml
fi
```

## Step 2: Gather Configuration

Ask for required parameters based on type:

### For Stages

```json
{
  "questions": [{
    "question": "What should I name this session?",
    "header": "Session",
    "options": [
      {"label": "Derive from context", "description": "Auto-generate from branch/beads label"},
      {"label": "Custom name", "description": "I'll specify a name"}
    ],
    "multiSelect": false
  }]
}
```

If "Derive from context":
```bash
# Try git branch first
branch=$(git branch --show-current 2>/dev/null | tr '/' '-' | tr '_' '-')
if [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
  session="$branch"
else
  # Try beads label
  label=$(bd list --status=open 2>/dev/null | head -1 | grep -oE 'pipeline/[a-z0-9-]+' | cut -d/ -f2)
  if [ -n "$label" ]; then
    session="$label"
  else
    session="work-$(date +%H%M)"
  fi
fi
echo "Suggested session name: $session"
```

Then ask for max iterations:

```json
{
  "questions": [{
    "question": "Maximum iterations?",
    "header": "Iterations",
    "options": [
      {"label": "10", "description": "Quick run"},
      {"label": "25 (Recommended)", "description": "Standard session"},
      {"label": "50", "description": "Extended session"},
      {"label": "Custom", "description": "Specify a number"}
    ],
    "multiSelect": false
  }]
}
```

### For Pipelines

Just need session name - iterations are defined in the pipeline:

```json
{
  "questions": [{
    "question": "What should I name this session?",
    "header": "Session",
    "options": [
      {"label": "Derive from context", "description": "Auto-generate from branch/beads label"},
      {"label": "Custom name", "description": "I'll specify a name"}
    ],
    "multiSelect": false
  }]
}
```

## Step 3: Check for Advanced Options

```json
{
  "questions": [{
    "question": "Any advanced options?",
    "header": "Options",
    "options": [
      {"label": "Use Defaults (Recommended)", "description": "Start with standard configuration"},
      {"label": "Customize Provider/Model", "description": "Use Codex, specific Claude model, etc."},
      {"label": "Add Context/Inputs", "description": "Inject instructions or input files"}
    ],
    "multiSelect": false
  }]
}
```

**If "Customize Provider/Model":**
```json
{
  "questions": [{
    "question": "Which provider?",
    "header": "Provider",
    "options": [
      {"label": "Claude (Recommended)", "description": "Default, uses Claude Code"},
      {"label": "Codex", "description": "OpenAI's Codex agent"}
    ],
    "multiSelect": false
  }]
}
```

**If "Add Context/Inputs":**
Ask for context string and/or input file paths.

## Step 4: Check for Conflicts

```bash
# Check for existing lock
if [ -f ".claude/locks/${session}.lock" ]; then
  pid=$(jq -r .pid ".claude/locks/${session}.lock")
  if kill -0 "$pid" 2>/dev/null; then
    echo "CONFLICT: Session actively running (PID $pid)"
  else
    echo "STALE: Lock exists but process dead"
  fi
fi

# Check for orphaned tmux
if tmux has-session -t "pipeline-${session}" 2>/dev/null; then
  echo "CONFLICT: tmux session exists"
fi
```

If conflict detected:
```json
{
  "questions": [{
    "question": "Session '${session}' has existing resources. How to proceed?",
    "header": "Conflict",
    "options": [
      {"label": "Resume", "description": "Continue from where it stopped (--resume)"},
      {"label": "Force Restart", "description": "Clear and start fresh (--force)"},
      {"label": "Different Name", "description": "Choose another session name"}
    ],
    "multiSelect": false
  }]
}
```

## Step 5: Validate Prerequisites

### For Ralph/Work Stages

```bash
# Check beads exist
count=$(bd ready 2>/dev/null | wc -l | xargs)
if [ "$count" -eq 0 ]; then
  echo "WARNING: No ready beads found"
  echo "Ralph works best with beads to process"
fi
```

### For All Types

```bash
# Verify dependencies
command -v claude >/dev/null || echo "ERROR: claude CLI not found"
command -v tmux >/dev/null || echo "ERROR: tmux not found"
command -v jq >/dev/null || echo "ERROR: jq not found"
```

## Step 6: Show Pre-Launch Summary and Confirm

Before executing, show exactly what will run:

```
## Pre-Launch Summary

Type: {stage or pipeline name}
Session: {session}
Provider: {provider:-claude} ({model:-opus})
Termination: {termination type from stage.yaml}
Max iterations: {max_iterations}

{For stages with beads:}
Beads ready: {count} with label 'pipeline/{session}'

{For pipelines:}
Stages: {list stages from pipeline yaml}

{If any flags:}
Flags: {--resume, --force, --context="...", --input=...}

Command: ./scripts/run.sh {stage} {session} {max} [flags]
```

Use AskUserQuestion to confirm:

```json
{
  "questions": [{
    "question": "Ready to launch?",
    "header": "Confirm",
    "options": [
      {"label": "Launch", "description": "Start the session now"},
      {"label": "Edit Config", "description": "Change provider, model, or other settings"},
      {"label": "Cancel", "description": "Don't start, return to conversation"}
    ],
    "multiSelect": false
  }]
}
```

**If "Launch":** Proceed to Step 7
**If "Edit Config":** Return to Step 3 to modify options
**If "Cancel":** Abort with confirmation message

## Step 7: Execute Command

**For Stages:**
```bash
cmd="./scripts/run.sh ${stage} ${session} ${max_iterations}"

# Add options
[ -n "$provider" ] && cmd="$cmd --provider=$provider"
[ -n "$model" ] && cmd="$cmd --model=$model"
[ -n "$context" ] && cmd="$cmd --context=\"$context\""
[ -n "$resume" ] && cmd="$cmd --resume"
[ -n "$force" ] && cmd="$cmd --force"

# Add input files
for input in "${inputs[@]}"; do
  cmd="$cmd --input=$input"
done

echo "Executing: $cmd"
eval "$cmd"
```

**For Pipelines:**
```bash
cmd="./scripts/run.sh pipeline ${pipeline} ${session}"

# Add options (same as above)
echo "Executing: $cmd"
eval "$cmd"
```

## Step 8: Verify and Report

```bash
# Wait briefly
sleep 2

# Verify started
if tmux has-session -t "pipeline-${session}" 2>/dev/null; then
  echo "Session started successfully"

  # Show initial state
  if [ -f ".claude/pipeline-runs/${session}/state.json" ]; then
    jq '{session, status, iteration, stage}' ".claude/pipeline-runs/${session}/state.json"
  fi
else
  echo "ERROR: Session failed to start"
  # Try to diagnose
  cat ".claude/pipeline-runs/${session}/state.json" 2>/dev/null
fi
```

Present next actions:
```
Session '${session}' is now running.

Monitor commands:
  tmux capture-pane -t pipeline-${session} -p | tail -50  # Quick peek
  tmux attach -t pipeline-${session}                       # Watch live (Ctrl+b d to detach)
  ./scripts/run.sh status ${session}                       # Detailed status

Management:
  /sessions monitor ${session}
  /sessions kill ${session}
```
</process>

<success_criteria>
- [ ] Selection validated (stage/pipeline exists)
- [ ] Session name determined (derived or custom)
- [ ] Iteration count set (for stages)
- [ ] Conflicts detected and resolved
- [ ] Prerequisites verified
- [ ] Pre-launch summary shown to user
- [ ] User confirmed launch via AskUserQuestion
- [ ] Session launched successfully
- [ ] Startup confirmed via tmux check
- [ ] Clear next actions provided
</success_criteria>
