# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Loop Agents is a [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code. It runs autonomous, multi-iteration agent workflows in tmux sessions. Each iteration spawns a fresh Claude instance that reads accumulated progress to maintain context without degradation.

## Commands

```bash
# Run a loop directly
./scripts/run.sh loop work auth 25        # work loop, session "auth", max 25 iterations
./scripts/run.sh loop improve-plan my-session 5

# Run a pipeline (chains loops together)
./scripts/run.sh pipeline full-refine.yaml my-session

# List available loops/pipelines
./scripts/run.sh
```

Dependencies: `jq`, `claude`, `tmux`, `bd` (beads CLI)

## Architecture

```
scripts/
├── engine.sh                 # Unified orchestrator (loops + pipelines)
├── run.sh                    # Entry point wrapper
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # JSON iteration history
│   ├── progress.sh           # Accumulated context files
│   ├── resolve.sh            # Template variable resolution
│   ├── parse.sh              # Claude output parsing
│   ├── notify.sh             # Desktop notifications + logging
│   └── completions/          # Stopping strategies
│       ├── beads-empty.sh    # Stop when no beads remain
│       ├── plateau.sh        # Stop when 2 agents agree
│       ├── fixed-n.sh        # Stop after N iterations
│       └── all-items.sh      # Stop after processing items
├── loops/                    # Loop type definitions
│   ├── work/                 # Implementation (beads-empty)
│   ├── improve-plan/         # Plan refinement (plateau)
│   ├── refine-beads/         # Bead refinement (plateau)
│   └── idea-wizard/          # Ideation (fixed-n)
└── pipelines/                # Multi-stage workflows
    └── *.yaml

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

## Core Concepts

### Loops

A loop = prompt template + completion strategy. Each iteration:
1. Resolves template variables (`${SESSION}`, `${ITERATION}`, `${PROGRESS_FILE}`, etc.)
2. Executes Claude with resolved prompt
3. Parses output for structured fields
4. Updates state file with results
5. Checks completion condition → stop or continue

### State vs Progress Files

**State file** (`.claude/loop-state-{session}.json`): JSON tracking iteration history for completion checks
```json
{"session": "auth", "iteration": 5, "history": [{"plateau": false}, {"plateau": true}]}
```

**Progress file** (`.claude/loop-progress/progress-{session}.txt`): Markdown with accumulated learnings. Fresh Claude reads this each iteration to maintain context.

### Completion Strategies

| Strategy | Implementation | Used By |
|----------|----------------|---------|
| `beads-empty` | Checks `bd ready --label=loop/{session}` returns 0 | work loop |
| `plateau` | Requires 2 consecutive agents to output `PLATEAU: true` | improve-plan, refine-beads |
| `fixed-n` | Runs exactly N iterations | idea-wizard |
| `all-items` | Processes each item in a list | batch processing |

### Pipelines

Chain loops together. Each stage's outputs become `${INPUTS}` for the next:
```yaml
stages:
  - name: plan
    loop: improve-plan
    runs: 5
  - name: beads
    loop: refine-beads
    runs: 5
```

## Template Variables

| Variable | Description |
|----------|-------------|
| `${SESSION}` / `${SESSION_NAME}` | Session name |
| `${ITERATION}` | 1-based iteration number |
| `${INDEX}` | 0-based iteration index |
| `${PROGRESS}` / `${PROGRESS_FILE}` | Path to progress file |
| `${OUTPUT}` | Path to write output (pipelines) |
| `${INPUTS}` | Previous stage outputs (pipelines) |
| `${INPUTS.stage-name}` | Named stage outputs (pipelines) |

## Creating a New Loop

1. Create directory: `scripts/loops/{name}/`
2. Add `loop.yaml`:
```yaml
name: my-loop
description: What this loop does
completion: plateau      # beads-empty, plateau, fixed-n, all-items
delay: 3                 # seconds between iterations
min_iterations: 2        # for plateau: don't check before this
output_parse: plateau:PLATEAU reasoning:REASONING  # extract from output
```
3. Add `prompt.md` with template using variables above

## Key Patterns

**Fresh agent per iteration**: Avoids context degradation. Each Claude reads the progress file for accumulated context.

**Two-agent consensus** (plateau): Prevents single-agent blind spots. Both must independently confirm completion.

**Beads integration**: Work loop uses `bd` CLI to list/claim/close tasks. Beads are tagged with `loop/{session}`.

## Environment Variables

Loops export:
- `CLAUDE_LOOP_AGENT=1` - Always true inside a loop
- `CLAUDE_LOOP_SESSION` - Current session name
- `CLAUDE_LOOP_TYPE` - Current loop type
