# Loop Agents

A Claude Code plugin for autonomous multi-task execution.

## What it is

Loop agents break work into discrete tasks, then execute them one by one in a while loop. Each task runs in a fresh Claude instance.

This solves context degradation. A normal Claude session accumulates context until quality drops. A loop agent resets context each iteration, so it can run for hours.

## How it works

1. You describe the work (a feature, a refactor, a build)
2. An orchestrator breaks it into tasks (10, 20, 50)
3. A while loop picks up each task, spawns a fresh Claude instance
4. Quality checks run between iterations
5. Progress accumulates in a file that persists across iterations

## Requirements

- **beads** - Task management CLI. Install from [github.com/hwells4/beads](https://github.com/hwells4/beads)
- **tmux** - Terminal multiplexer (`brew install tmux`)
- **Claude Code** - Anthropic's CLI

## Installation

Copy `.claude/` and `scripts/` to your project, or symlink them.

```bash
# Option 1: Copy
cp -r loop-agents/.claude your-project/
cp -r loop-agents/scripts your-project/

# Option 2: Symlink (if you want updates)
ln -s /path/to/loop-agents/.claude your-project/.claude
ln -s /path/to/loop-agents/scripts your-project/scripts
```

## Usage

```bash
# 1. Create a plan
/prd

# 2. Break it into tasks
/generate-stories

# 3. Run the loop
/loop start
```

The `/loop` command manages tmux sessions:

```bash
/loop start     # Plan + start a loop
/loop list      # See running loops
/loop attach    # Watch a loop live
/loop status    # Quick health check
/loop kill      # Stop a loop
```

## Files

```
.claude/
  commands/loop.md          # /loop command
  hooks/loop-stop-gate.py   # Ensures tests pass before stopping
  settings.json             # Hook configuration
  skills/
    generate-prd/           # Creates planning documents
    generate-stories/       # Breaks plans into tasks
    run-loop/               # Manages tmux sessions

scripts/loop/
  loop.sh                   # Main while loop
  loop-once.sh              # Test single iteration
  prompt.md                 # Instructions for each iteration
```

## Limitations

Loops run on your machine. If your computer sleeps, they pause. This isn't remote execution.
