---
description: Run a traditional Ralph loop on a set of tasks. Uses beads for task management.
---

# /work

A basic [Ralph loop](https://ghuntley.com/ralph/) implementation. Spawns a fresh Claude agent in tmux that works through your task queue (beads) until empty.

**Core idea:** Fresh agent per iteration prevents context degradation. Each agent reads accumulated progress, does one task, writes what it learned, exits. Repeat.

## Usage

```
/work                # Start loop (auto-detects session)
/work auth           # Work on beads labeled loop/auth
/work status         # Check running loops
/work attach NAME    # Watch live (Ctrl+b d to detach)
/work kill NAME      # Stop a loop
```

## How It Works

Runs in tmux (`loop-{session}`). Each iteration:
1. Fresh Claude spawns
2. Reads progress file (accumulated context)
3. Picks next bead from queue
4. Implements, tests, commits
5. Closes bead, writes learnings
6. Exits

Repeats until queue empty.

## Termination

**Fixed iterations** - runs exactly N times (you specify max). Traditional Ralph behavior.

## Monitoring

```bash
tmux attach -t loop-{session}     # Watch live
bd ready --label=loop/{session}   # Remaining tasks
```
