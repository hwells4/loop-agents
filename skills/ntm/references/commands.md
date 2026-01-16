<overview>
Complete NTM command reference. All commands, flags, and options for orchestrating multi-agent tmux sessions.
</overview>

<session_creation>

**ntm create**
Create empty tmux session without launching agents.
```bash
ntm create {session} [--panes=N]
```
- `--panes=N` - Number of empty panes (default: 1)

**ntm spawn**
Create session AND launch agents immediately.
```bash
ntm spawn {session} --cc=N --cod=N --gmi=N
```
- `--cc=N` - Number of Claude Code agents
- `--cod=N` - Number of Codex agents
- `--gmi=N` - Number of Gemini agents

Example:
```bash
ntm spawn myproject --cc=3 --cod=2 --gmi=1  # 6 total agents
```

**ntm quick**
Full project scaffold with git init, VSCode settings, and agents.
```bash
ntm quick {project} [--template=go|python|node|rust]
```

</session_creation>

<agent_management>

**ntm add**
Add more agents to existing session.
```bash
ntm add {session} --cc=N --cod=N --gmi=N
```

**ntm send**
Broadcast prompt to agents.
```bash
ntm send {session} [--cc|--cod|--gmi|--all] "prompt"
```
- `--cc` - Send to Claude agents only
- `--cod` - Send to Codex agents only
- `--gmi` - Send to Gemini agents only
- `--all` - Send to all agents (default)

**ntm interrupt**
Send Ctrl+C to all agent panes.
```bash
ntm interrupt {session}
```

</agent_management>

<navigation>

**ntm attach**
Reattach to detached session.
```bash
ntm attach {session}
```
Alias: `rnt`

**ntm list**
Show all tmux sessions.
```bash
ntm list
```
Alias: `lnt`

**ntm status**
Display detailed session status with agent counts.
```bash
ntm status {session}
```
Alias: `snt`

**ntm view**
Show tiled pane layout.
```bash
ntm view {session}
```
Alias: `vnt`

**ntm zoom**
Focus on specific pane.
```bash
ntm zoom {session} [pane-index]
```
Alias: `znt`

</navigation>

<monitoring>

**ntm dashboard**
Visual TUI dashboard with agent status cards.
```bash
ntm dashboard {session}
```
Alias: `dash` or `d`

Dashboard features:
- Color-coded agent cards
- Token velocity badges
- Live state indicators
- Number keys (1-9) for navigation
- `c` to check context
- `r` to refresh

**ntm activity**
Real-time agent activity states.
```bash
ntm activity {session} [--cc|--cod|--gmi] [-w] [--interval MS]
```
- `-w` - Watch mode (continuous)
- `--interval` - Refresh interval in ms

**ntm watch**
Stream agent output in real-time.
```bash
ntm watch {session} [--cc|--cod|--gmi] [--activity] [--tail N]
```

**ntm health**
Check agent health status.
```bash
ntm health {session} [--json]
```

**ntm grep**
Search across pane outputs.
```bash
ntm grep {pattern} {session} [-i] [-C N]
```
- `-i` - Case insensitive
- `-C N` - Context lines

</monitoring>

<output_capture>

**ntm copy**
Copy pane output to clipboard.
```bash
ntm copy {session[:pane]} [--all|--cc|--cod|--gmi] [-l lines] [--pattern REGEX] [--code] [--output FILE]
```
- `--all` - All pane outputs
- `--code` - Extract markdown code blocks only
- `--pattern` - Filter by regex
- `-l` - Number of lines
- `--output` - Write to file instead of clipboard

**ntm save**
Save outputs to timestamped files.
```bash
ntm save {session} [-o dir] [-l lines]
```

**ntm extract**
Extract code blocks from output.
```bash
ntm extract {session} [pane] [--lang=X] [--copy] [--apply]
```
- `--lang` - Filter by language
- `--copy` - Copy to clipboard
- `--apply` - Apply changes to files

**ntm diff**
Compare outputs between panes.
```bash
ntm diff {session} {pane1} {pane2} [--unified] [--code-only]
```

</output_capture>

<checkpoints>

**ntm checkpoint save**
Capture complete session state.
```bash
ntm checkpoint save {session} [-m "description"] [--scrollback=N]
```

**ntm checkpoint list**
List all checkpoints.
```bash
ntm checkpoint list {session} [--json]
```

**ntm checkpoint show**
Show checkpoint details.
```bash
ntm checkpoint show {session} {id} [--json]
```

**ntm checkpoint delete**
Delete checkpoint.
```bash
ntm checkpoint delete {session} {id} [-f]
```

</checkpoints>

<interactive>

**ntm palette**
Open fuzzy-searchable command palette.
```bash
ntm palette {session}
```
Alias: `ncp`

Palette features:
- Animated gradient banner
- Fuzzy search
- Pin favorites with Ctrl+P
- Number keys 1-9 for quick select
- `?` or F1 for help

**ntm tutorial**
Interactive onboarding.
```bash
ntm tutorial [--skip] [--slide=N]
```

</interactive>

<system>

**ntm deps**
Check dependencies.
```bash
ntm deps [-v]
```

**ntm bind**
Configure tmux keybinding for palette.
```bash
ntm bind [--key=F6] [--unbind] [--show]
```

**ntm kill**
Terminate session.
```bash
ntm kill {session} [-f]
```
Alias: `knt`

**ntm upgrade**
Self-update NTM.
```bash
ntm upgrade [--check] [--yes] [--force]
```

</system>

<robot_mode>

Machine-readable JSON output for automation:

```bash
ntm --robot-status              # Sessions and agent states
ntm --robot-context={session}   # Context window usage
ntm --robot-snapshot            # Unified state dump
ntm --robot-tail={session}      # Recent pane output
ntm --robot-inspect-pane={sess} # Detailed pane inspection
ntm --robot-files={session}     # File changes with attribution
ntm --robot-metrics={session}   # Session metrics
ntm --robot-health              # Health status
ntm --robot-history={session}   # Prompt history
ntm --robot-send={session} --msg="text" --type=claude
ntm --robot-ack={session} --ack-timeout=30s
ntm --robot-assign={session} --assign-strategy=balanced
```

</robot_mode>

<shell_aliases>

After `eval "$(ntm init zsh)"`:

| Alias | Command | Purpose |
|-------|---------|---------|
| `cc`, `cod`, `gmi` | - | Launch individual agent CLIs |
| `cnt` | create | Create session |
| `sat` | spawn | Spawn with agents |
| `qps` | quick | Quick project setup |
| `ant` | add | Add agents |
| `bp` | send | Broadcast prompt |
| `int` | interrupt | Interrupt all |
| `rnt` | attach | Reattach |
| `lnt` | list | List sessions |
| `snt` | status | Status |
| `vnt` | view | View layout |
| `znt` | zoom | Zoom pane |
| `dash`, `d` | dashboard | Dashboard |
| `cpnt` | copy | Copy output |
| `svnt` | save | Save outputs |
| `ncp` | palette | Command palette |
| `knt` | kill | Kill session |
| `cad` | deps | Check deps |

</shell_aliases>
