---
description: Run a traditional Ralph loop on a set of tasks. Uses beads for task management.
---

# /ralph

A basic [Ralph loop](https://ghuntley.com/ralph/) implementation. Spawns a fresh Claude agent in tmux that works through your task queue (beads) until empty.

**Core idea:** Fresh agent per iteration prevents context degradation. Each agent reads accumulated progress, does one task, writes what it learned, exits. Repeat.

## Usage

```
/ralph                # Start loop (auto-detects session)
/ralph auth           # Work on beads labeled pipeline/auth
/ralph status         # Check running loops
/ralph attach NAME    # Watch live (Ctrl+b d to detach)
/ralph kill NAME      # Stop a loop
```

## How It Works

Runs in tmux (`pipeline-{session}`). Each iteration:
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
tmux attach -t pipeline-{session}     # Watch live
bd ready --label=pipeline/{session}   # Remaining tasks
```
