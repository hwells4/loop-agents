---
description: Generate improvement ideas for code and architecture
---

# /ideate

Runs the idea-wizard pipeline: brainstorms 20-30 improvements across simplicity, performance, UX, reliability, and developer experience. Evaluates each by impact/effort/risk, winnows to top 5 per iteration. Output saved to `docs/ideas-{session}.md`.

**Runtime:** ~3 min per iteration

## When Invoked

Ask the user to configure ideation, then show a summary and confirm before launching.

### Step 1: Gather Configuration

Use AskUserQuestion:

```json
{
  "questions": [{
    "question": "How many ideation iterations?",
    "header": "Iterations",
    "options": [
      {"label": "1 (Quick)", "description": "~3 min, 5 top ideas"},
      {"label": "3 (Recommended)", "description": "~10 min, diverse perspectives"},
      {"label": "5 (Comprehensive)", "description": "~15 min, thorough exploration"}
    ],
    "multiSelect": false
  }]
}
```

Then ask for session name:

```json
{
  "questions": [{
    "question": "Session name for this ideation?",
    "header": "Session",
    "options": [
      {"label": "Derive from branch", "description": "Use current git branch name"},
      {"label": "ideas", "description": "Use 'ideas' as session name"},
      {"label": "Custom", "description": "I'll specify a name"}
    ],
    "multiSelect": false
  }]
}
```

### Step 2: Show Pre-Launch Summary and Confirm

```
## Pre-Launch Summary

Stage: idea-wizard
Session: {session}
Provider: claude (opus)
Iterations: {N}

What will happen:
  • Each iteration generates 20-30 raw ideas
  • Ideas scored by Impact/Effort/Risk
  • Top 5 ideas per iteration saved
  • Output: docs/ideas-{session}.md

Categories covered:
  • Simplicity - What to remove or simplify
  • Performance - Speed and efficiency gains
  • User Experience - Delight and usability
  • Reliability - Error handling, edge cases
  • Developer Experience - Maintainability, clarity

Estimated runtime: ~{N*3} minutes
```

```json
{
  "questions": [{
    "question": "Ready to start ideation?",
    "header": "Confirm",
    "options": [
      {"label": "Launch", "description": "Start generating ideas"},
      {"label": "Edit Config", "description": "Change iterations, provider, or focus area"},
      {"label": "Cancel", "description": "Don't start, return to conversation"}
    ],
    "multiSelect": false
  }]
}
```

**If "Launch":** Start the pipeline
**If "Edit Config":** Ask what to change (can add --context for focus area)
**If "Cancel":** Abort

### Step 3: Launch

```bash
./scripts/run.sh idea-wizard {session} {iterations}
```

## Usage (Direct Commands)

```
/ideate              # Interactive (recommended)
/ideate 3            # 3 iterations (~10 min, diverse ideas)
/ideate 5            # 5 iterations (~15 min, comprehensive)
```

## What It Produces

Each iteration generates 5 high-impact ideas covering:
- **Simplicity** - What to remove or simplify
- **Performance** - Speed and efficiency gains
- **User Experience** - Delight and usability
- **Reliability** - Error handling, edge cases
- **Developer Experience** - Maintainability, clarity

Ideas are scored (Impact 1-5, Effort 1-5, Risk 1-5) and ranked by ROI.

## Termination

**Fixed iterations** - runs exactly N times (default: 1). Each iteration reads previous output to avoid duplicates and push for fresh thinking.

## Advanced Options

Override provider, model, or inject context:

```bash
# Use Codex instead of Claude
./scripts/run.sh ideate my-session 3 --provider=codex

# Use specific model
./scripts/run.sh ideate my-session 3 --model=sonnet

# Focus ideation on specific area
./scripts/run.sh ideate my-session 2 --context="Focus on performance optimizations"

# Pass initial inputs
./scripts/run.sh ideate my-session 2 --input=docs/current-architecture.md
```

See CLAUDE.md for full list of providers, models, and options.

## After Ideation

- `/agent-pipelines:create-tasks` → Turn ideas into beads
- `/refine` → Incorporate ideas into existing plan
