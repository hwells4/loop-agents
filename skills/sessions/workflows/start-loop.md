# Workflow: Start a Loop

Start any loop type in a tmux background session.

## Step 1: Discover Available Loops

```bash
ls scripts/loops/
```

Show the user what's available:
- `work` - Implements beads until none remain (beads-empty)
- `improve-plan` - Refines a plan until plateau (plateau)
- `refine-beads` - Improves beads until plateau (plateau)
- `idea-wizard` - Generates ideas for N iterations (fixed-n)
- Any custom loops they've created

## Step 2: Gather Requirements

Use AskUserQuestion to collect:

```json
{
  "questions": [
    {
      "question": "Which loop type do you want to run?",
      "header": "Loop Type",
      "options": [
        {"label": "work", "description": "Implement beads until all done"},
        {"label": "improve-plan", "description": "Refine a plan doc until plateau"},
        {"label": "refine-beads", "description": "Improve beads until plateau"},
        {"label": "idea-wizard", "description": "Generate ideas for N iterations"}
      ],
      "multiSelect": false
    }
  ]
}
```

If they choose "Other", ask what custom loop they want.

## Step 3: Get Session Name

Ask for a session name:

```json
{
  "questions": [{
    "question": "What should we call this session? (used for bead labels and progress files)",
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

## Step 4: Get Max Iterations

```json
{
  "questions": [{
    "question": "How many maximum iterations? (Recommended based on loop type)",
    "header": "Max Iterations",
    "options": [
      {"label": "5", "description": "Quick run - good for testing"},
      {"label": "25", "description": "Standard for work loops"},
      {"label": "50", "description": "Thorough - for larger tasks"},
      {"label": "Custom", "description": "I'll specify a number"}
    ],
    "multiSelect": false
  }]
}
```

**Defaults by loop type:**
- work: 25-50 (depends on task size)
- improve-plan: 5-10 (plateau typically hit around 3-5)
- refine-beads: 5-10 (plateau typically hit around 3-5)
- idea-wizard: 3-5 (fixed-n, specify exactly what you want)

## Step 5: Check for Conflicts

Check both tmux sessions AND lock files:

```bash
# Check if tmux session already exists
tmux has-session -t loop-{session-name} 2>/dev/null && echo "TMUX_EXISTS" || echo "NO_TMUX"

# Check if lock file exists
test -f .claude/locks/{session-name}.lock && echo "LOCKED" || echo "NO_LOCK"
```

**If TMUX_EXISTS**, use AskUserQuestion:
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

**If LOCKED but NO_TMUX** (stale lock), show lock details:
```bash
cat .claude/locks/{session-name}.lock | jq
```

Then ask:
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

## Step 6: Validate Prerequisites

```bash
# Check loop exists
test -f scripts/loops/{loop-type}/loop.yaml && echo "OK" || echo "MISSING"

# Check run script exists
test -f scripts/run.sh && echo "OK" || echo "MISSING"
```

If anything is missing, warn the user and stop.

## Step 7: Start the Session

```bash
# Get absolute path for working directory
PROJECT_PATH="$(pwd)"

# Start detached tmux session
tmux new-session -d -s "loop-{session-name}" -c "$PROJECT_PATH" \
  "./scripts/run.sh loop {loop-type} {session-name} {max-iterations}"
```

## Step 8: Verify Session Started

```bash
# Give it a moment to start
sleep 1

# Check if running
tmux has-session -t loop-{session-name} 2>/dev/null && echo "RUNNING" || echo "FAILED"
```

If FAILED, try to capture any error:
```bash
# Check if there's a pane to capture
tmux capture-pane -t loop-{session-name} -p 2>/dev/null || echo "Session failed to start"
```

## Step 9: Update State File

Read existing state, add new session:

```bash
# Ensure directory exists
mkdir -p .claude

# Read existing or create new
if [ -f .claude/loop-sessions.json ]; then
  EXISTING=$(cat .claude/loop-sessions.json)
else
  EXISTING='{"sessions":{}}'
fi

# Add new session using jq
echo "$EXISTING" | jq --arg name "loop-{session-name}" \
  --arg type "loop" \
  --arg loop_type "{loop-type}" \
  --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg path "$PROJECT_PATH" \
  --argjson max {max-iterations} \
  '.sessions[$name] = {
    "type": $type,
    "loop_type": $loop_type,
    "started_at": $started,
    "project_path": $path,
    "max_iterations": $max,
    "status": "running"
  }' > .claude/loop-sessions.json
```

## Step 10: Show Success Message

Display clear instructions:

```
Session started: loop-{session-name}

Loop type: {loop-type}
Max iterations: {max-iterations}

Quick commands:
  Monitor:  tmux capture-pane -t loop-{session-name} -p | tail -50
  Attach:   tmux attach -t loop-{session-name}
  Detach:   Ctrl+b, then d
  Kill:     tmux kill-session -t loop-{session-name}

Progress tracking:
  State:    cat .claude/loop-state-{session-name}.json
  Progress: cat .claude/loop-progress/progress-{session-name}.txt
  Beads:    bd ready --label=loop/{session-name}

The session is running in the background. Use 'Monitor' to check progress.
```

## Success Criteria

- [ ] Loop type selected and validated
- [ ] Session name collected (lowercase, hyphens)
- [ ] No naming conflicts (or resolved)
- [ ] Prerequisites verified
- [ ] tmux session started successfully
- [ ] State file updated with session info
- [ ] User shown monitoring instructions
