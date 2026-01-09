# Loop Agents

A Claude Code plugin for autonomous multi-task execution.

## What it is

An iteration of the [Ralph Wiggum loop](https://ghuntley.com/ralph/) pattern - a while loop that lets AI agents manage context persistently across long-running tasks.

**What's different here:**
- **Claude Code is the orchestrator** - Just describe your work and Claude handles planning, task breakdown, and loop management
- **tmux sessions** - Loops run in the background; Claude can spin up several with their own tasks and dependencies without clogging your terminal
- **Attach/detach** - Claude can attach to running loops, monitor progress, or kill them - all from your normal session
- **Notifications** - Desktop alerts (macOS/Linux) when loops complete

## Installation

```bash
# Add the marketplace
/plugin marketplace add hwells4/loop-agents

# Install the plugin
/plugin install loop-agents@loop-agents-marketplace
```

## Dependencies

Before running `/loop`, Claude will check that these are installed:

- **[tmux](https://github.com/tmux/tmux)** - Terminal multiplexer for background execution
  ```bash
  brew install tmux        # macOS
  apt install tmux         # Linux
  ```

- **[beads](https://github.com/steveyegge/beads)** - Task management CLI for coding agents
  ```bash
  brew install steveyegge/tap/bd
  ```

## Usage

Run `/loop` to manage loops through Claude:

```bash
/loop              # Start the orchestrator - plan work and launch a loop
/loop start        # Start a loop (after planning)
/loop list         # See running loops
/loop attach       # Watch a loop live (Ctrl+b, d to detach)
/loop status       # Quick health check
/loop kill         # Stop a loop
```

Or just talk to Claude naturally:

```
"I want to add user authentication to this app"
"Check on my running loops"
"Attach to the auth loop"
```

## How it works

Run /loop and tell Claude what you're working on. It will:

1. Gather context about what you're building
2. Generate a PRD and breaks it into discrete tasks
3. Spin up a tmux session running a while loop
4. Each iteration: fresh Claude instance picks a task, implements it, commits, updates progress
5. Send a system notification when the full loop is complete

The loop runs in the background, seperate from your active claude code session. You can ask Claude to check on it, attach to watch live, or spin up more loops for parallel work. If Claude Code crashes during a run, your loop will still be active! Just ask claude to reconnect to it.

```
You describe work → Claude plans → Claude spawns tmux loop → Fresh Claude per task → You get notified
```

## Multi-Loop Support

Claude can manage multiple loops simultaneously. Each runs in its own tmux session with its own tasks and progress file.

Ask Claude to start a second feature while the first is running - they won't conflict.

## Notifications

When a loop completes or hits max iterations:
- **macOS**: Native notification center
- **Linux**: `notify-send` (install `libnotify` if missing)

Completion events are also logged to `.claude/loop-completions.json`.

## How Progress is Stored

Progress files are stored in your project (not the plugin):

```
your-project/
└── .claude/
    └── loop-progress/
        └── progress-{session-name}.txt
```

Each iteration appends learnings. Fresh Claude instances read this to maintain context without degradation.

## Limitations

- Tmux sessions are local, so if your computer sleeps, they pause. Use caffiene or antoher system to keep your computer running for async work.

## License

MIT
