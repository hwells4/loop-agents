---
name: ntm
description: Orchestrate multi-agent sessions with NTM (Named Tmux Manager). Spawn Claude, Codex, and Gemini agents in parallel tmux panes, broadcast prompts, monitor progress, and collect outputs. Use when coordinating multiple AI agents on a shared task.
---

<dependencies>

**Before proceeding, check that ntm is installed:**

```bash
command -v ntm && ntm --version
```

If ntm is not found, inform the user:

> **NTM not installed.** This skill requires the `ntm` CLI tool.
>
> Install it with:
> ```bash
> # Using Homebrew (macOS)
> brew install hwells4/tap/ntm
>
> # Or from source
> go install github.com/hwells4/ntm@latest
> ```
>
> After installing, run `/ntm` again.

**Also verify tmux is available:**

```bash
command -v tmux && tmux -V
```

If tmux is missing:

> **tmux not installed.** NTM requires tmux to manage agent sessions.
>
> Install it with:
> ```bash
> # macOS
> brew install tmux
>
> # Ubuntu/Debian
> sudo apt install tmux
> ```

**Do not proceed with the skill until both dependencies are confirmed.**

</dependencies>

<essential_principles>

NTM transforms tmux into a multi-agent command center. Key concepts:

**Pane naming:** `{session}__{agent}_{number}` (e.g., `myproject__cc_1`, `myproject__cod_2`)
- `cc` = Claude Code
- `cod` = Codex
- `gmi` = Gemini

**Session lifecycle:**
1. `spawn` creates session + launches agents
2. `send` broadcasts prompts to agents
3. `activity`/`dashboard` monitors progress
4. `copy`/`save` collects outputs
5. `kill` terminates session

**Broadcasting:** Send to specific agent types or all:
- `--cc` targets Claude agents only
- `--cod` targets Codex agents only
- `--gmi` targets Gemini agents only
- `--all` targets every agent

**Robot mode:** For automation, use `--robot-*` flags to get machine-readable JSON output instead of TUI.

</essential_principles>

<intake>
What would you like to do?

1. Spawn a multi-agent session
2. Send prompts to agents
3. Monitor agent progress
4. Collect agent outputs
5. Manage session (add agents, checkpoint, kill)
6. Coordinate agents with Agent Mail (file reservations, messaging)
7. Something else

**Wait for response before proceeding.**
</intake>

<routing>
| Response | Workflow |
|----------|----------|
| 1, "spawn", "create", "start", "launch" | `workflows/spawn-session.md` |
| 2, "send", "prompt", "broadcast", "instruct" | `workflows/send-prompts.md` |
| 3, "monitor", "watch", "dashboard", "activity", "status" | `workflows/monitor-agents.md` |
| 4, "copy", "save", "output", "extract", "collect" | `workflows/collect-outputs.md` |
| 5, "add", "kill", "checkpoint", "manage" | `workflows/manage-session.md` |
| 6, "agent-mail", "coordinate", "reservation", "messaging", "conflict" | `workflows/coordinate-with-agent-mail.md` |
| 7, other | Clarify, then select workflow or read references |

**After reading the workflow, follow it exactly.**
</routing>

<quick_reference>

**Spawn session:**
```bash
ntm spawn {session} --cc=3 --cod=2 --gmi=1
```

**Send prompts:**
```bash
ntm send {session} --all "implement the feature"
ntm send {session} --cc "analyze the code"
ntm send {session} --cod "write tests"
```

**Monitor:**
```bash
ntm dashboard {session}     # Visual TUI
ntm activity {session} -w   # Real-time activity
ntm status {session}        # Agent counts
```

**Collect outputs:**
```bash
ntm copy {session} --all              # All to clipboard
ntm save {session} -o ~/logs          # All to files
ntm extract {session} --code --copy   # Code blocks only
```

**Manage:**
```bash
ntm add {session} --cc=2              # Add 2 more Claude agents
ntm interrupt {session}               # Ctrl+C all agents
ntm checkpoint save {session} -m "before refactor"
ntm kill {session} -f                 # Terminate
```

</quick_reference>

<robot_mode>

For automation/scripting, use robot mode for JSON output:

```bash
ntm --robot-status              # All sessions + agent states
ntm --robot-context={session}   # Context window usage per agent
ntm --robot-snapshot            # Complete unified state
ntm --robot-tail={session}      # Recent pane output
ntm --robot-files={session}     # File changes with attribution
ntm --robot-health              # Health status
ntm --robot-send={session} --msg="prompt" --type=claude
```

Parse with `jq` for specific fields:
```bash
ntm --robot-status | jq '.sessions[].agents | length'
```

</robot_mode>

<reference_index>

All in `references/`:

**Commands:** commands.md (complete command reference)
**Configuration:** configuration.md (config file, env vars)
**Patterns:** patterns.md (common workflows, best practices)
**Agent Mail:** agent-mail.md (MCP tools, file reservations, messaging)
**Multi-Phase:** multi-phase-workflows.md (planning → implementation → review → integration)
**Troubleshooting:** troubleshooting.md (common issues, solutions)

</reference_index>

<workflows_index>

| Workflow | Purpose |
|----------|---------|
| spawn-session.md | Create multi-agent sessions with specific agent counts |
| send-prompts.md | Broadcast prompts to agents by type or all |
| monitor-agents.md | Watch activity, use dashboard, check health |
| collect-outputs.md | Copy, save, extract outputs from agents |
| manage-session.md | Add agents, checkpoint, interrupt, kill sessions |
| coordinate-with-agent-mail.md | Set up agent-mail, register agents, file reservations, messaging |

</workflows_index>

<success_criteria>

NTM operations succeed when:
- Sessions spawn with correct agent counts
- Prompts reach intended agents
- Outputs are captured completely
- Sessions terminate cleanly
- Robot mode returns valid JSON for automation

</success_criteria>
