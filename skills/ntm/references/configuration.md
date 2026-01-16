<overview>
NTM configuration options: config file, environment variables, and shell integration.
</overview>

<installation>

**One-line install:**
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash
```

**Alternative methods:**
```bash
# Homebrew
brew install dicklesworthstone/tap/ntm

# Go install
go install github.com/Dicklesworthstone/ntm/cmd/ntm@latest

# Docker
docker pull ghcr.io/dicklesworthstone/ntm:latest
```

**Shell integration:**
```bash
# Zsh (add to ~/.zshrc)
eval "$(ntm init zsh)"

# Bash (add to ~/.bashrc)
eval "$(ntm init bash)"

# Fish (add to ~/.config/fish/config.fish)
ntm init fish | source
```

</installation>

<config_file>

Create `~/.config/ntm/config.toml`:

```toml
# Project base directory
projects_base = "~/Developer"

# Agent launch commands (customize flags as needed)
[agents]
claude = 'claude --dangerously-skip-permissions'
codex = "codex --dangerously-bypass-approvals-and-sandbox"
gemini = "gemini --yolo"

# Tmux settings
[tmux]
default_panes = 10
palette_key = "F6"

# Context window rotation (automatic compaction)
[context_rotation]
enabled = true
warning_threshold = 0.80   # Warn at 80% usage
rotate_threshold = 0.95    # Rotate at 95% usage

# Desktop notifications
[notifications]
enabled = true
events = ["agent.error", "agent.crashed", "agent.rate_limit"]

# Command hooks (run scripts before/after commands)
[hooks]
pre_spawn = ""
post_spawn = ""
pre_send = ""
post_send = ""
```

**Initialize default config:**
```bash
ntm config init
```

**View current config:**
```bash
ntm config show
```

</config_file>

<environment_variables>

| Variable | Default | Description |
|----------|---------|-------------|
| `NTM_PROJECTS_BASE` | `~/Developer` (macOS), `/data/projects` (Linux) | Base directory for projects |
| `NTM_THEME` | `auto` | Color theme: `auto`, `mocha`, `macchiato`, `nord`, `latte`, `plain` |
| `NTM_ICONS` | auto-detect | Icon set: `nerd`, `unicode`, `ascii` |
| `NTM_REDUCE_MOTION` | - | Set to disable animations |
| `NO_COLOR` | - | Disable all colors (standard) |

**Theme examples:**
```bash
export NTM_THEME=mocha       # Catppuccin Mocha (dark)
export NTM_THEME=latte       # Catppuccin Latte (light)
export NTM_THEME=nord        # Nord color scheme
export NTM_THEME=plain       # No colors
```

</environment_variables>

<tmux_keybinding>

Bind F6 (or custom key) to open command palette:

```bash
# Default binding (F6)
ntm bind

# Custom key
ntm bind --key=F5

# Show current binding
ntm bind --show

# Remove binding
ntm bind --unbind
```

Inside tmux, press the bound key to open the palette without leaving the session.

</tmux_keybinding>

<agent_profiles>

List and view agent profiles:

```bash
# List all profiles
ntm profiles list

# Filter by agent type
ntm profiles list --agent claude

# Filter by tag
ntm profiles list --tag refactoring

# Show profile details
ntm profiles show {profile-name}
```

Profiles contain pre-configured prompts and settings for common tasks.

</agent_profiles>

<dependencies>

Check required dependencies:
```bash
ntm deps -v
```

Required:
- `tmux` (session management)
- `go` 1.25+ (only if building from source)

Optional:
- Nerd Font (for icons in TUI)
- `jq` (for parsing robot mode JSON)

</dependencies>
