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

## Advanced Options

Override provider, model, or inject context:

```bash
# Use Codex for analysis
./scripts/run.sh robot-mode my-session 3 --provider=codex

# Use specific model
./scripts/run.sh robot-mode my-session 2 --model=opus

# Focus analysis on specific component
./scripts/run.sh robot-mode my-session 2 --context="Analyze CLI for JSON output opportunities"

# Pass specific code/docs to analyze
./scripts/run.sh robot-mode my-session 2 --input=src/cli.py
```

See CLAUDE.md for full list of providers, models, and options.

## After Analysis

Use the output to create beads for implementing the improvements:
- `/agent-pipelines:create-tasks` → Turn recommendations into work items
