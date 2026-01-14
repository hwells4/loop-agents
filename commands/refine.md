---
description: Iteratively refine plans and beads before implementation
---

# /refine

Runs refinement pipelines: multiple agents review and improve plans and beads. Planning tokens are cheaper than implementation tokens—catch issues early.

**Runtime:** ~2-3 min per iteration

## Usage

```
/refine              # Full refine (5+5 iterations)
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
