# Workflow: Start a Session

Start any session (single-stage loop or multi-stage pipeline) in a tmux background session.

> **Everything is a pipeline.** A "loop" is just a single-stage pipeline. This workflow handles both.

## Step 1: Determine Session Type

Ask what kind of session to start:

```json
{
  "questions": [{
    "question": "What type of session do you want to run?",
    "header": "Session Type",
    "options": [
      {"label": "Single-stage (loop)", "description": "Run one stage type until completion (e.g., work, improve-plan)"},
      {"label": "Multi-stage (pipeline)", "description": "Chain multiple stages together (e.g., quick-refine, full-refine)"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Discover Available Options

### For single-stage:
```bash
ls scripts/loops/
```

Common stages:
- `work` - Implements beads until none remain (beads-empty)
- `improve-plan` - Refines a plan until plateau (plateau)
- `refine-beads` - Improves beads until plateau (plateau)
- `idea-wizard` - Generates ideas for N iterations (fixed-n)

### For multi-stage:
```bash
ls scripts/pipelines/*.yaml 2>/dev/null || echo "No pipelines found"
```

Common pipelines:
- `quick-refine.yaml` - 3+3 iterations (improve-plan → refine-beads)
- `full-refine.yaml` - 5+5 iterations (standard)
- `deep-refine.yaml` - 8+8 iterations (thorough)

## Step 3: Select Stage/Pipeline

### For single-stage:
```json
{
  "questions": [{
    "question": "Which stage type do you want to run?",
    "header": "Stage Type",
    "options": [
      {"label": "work", "description": "Implement beads until all done"},
      {"label": "improve-plan", "description": "Refine a plan doc until plateau"},
      {"label": "refine-beads", "description": "Improve beads until plateau"},
      {"label": "idea-wizard", "description": "Generate ideas for N iterations"}
    ],
    "multiSelect": false
  }]
}
```

### For multi-stage:
```json
{
  "questions": [{
    "question": "Which pipeline do you want to run?",
    "header": "Pipeline",
    "options": [
      {"label": "quick-refine", "description": "Fast 3+3 iteration refinement"},
      {"label": "full-refine", "description": "Standard 5+5 iteration refinement"},
      {"label": "deep-refine", "description": "Thorough 8+8 iteration refinement"}
    ],
    "multiSelect": false
  }]
}
```

Adapt options based on what actually exists.

## Step 4: Get Session Name

```json
{
  "questions": [{
    "question": "What should we call this session? (used for state files and bead labels)",
    "header": "Session Name",
    "options": [
      {"label": "Let me type a name", "description": "I'll provide a custom session name"}
    ],
    "multiSelect": false
  }]
}
```

Session name rules:
- Lowercase letters and hyphens only
- No spaces
- Examples: `auth`, `billing-refactor`, `docs-update`

The tmux session will be `loop-{session-name}`.

## Step 5: Get Max Iterations (single-stage only)

For single-stage sessions, ask for max iterations:

```json
{
  "questions": [{
    "question": "How many maximum iterations?",
    "header": "Max Iterations",
    "options": [
      {"label": "5", "description": "Quick run - good for testing or plateau stages"},
      {"label": "25", "description": "Standard for work stages"},
      {"label": "50", "description": "Thorough - for larger tasks"}
    ],
    "multiSelect": false
  }]
}
```

**Defaults by stage type:**
- work: 25-50 (depends on task size)
- improve-plan: 5-10 (plateau typically hit around 3-5)
- refine-beads: 5-10 (plateau typically hit around 3-5)
- idea-wizard: 3-5 (fixed-n, specify exactly what you want)

## Step 6: Check for Existing/Crashed Sessions

```bash
# Check session status
./scripts/run.sh status {session-name}

# Check if tmux session exists
tmux has-session -t loop-{session-name} 2>/dev/null && echo "TMUX_EXISTS" || echo "NO_TMUX"

# Check if lock file exists
test -f .claude/locks/{session-name}.lock && echo "LOCKED" || echo "NO_LOCK"
```

### If session shows "CRASHED" or "failed":
```json
{
  "questions": [{
    "question": "Found a crashed session '{session-name}'. What should we do?",
    "header": "Crashed Session",
    "options": [
      {"label": "Resume", "description": "Continue from last completed iteration (--resume)"},
      {"label": "Start fresh", "description": "Clear state and start from iteration 1 (--force)"},
      {"label": "Choose different name", "description": "I'll pick another name"}
    ],
    "multiSelect": false
  }]
}
```

### If TMUX_EXISTS:
```json
{
  "questions": [{
    "question": "A session named 'loop-{session-name}' already exists in tmux. What should we do?",
    "header": "Conflict",
    "options": [
      {"label": "Attach to existing", "description": "Connect to the running session"},
      {"label": "Kill and restart", "description": "Stop existing and start fresh"},
      {"label": "Choose different name", "description": "I'll pick another name"}
    ],
    "multiSelect": false
  }]
}
```

### If LOCKED but NO_TMUX (stale lock):
```bash
cat .claude/locks/{session-name}.lock | jq
```

```json
{
  "questions": [{
    "question": "Found stale lock for '{session-name}' (PID not running). What should we do?",
    "header": "Stale Lock",
    "options": [
      {"label": "Clear lock and start", "description": "Remove stale lock, start fresh"},
      {"label": "Force start", "description": "Use --force flag to override"},
      {"label": "Choose different name", "description": "I'll pick another name"}
    ],
    "multiSelect": false
  }]
}
```

If they choose "Clear lock and start":
```bash
rm .claude/locks/{session-name}.lock
```

## Step 7: Validate Prerequisites

### For single-stage:
```bash
# Check stage exists
test -d scripts/loops/{stage-type} && echo "OK" || echo "MISSING: scripts/loops/{stage-type}/"

# Check run script exists
test -f scripts/run.sh && echo "OK" || echo "MISSING: scripts/run.sh"
```

### For multi-stage:
```bash
# Check pipeline file exists
test -f scripts/pipelines/{pipeline-name}.yaml && echo "OK" || echo "MISSING"

# Check referenced stages exist
for stage in $(grep "loop:" scripts/pipelines/{pipeline-name}.yaml | awk '{print $2}'); do
  test -d "scripts/loops/$stage" && echo "OK: $stage" || echo "MISSING: scripts/loops/$stage/"
done
```

If anything is missing, warn the user and stop.

## Step 8: Start the Session

Get absolute path and start in tmux:

```bash
PROJECT_PATH="$(pwd)"
```

### For single-stage:
```bash
# Build command with optional flags
CMD="./scripts/run.sh {stage-type} {session-name} {max-iterations}"
# Add --resume or --force if selected in Step 6

tmux new-session -d -s "loop-{session-name}" -c "$PROJECT_PATH" "$CMD"
```

### For multi-stage:
```bash
tmux new-session -d -s "loop-{session-name}" -c "$PROJECT_PATH" \
  "./scripts/run.sh pipeline {pipeline-name}.yaml {session-name}"
```

## Step 9: Verify Session Started

```bash
# Give it a moment to start
sleep 1

# Check if running
tmux has-session -t loop-{session-name} 2>/dev/null && echo "RUNNING" || echo "FAILED"
```

If FAILED:
```bash
tmux capture-pane -t loop-{session-name} -p 2>/dev/null || echo "Session failed to start"
```

## Step 10: Verify Engine State

The engine automatically creates state files. Verify:

```bash
# Check state file was created
test -f .claude/pipeline-runs/{session-name}/state.json && echo "OK" || echo "MISSING"

# Quick status check
./scripts/run.sh status {session-name}
```

## Step 11: Show Success Message

### For single-stage:
```
Session started: loop-{session-name}

Stage: {stage-type}
Max iterations: {max-iterations}

Quick commands:
  Monitor:  tmux capture-pane -t loop-{session-name} -p | tail -50
  Attach:   tmux attach -t loop-{session-name}
  Detach:   Ctrl+b, then d
  Kill:     tmux kill-session -t loop-{session-name}

Progress tracking:
  State:    cat .claude/pipeline-runs/{session-name}/state.json | jq
  Progress: cat .claude/pipeline-runs/{session-name}/progress-{session-name}.md
  Beads:    bd ready --label=loop/{session-name}

The session is running in the background. Use 'Monitor' to check progress.
```

### For multi-stage:
```
Session started: loop-{session-name}

Pipeline: {pipeline-name}.yaml
Stages: [list from pipeline file]

Quick commands:
  Monitor:  tmux capture-pane -t loop-{session-name} -p | tail -50
  Attach:   tmux attach -t loop-{session-name}
  Detach:   Ctrl+b, then d
  Kill:     tmux kill-session -t loop-{session-name}

Progress tracking:
  State:    cat .claude/pipeline-runs/{session-name}/state.json | jq
  Stages:   ls .claude/pipeline-runs/{session-name}/

The pipeline is running in the background. Use 'Monitor' to check progress.
```

## Success Criteria

- [ ] Session type selected (single-stage or multi-stage)
- [ ] Stage/pipeline selected and validated
- [ ] Session name collected (lowercase, hyphens)
- [ ] No conflicts (or resolved via resume/force/kill)
- [ ] Prerequisites verified
- [ ] tmux session started successfully
- [ ] State file created in `.claude/pipeline-runs/{session-name}/`
- [ ] User shown monitoring instructions
