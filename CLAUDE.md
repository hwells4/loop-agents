# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Loop Agents is a Claude Code plugin that enables autonomous, multi-task execution by implementing a "while loop" pattern. It solves context degradation in long-running AI sessions by spawning fresh Claude instances for each task while preserving accumulated context through a persistent progress file.

## Architecture

### Core Loop Pattern
```
PRD → Stories/Beads → tmux session → Fresh Claude per iteration → Progress file accumulates context
```

Each iteration:
1. Reads progress file for accumulated context
2. Picks next available bead (`bd ready --label=loop/{session}`)
3. Implements and verifies (tests must pass)
4. Commits with detailed message
5. Closes bead and appends results to progress file
6. Fresh context prevents degradation over hours of execution

### Key Components

**Commands (`commands/`)** - User-facing orchestration
- `loop.md` - Main `/loop` command that handles the entire workflow: context gathering, PRD generation, story creation, and loop launch

**Scripts (`scripts/`)** - Execution engine
- `loop.sh` - Main loop runner (default 25 iterations). Sets `CLAUDE_LOOP_AGENT=1` to activate hooks
- `loop-once.sh` - Single iteration test mode
- `prompt.md` - Instructions piped to Claude each iteration

**Skills (`skills/`)** - Specialized capabilities
- `loops/` - tmux session management (start, monitor, attach, kill, cleanup)
- `create-prd/` - Product requirements with adaptive questioning (uses AskUserQuestion)
- `create-tasks/` - Breaks PRD into verifiable beads with acceptance criteria

**Hooks (`hooks/`)** - Safety and awareness
- `session-init.sh` - Shows running loops and checks dependencies on session start
- `loop-stop-gate.py` - Prevents exit with uncommitted changes when inside loop (only when `CLAUDE_LOOP_AGENT=1`)

### State Files

| File | Purpose |
|------|---------|
| `.claude/loop-progress/progress-{session}.txt` | Accumulated context across iterations (patterns, changes, learnings) |
| `.claude/loop-sessions.json` | Active session metadata (started_at, status, max_iterations) |
| `.claude/loop-completions.json` | Completion event log |

### Multi-Session Support

Multiple loops run simultaneously with separate beads and progress files:
```
loop-auth → tasks tagged loop/auth
loop-dashboard → tasks tagged loop/dashboard
```

## Dependencies

**Required:**
- `tmux` - Terminal multiplexer for background execution
- `beads (bd)` - Task management CLI (brew install steveyegge/tap/bd)

## Commands

Run a complete adaptive workflow:
```bash
/loop-agents:loop              # Full workflow: context → PRD → stories → launch
```

Individual skills:
```bash
/loop-agents:prd               # Generate product requirements
/loop-agents:create-tasks  # Break PRD into beads
/loop-agents:loop start        # Launch tmux session
/loop-agents:loop status       # Check progress
/loop-agents:loop attach       # Watch live (Ctrl+b, d to detach)
/loop-agents:loop kill         # Stop session
```

Test mode (single iteration):
```bash
./scripts/loop-once.sh {session-name}
```

## Design Principles

1. **Fresh context per iteration** - Each Claude instance starts clean, reads progress file for context
2. **Adaptive questioning** - PRD skill uses AskUserQuestion with follow-ups based on answers, not checklists
3. **Agent judgment** - Agent picks logical next task; dependencies added only when strictly required
4. **Safety gates** - Tests must pass before commit; stop gate prevents incomplete work
5. **Append-only progress** - Never overwrite progress file; always append new learnings
