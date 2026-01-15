---
description: Iteratively refine plans and beads before implementation
---

# /refine

Runs refinement pipelines: multiple agents review and improve plans and beads. Planning tokens are cheaper than implementation tokens—catch issues early.

**Runtime:** ~2-3 min per iteration

## When Invoked

Ask the user to configure the refinement, then show a summary and confirm before launching.

### Step 1: Gather Configuration

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "What type of refinement?",
    "header": "Type",
    "options": [
      {"label": "Full (Recommended)", "description": "5+5 iterations - balanced thoroughness"},
      {"label": "Quick", "description": "3+3 iterations - fast validation"},
      {"label": "Deep", "description": "8+8 iterations - comprehensive review"}
    ],
    "multiSelect": false
  }]
}
```

Then ask for session name:

```json
{
  "questions": [{
    "question": "Session name?",
    "header": "Session",
    "options": [
      {"label": "Derive from branch", "description": "Use current git branch name"},
      {"label": "Custom", "description": "I'll specify a name"}
    ],
    "multiSelect": false
  }]
}
```

### Step 2: Check Prerequisites

```bash
# Check for plan files
ls docs/plans/*.md 2>/dev/null | head -5

# Check for beads
bd ready 2>/dev/null | head -5
```

### Step 3: Show Pre-Launch Summary and Confirm

```
## Pre-Launch Summary

Pipeline: {type}-refine.yaml
Session: {session}
Provider: claude (opus)

Stages:
  1. improve-plan ({N} iterations) - Reviews docs/plans/
  2. refine-tasks ({N} iterations) - Reviews beads

Termination: Two-agent consensus per stage
Plans found: {count} files in docs/plans/
Beads found: {count} ready beads

Estimated runtime: ~{N*2} minutes
```

```json
{
  "questions": [{
    "question": "Ready to launch this refinement pipeline?",
    "header": "Confirm",
    "options": [
      {"label": "Launch", "description": "Start the refinement now"},
      {"label": "Edit Config", "description": "Change provider, model, or add context"},
      {"label": "Cancel", "description": "Don't start, return to conversation"}
    ],
    "multiSelect": false
  }]
}
```

**If "Launch":** Start the pipeline
**If "Edit Config":** Ask what to change
**If "Cancel":** Abort

### Step 4: Launch

```bash
./scripts/run.sh pipeline {type}-refine.yaml {session}
```

## Usage (Direct Commands)

```
/refine              # Interactive (recommended)
/refine quick        # Quick pass (3+3 iterations)
/refine deep         # Thorough pass (8+8 iterations)
/refine plan         # Only refine docs/plans/
/refine beads        # Only refine beads
/refine status       # Check running refinement loops
```

## Two-Stage Pipeline

1. **improve-plan** - Reviews documents in `docs/plans/`
2. **refine-tasks** - Reviews beads for the session

| Pipeline | improve-plan | refine-tasks | Best for |
|----------|--------------|--------------|----------|
| `quick`  | 3 iterations | 3 iterations | Fast validation |
| `full`   | 5 iterations | 5 iterations | Standard workflow |
| `deep`   | 8 iterations | 8 iterations | Complex projects |

## Termination

**Two-agent consensus** - stops when 2 consecutive agents agree work is done. Each agent judges `decision: stop` or `decision: continue`. If the second agent finds real issues, counter resets.

This prevents:
- Single-agent blind spots
- Premature stopping
- Missing subtle issues

## After Refinement

- `/work` → Start implementing refined beads
- `/refine` again → Go deeper if needed

## Advanced Options

Override provider, model, context, and pass initial inputs:

### Provider and Model

```bash
# Use Codex for refinement
./scripts/run.sh pipeline full-refine.yaml my-session --provider=codex

# Specific model
./scripts/run.sh pipeline quick-refine.yaml my-session --model=opus
```

### Context Injection

```bash
# Focus refinement on specific areas
./scripts/run.sh pipeline full-refine.yaml my-session \
  --context="Focus on security and error handling"
```

### Initial Inputs

Pass specific plan files instead of relying on `docs/plans/` discovery:

```bash
# Single plan
./scripts/run.sh pipeline full-refine.yaml my-session --input docs/plans/auth-plan.md

# Multiple plans
./scripts/run.sh pipeline full-refine.yaml my-session \
  --input docs/plans/auth-plan.md \
  --input docs/architecture.md
```

Stages read inputs via `context.json`:
```bash
# From prompt.md
jq -r '.inputs.from_initial[]' ${CTX} | xargs cat
```
