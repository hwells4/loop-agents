# CLAUDE.md

This file provides guidance to Claude Code when working with this plugin.

## Overview

Loop Agents is a Claude Code plugin that enables autonomous, multi-task execution through iterative loops. It solves context degradation in long-running AI sessions by spawning fresh Claude instances for each task while preserving accumulated context.

## Installation

```bash
# Install as Claude Code plugin
claude plugins install loop-agents
```

This installs to `.claude/loop-agents/` in your project.

## Dependencies

**Required:**
- `tmux` - Terminal multiplexer for background execution
- `beads (bd)` - Task management CLI (`brew install steveyegge/tap/bd`)
- `jq` - JSON processing (for state management)

## Project Conventions

When using this plugin, the following directories are created in YOUR project:

| Location | Purpose |
|----------|---------|
| `docs/plans/` | PRDs and planning documents |
| `.claude/loop-progress/` | Progress files (accumulated context per session) |
| `.claude/loop-state-*.json` | State files (iteration history) |
| `.claude/pipelines/` | Pipeline definitions (YAML) |
| `.claude/pipeline-runs/` | Pipeline execution outputs |
| `.beads/` | Beads database (created by `bd init`) |

## Commands

### Primary Commands
```bash
/loop-agents:loop              # Orchestration & management: decide what to do, check status
/loop-agents:work              # Run work loop: implement tasks from beads
/loop-agents:refine            # Run refinement loops: improve plans and beads
/loop-agents:ideate            # Generate improvement ideas (one-shot)
```

### Loop Management
```bash
/loop-agents:loop status       # Check all running loops
/loop-agents:loop attach NAME  # Watch live (Ctrl+b, d to detach)
/loop-agents:loop kill NAME    # Stop a session
/loop-agents:loop plan         # Plan a new feature (PRD → beads)
```

### Pipeline Commands
```bash
/loop-agents:pipeline          # Create and run multi-stage pipelines
/loop-agents:pipeline create   # Design a new pipeline
/loop-agents:pipeline run      # Execute an existing pipeline
/loop-agents:pipeline status   # Check running pipeline status
```

### Supporting Skills
```bash
/loop-agents:create-prd        # Generate product requirements document
/loop-agents:create-tasks      # Break PRD into beads
/loop-agents:build-loop        # Scaffold a new loop type
```

## Architecture

### Loop Engine

The core is a universal loop runner that executes any loop type:

```
.claude/loop-agents/scripts/
├── loop-engine/
│   ├── engine.sh          # Core loop runner
│   ├── run.sh             # ./run.sh <type> [session] [max]
│   ├── pipeline.sh        # ./pipeline.sh <pipeline> [session]
│   ├── lib/               # Shared utilities
│   └── completions/       # Stop conditions (plateau, beads-empty, etc.)
│
├── loops/                 # Loop type definitions
│   ├── work/              # Implementation from beads
│   ├── improve-plan/      # Plan refinement
│   ├── refine-beads/      # Bead refinement
│   └── idea-wizard/       # Idea generation
│
└── pipelines/             # Multi-loop sequences
    ├── quick-refine.yaml
    ├── full-refine.yaml
    └── deep-refine.yaml
```

### Loop Types

| Loop | Purpose | Stops When |
|------|---------|------------|
| `work` | Implement tasks from beads | All beads complete |
| `improve-plan` | Refine planning docs | Two agents agree it's ready |
| `refine-beads` | Improve bead quality | Two agents agree it's ready |
| `idea-wizard` | Generate ideas | Fixed iterations (usually 1) |

### Intelligent Plateau Detection

Loops don't stop based on arbitrary thresholds. Instead:
1. Each agent makes a judgment: `PLATEAU: true/false` with reasoning
2. **Two consecutive agents must agree** before stopping
3. If the second agent finds real issues, the counter resets

This prevents single-agent blind spots and premature stopping.

### Pipeline Orchestrator

The orchestrator coordinates multi-stage pipelines with fan-out/fan-in:

```
.claude/loop-agents/scripts/
├── orchestrator/
│   ├── run.sh             # Pipeline runner
│   ├── lib/               # Parsing, resolution, providers
│   ├── templates/         # Example pipelines
│   └── SCHEMA.md          # Pipeline schema reference
```

**Pipeline capabilities:**
- **Fan-out:** Run N times in parallel with different perspectives
- **Fan-in:** Aggregate results from previous stage
- **Completion strategies:** `plateau`, `beads-empty`, or fixed runs
- **Multi-provider:** Claude Code, Codex, Gemini

```yaml
# .claude/pipelines/code-review.yaml
name: code-review
stages:
  - name: review
    runs: 4
    parallel: true
    perspectives: [security, performance, clarity, testing]
    prompt: |
      Review from ${PERSPECTIVE} perspective.
      Write to ${OUTPUT}

  - name: synthesize
    runs: 1
    prompt: |
      Combine reviews: ${INPUTS.review}
      Write to ${OUTPUT}
```

### Legacy Pipelines

Chain multiple loops in sequence (simpler, for refinement):

```yaml
# pipelines/full-refine.yaml
steps:
  - loop: improve-plan
    max: 5
  - loop: refine-beads
    max: 5
```

## Workflow

### Typical Flow

```
1. /loop-agents:loop plan (or /loop-agents:create-prd + /loop-agents:create-tasks)
   ├── Gather context (adaptive questioning)
   ├── Generate PRD → docs/plans/{date}-{slug}-prd.md
   └── Create beads tagged loop/{session}

2. (Optional) /loop-agents:refine
   ├── improve-plan loop polishes the PRD
   └── refine-beads loop improves task definitions

3. /loop-agents:work
   ├── Launches work loop in tmux
   ├── Each iteration: pick bead → implement → test → commit → close
   ├── Progress accumulates in .claude/loop-progress/
   └── Stops when all beads complete
```

### Multi-Session Support

Run multiple loops simultaneously:
```bash
# Each session has separate beads and progress
loop-auth      → beads tagged loop/auth
loop-dashboard → beads tagged loop/dashboard
```

## Design Principles

1. **Fresh context per iteration** - Each Claude instance starts clean
2. **Accumulated context via files** - Progress file preserves learnings
3. **Agent judgment over thresholds** - Agents decide when work is done
4. **Two-agent confirmation** - No single agent can stop a loop
5. **Plugin operates on YOUR project** - Creates files in your project, not the plugin
