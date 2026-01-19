---
description: Orchestrate multi-agent tmux sessions with NTM
---

# /ntm

Manage multi-agent sessions using NTM (Named Tmux Manager). Spawn Claude, Codex, and Gemini agents in parallel tmux panes, broadcast prompts, monitor progress, and collect outputs.

## Usage

```
/ntm                         # Interactive - choose action
/ntm spawn                   # Create a new multi-agent session
/ntm send                    # Broadcast prompts to agents
/ntm monitor                 # Watch agent activity
/ntm collect                 # Gather agent outputs
/ntm manage                  # Add agents, checkpoint, kill
/ntm coordinate              # Agent Mail: file reservations, messaging
```

## Quick Start

**Spawn a session with 2 Claude + 2 Codex agents:**
```bash
ntm spawn myproject --cc=2 --cod=2
```

**Send a prompt to all agents:**
```bash
ntm send myproject --all "implement the user authentication feature"
```

**Send to specific agent types:**
```bash
ntm send myproject --cc "analyze the codebase structure"
ntm send myproject --cod "write comprehensive tests"
```

**Monitor activity:**
```bash
ntm dashboard myproject      # Visual TUI
ntm activity myproject -w    # Real-time stream
ntm status myproject         # Agent counts
```

**Collect outputs:**
```bash
ntm copy myproject --all              # All to clipboard
ntm save myproject -o ~/logs          # All to files
ntm extract myproject --code --copy   # Code blocks only
```

## Robot Mode (for automation)

Get machine-readable JSON output:
```bash
ntm --robot-status              # All sessions + agent states
ntm --robot-snapshot            # Complete unified state
ntm --robot-tail=myproject      # Recent pane output
ntm --robot-send=myproject --msg="prompt" --type=claude
```

## Session Lifecycle

1. `spawn` - Create session and launch agents
2. `send` - Broadcast prompts to agents
3. `dashboard`/`activity` - Monitor progress
4. `copy`/`save` - Collect outputs
5. `kill` - Terminate session

## Pane Naming

Panes are named `{session}__{agent}_{number}`:
- `cc` = Claude Code
- `cod` = Codex
- `gmi` = Gemini

Example: `myproject__cc_1`, `myproject__cod_2`

---

**Invoke the ntm skill for:** $ARGUMENTS
