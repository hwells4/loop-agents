<overview>
Common NTM issues and solutions.
</overview>

<installation_issues>

**"ntm: command not found"**
```bash
# Check if binary exists
which ntm

# If not, reinstall
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash

# Add to PATH if needed
export PATH="$PATH:$HOME/.local/bin"
```

**Shell aliases not working**
```bash
# Re-run init for your shell
eval "$(ntm init zsh)"   # or bash/fish

# Add to shell rc file permanently
echo 'eval "$(ntm init zsh)"' >> ~/.zshrc
source ~/.zshrc
```

**Missing dependencies**
```bash
ntm deps -v

# Install tmux if missing
# macOS
brew install tmux

# Ubuntu/Debian
sudo apt install tmux
```

</installation_issues>

<session_issues>

**"Session already exists"**
```bash
# List existing sessions
ntm list

# Kill the existing session
ntm kill {session} -f

# Or use a different name
ntm spawn new-session-name --cc=3
```

**"Cannot attach to session"**
```bash
# Check if session exists
tmux list-sessions

# If detached, reattach
ntm attach {session}

# If tmux server not running
tmux new-session -d -s temp && tmux kill-session -t temp
ntm spawn {session} --cc=3
```

**Panes not responding**
```bash
# Interrupt all panes
ntm interrupt {session}

# Check activity
ntm activity {session}

# Force kill if truly stuck
ntm kill {session} -f
```

</session_issues>

<agent_issues>

**Agent not starting**
```bash
# Check agent command
ntm config show | grep agents

# Verify agent CLI is installed
which claude
which codex
which gemini

# Test agent manually
claude --version
```

**Agent hitting rate limits**
```bash
# Check health
ntm health {session}

# Look for rate_limit state
ntm activity {session}

# Solution: Reduce agent count or add delays between prompts
```

**Agent context window full**
```bash
# Check context usage
ntm --robot-context={session}

# Enable auto-rotation in config
[context_rotation]
enabled = true
rotate_threshold = 0.95

# Manually trigger rotation (in agent's pane)
# Send: /compact
```

**Wrong agents receiving prompts**
```bash
# Specify agent type explicitly
ntm send {session} --cc "prompt"  # Only Claude
ntm send {session} --cod "prompt" # Only Codex

# Check which panes exist
ntm status {session}
```

</agent_issues>

<output_issues>

**Copy to clipboard not working**
```bash
# Check clipboard tool
# macOS: pbcopy should be available
# Linux: install xclip or xsel

# Workaround: write to file instead
ntm copy {session} --all --output /tmp/output.txt
```

**Outputs empty or truncated**
```bash
# Increase line count
ntm copy {session} --all -l 5000

# Save full scrollback
ntm save {session} -o ~/logs --scrollback=10000
```

**Code extraction failing**
```bash
# Check output format
ntm copy {session} --all

# Agents must use markdown code blocks
# If not, extract manually with regex
ntm copy {session} --pattern '```[\s\S]*?```'
```

</output_issues>

<performance_issues>

**Dashboard laggy**
```bash
# Reduce refresh rate
# Or use simpler monitoring
ntm activity {session}

# Disable animations
export NTM_REDUCE_MOTION=1
ntm dashboard {session}
```

**High CPU usage**
```bash
# Check agent count
ntm status {session}

# Reduce if too many
ntm kill {session} -f
ntm spawn {session} --cc=2 --cod=1  # Fewer agents
```

**Slow prompt delivery**
```bash
# Check for blocked panes
ntm activity {session}

# If agents are "thinking", wait
# If stuck, interrupt and resend
ntm interrupt {session}
ntm send {session} --all "prompt"
```

</performance_issues>

<robot_mode_issues>

**JSON parse errors**
```bash
# Validate JSON output
ntm --robot-status | jq .

# If invalid, check for error messages
ntm --robot-status 2>&1 | head -20
```

**Robot commands hanging**
```bash
# Add timeout
timeout 30 ntm --robot-status

# Check if session exists
ntm list
```

</robot_mode_issues>

<recovery>

**Session crashed mid-work**
```bash
# Check for checkpoints
ntm checkpoint list {session}

# If checkpoint exists, review state
ntm checkpoint show {session} {checkpoint-id}

# Start new session and continue manually
ntm spawn {session}-recovery --cc=3
```

**Lost outputs**
```bash
# Check if session still exists
tmux list-sessions

# If exists, save immediately
ntm save {session} -o ~/recovery/

# Check tmux scrollback
tmux capture-pane -t {session}:0 -p > pane0.txt
```

**Clean slate**
```bash
# Kill all NTM sessions
tmux list-sessions | grep -E '^[a-z]' | cut -d: -f1 | xargs -I{} tmux kill-session -t {}

# Clear config and restart
rm -rf ~/.config/ntm/
ntm config init
```

</recovery>
