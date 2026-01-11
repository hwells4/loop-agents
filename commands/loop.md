---
description: Orchestrate and manage autonomous loop agents
---

# /loop Command

**Loop orchestration:** Plan workflows, manage running loops, and get guidance on what to do next.

## Usage

```
/loop                    # Interactive: decide what to do
/loop status             # Check all running loops
/loop attach NAME        # Attach to a session
/loop kill NAME          # Stop a session
/loop plan               # Plan a new feature (PRD + beads)
```

---

## Available Loop Types

| Loop | Command | Stops When |
|------|---------|------------|
| **Work** | `/work` | All beads complete |
| **Refine** | `/refine` | 2 agents agree it's ready |
| **Ideate** | `/ideate` | Fixed iterations |

---

## Adaptive Guidance

**When user types `/loop` with no arguments:**

First, check the current state:
```bash
# Running loops
RUNNING=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^loop-" | wc -l | tr -d ' ')

# Ready beads
READY_BEADS=$(bd ready 2>/dev/null | grep -c "^" || echo "0")

# Recent plans
RECENT_PLANS=$(ls -t docs/plans/*.md 2>/dev/null | head -3)
```

Then offer contextual options:

**If loops are running:**
```yaml
question: "You have {N} loop(s) running. What would you like to do?"
header: "Loops"
options:
  - label: "Check status"
    description: "See progress of running loops"
  - label: "Attach to a loop"
    description: "Watch a loop live"
  - label: "Start something new"
    description: "Plan or launch another loop"
```

**If beads exist but no work loop:**
```yaml
question: "Found {N} ready beads. What's next?"
header: "Beads Ready"
options:
  - label: "Start work loop (Recommended)"
    description: "Launch /work to implement beads"
  - label: "Refine first"
    description: "Run /refine to improve beads before work"
  - label: "Review the plan"
    description: "Look at beads before deciding"
```

**If no beads and no recent plan:**
```yaml
question: "No beads or plans found. What would you like to do?"
header: "Getting Started"
options:
  - label: "Plan a new feature"
    description: "Create PRD and break into tasks"
  - label: "Generate ideas"
    description: "Brainstorm improvements with /ideate"
```

---

## Plan a New Feature

When user wants to plan:

1. **Generate PRD:**
```
Skill(skill="loop-agents:prd")
```
Creates: `docs/plans/{date}-{slug}-prd.md`

2. **Create beads from PRD:**
```
Skill(skill="loop-agents:create-tasks")
```
Creates beads tagged `loop/{session}`.

3. **Offer refinement:**
```yaml
question: "Plan created with {N} beads. Ready to work or refine first?"
header: "Next Step"
options:
  - label: "Launch work loop (Recommended)"
    description: "Start implementing now"
  - label: "Refine first"
    description: "Improve plan quality with /refine"
  - label: "Review beads"
    description: "Show me the beads first"
```

---

## Status and Management

### /loop status

Show comprehensive status:
```bash
echo "=== Running Loops ==="
tmux list-sessions 2>/dev/null | grep "^loop-" || echo "No loops running"

echo ""
echo "=== Beads Summary ==="
for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^loop-" | sed 's/^loop-//'); do
  total=$(bd list --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")
  ready=$(bd ready --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")
  echo "  $session: $ready/$total remaining"
done

echo ""
echo "=== Untagged Ready Beads ==="
bd ready 2>/dev/null | grep -v "loop/" | head -5 || echo "None"
```

### /loop attach NAME

```bash
tmux attach -t loop-{NAME}
```

Remind: `Ctrl+b d` to detach without stopping.

### /loop kill NAME

```bash
tmux kill-session -t loop-{NAME}
```

Confirm first: "This will stop the loop. Any bead in progress may be incomplete."

Note: The session lock is automatically released when the loop process ends.

---

## Building Pipelines

For complex workflows, use pipelines:

```bash
PLUGIN_DIR=".claude/loop-agents"

# Quick refine then work
$PLUGIN_DIR/scripts/pipelines/run.sh $PLUGIN_DIR/scripts/pipelines/quick-refine.yaml session-name
$PLUGIN_DIR/scripts/loops/run.sh work session-name 20

# Full quality pipeline
$PLUGIN_DIR/scripts/pipelines/run.sh $PLUGIN_DIR/scripts/pipelines/deep-refine.yaml session-name
$PLUGIN_DIR/scripts/loops/run.sh review session-name 9
$PLUGIN_DIR/scripts/loops/run.sh work session-name 30
```

### Available Pipelines

| Pipeline | Improve-Plan | Refine-Beads | Best For |
|----------|--------------|--------------|----------|
| `quick-refine` | 3 iterations | 3 iterations | Fast validation |
| `full-refine` | 5 iterations | 5 iterations | Standard workflow |
| `deep-refine` | 8 iterations | 8 iterations | Complex projects |

---

## Multi-Session Support

Run multiple loops simultaneously:
```bash
# Different features in parallel
tmux new-session -d -s "loop-auth" ...
tmux new-session -d -s "loop-api" ...

# Each has separate beads, progress, and state
```

---

## Quick Reference

| Want to... | Command |
|------------|---------|
| Start new feature | `/loop plan` or `/loop-agents:prd` |
| Implement tasks | `/work` |
| Improve plans/beads | `/refine` |
| Generate ideas | `/ideate` |
| Check running loops | `/loop status` |
| Watch a loop | `/loop attach NAME` |
| Stop a loop | `/loop kill NAME` |

---

## Session Locks

Sessions are protected by lock files to prevent running duplicate sessions with the same name.

**If you see "Session is already running":**
```bash
# Check if the session is actually running
tmux has-session -t loop-{NAME} && echo "running" || echo "not in tmux"

# View lock details
cat .claude/locks/{NAME}.lock | jq

# Check if the lock's PID is alive
ps -p $(jq -r .pid .claude/locks/{NAME}.lock)

# Force start (override existing lock)
./scripts/run.sh loop work {NAME} 25 --force

# Or clear a stale lock manually
rm .claude/locks/{NAME}.lock
```
