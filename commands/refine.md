---
description: Iteratively refine plans and beads before implementation
---

# /refine Command

**Optimize planning before work:** Run refinement loops to improve plans and beads.

## Usage

```
/refine                  # Run full-refine pipeline (improve-plan → refine-beads)
/refine quick            # Quick pass (3 iterations each)
/refine deep             # Thorough pass (8 iterations each)
/refine plan             # Only refine plans
/refine beads            # Only refine beads
```

---

## Plugin Path

Scripts are at `.claude/loop-agents/scripts/`:
```
loop-engine/run.sh work|improve-plan|refine-beads [session] [max]
loop-engine/pipeline.sh quick-refine|full-refine|deep-refine [session]
```

---

## What This Does

**The pattern:** "Check your beads N times, implement once"

Planning tokens are cheaper than implementation tokens. Running multiple refinement iterations finds subtle issues that compound into significantly better execution.

### Pipelines

| Pipeline | improve-plan | refine-beads | Best for |
|----------|--------------|--------------|----------|
| `quick` | 3 iterations | 3 iterations | Fast validation |
| `full` | 5 iterations | 5 iterations | Standard workflow |
| `deep` | 8 iterations | 8 iterations | Complex projects |

### How It Works

1. **improve-plan loop** - Reviews plan documents in `docs/plans/`
   - Checks completeness, clarity, feasibility
   - Fixes gaps, ambiguities, inconsistencies
   - Stops when two agents agree it's ready

2. **refine-beads loop** - Reviews beads tagged for this session
   - Checks titles, descriptions, acceptance criteria
   - Ensures proper dependencies
   - Stops when two agents agree beads are implementable

---

## Execution

### Default: Full Pipeline

```yaml
question: "Run refine pipeline?"
header: "Refine"
options:
  - label: "Full refine (5+5)"
    description: "Standard: improve-plan then refine-beads"
  - label: "Quick refine (3+3)"
    description: "Fast pass, fewer iterations"
  - label: "Deep refine (8+8)"
    description: "Thorough, for complex projects"
  - label: "Plan only"
    description: "Just refine docs/plans/"
  - label: "Beads only"
    description: "Just refine beads"
```

### Ask for Session Name

```yaml
question: "Session name for this refinement?"
header: "Session"
options:
  - label: "refine-{date}"
    description: "Auto-generated name"
  - label: "Let me name it"
    description: "I'll type a custom name"
```

### Launch

**For pipelines:**
```bash
PLUGIN_DIR=".claude/loop-agents"
SESSION_NAME="{session}"

# In foreground (shows progress)
$PLUGIN_DIR/scripts/loop-engine/pipeline.sh full-refine $SESSION_NAME
```

**For single loops:**
```bash
# Plan only
$PLUGIN_DIR/scripts/loop-engine/run.sh improve-plan $SESSION_NAME 5

# Beads only
$PLUGIN_DIR/scripts/loop-engine/run.sh refine-beads $SESSION_NAME 5
```

### Show Progress

After launching, show:
```
Refine Pipeline: {pipeline}
Session: {session}

Progress file: .claude/loop-progress/progress-{session}.txt
State file: .claude/loop-state-{session}.json

Watch: tail -f .claude/loop-progress/progress-{session}.txt
```

---

## Intelligent Plateau Detection

Each iteration, the agent judges: `PLATEAU: true/false`

**Two consecutive agents must agree** before stopping. This prevents:
- Single-agent blind spots
- Premature stopping
- Missing important issues

If the second agent finds real problems, refinement continues.

---

## After Refinement

```yaml
question: "Refinement complete. What next?"
header: "Next"
options:
  - label: "Launch work loop"
    description: "Start implementing with /loop"
  - label: "Review changes"
    description: "Look at what was refined"
  - label: "Run another pass"
    description: "Go deeper on refinement"
```
