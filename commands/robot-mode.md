---
description: Plan agent-usability improvements for code and plans
---

# /robot-mode

Analyzes existing code, CLIs, or plans and identifies improvements that would make them more usable for coding agents. Outputs prioritized recommendations.

**Runtime:** ~2 min per iteration

## Usage

```
/robot-mode          # 3 iterations (default)
/robot-mode 2        # 2 iterations (quick pass)
```

## What It Produces

Each iteration identifies 5 agent-usability improvements covering:
- Token efficiency (verbose → compact)
- Machine-readable output (prose → JSON/structured)
- CLI gaps (UI-only → scriptable)
- Error handling (human messages → parseable errors)
- Documentation (walls of text → scannable reference)

## Termination

**Fixed iterations** - runs exactly N times (default: 3). Each iteration reads previous output to analyze different areas.

## After Analysis

Use the output to create beads for implementing the improvements:
- `/agent-pipelines:create-tasks` → Turn recommendations into work items
