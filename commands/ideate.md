---
description: Generate improvement ideas for code and architecture
---

# /ideate

Runs the idea-wizard pipeline: brainstorms 20-30 improvements across simplicity, performance, UX, reliability, and developer experience. Evaluates each by impact/effort/risk, winnows to top 5 per iteration. Output saved to `docs/ideas-{session}.md`.

**Runtime:** ~3 min per iteration

## Usage

```
/ideate              # 1 iteration (quick brainstorm)
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
