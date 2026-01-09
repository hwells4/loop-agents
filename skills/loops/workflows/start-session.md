# Workflow: Start a New Loop Session

<required_reading>
Read `references/state-management.md` before proceeding.
</required_reading>

<process>

## Step 1: Validate Prerequisites

Check that the project has required files:
```bash
ls .claude/loop-agents/scripts/loop.sh .claude/loop-agents/scripts/prompt.md 2>/dev/null || echo "MISSING"
```

If missing, warn the user:
- `loop.sh` - The loop runner script
- `prompt.md` - Instructions for the agent

## Step 2: Choose Session Name

Ask for or generate a name:
- Must be lowercase with hyphens
- Prefix with `loop-`
- Example: `loop-auth-refactor`, `loop-docs-update`

## Step 3: Check for Conflicts

```bash
tmux has-session -t loop-NAME 2>/dev/null && echo "EXISTS"
```

If session exists, offer:
1. Attach to existing session
2. Kill and restart
3. Choose different name

## Step 4: Start the Session

```bash
# Get absolute path
PROJECT_PATH="$(pwd)"

# Extract session name without 'loop-' prefix for beads tag
SESSION_TAG="${NAME}"  # e.g., "auth-refactor" from "loop-auth-refactor"

# Start detached session with session name for beads
tmux new-session -d -s "loop-NAME" -c "$PROJECT_PATH" ".claude/loop-agents/scripts/loop.sh 50 $SESSION_TAG"
```

The session name is passed to `loop.sh` so beads are tagged `loop/{session-tag}`.

## Step 5: Update State File

Create or update `.claude/loop-sessions.json`:
```bash
# Ensure directory exists
mkdir -p .claude

# Add session to state
cat > .claude/loop-sessions.json << 'EOF'
{
  "sessions": {
    "loop-NAME": {
      "started_at": "TIMESTAMP",
      "project_path": "PROJECT_PATH",
      "max_iterations": 50,
      "status": "running"
    }
  }
}
EOF
```

## Step 6: Verify Session Started

```bash
tmux has-session -t loop-NAME 2>/dev/null && echo "✅ Session started"
```

## Step 7: Show Status and Instructions

Display:
```
╔══════════════════════════════════════════════════════════╗
║  🚀 Loop session started: loop-NAME                       ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Monitor:  tmux capture-pane -t loop-NAME -p | tail -50  ║
║  Attach:   tmux attach -t loop-NAME                      ║
║  Detach:   Ctrl+b, then d                                ║
║  Kill:     tmux kill-session -t loop-NAME                ║
║                                                          ║
║  Beads:    bd ready --label=loop/SESSION_TAG               ║
║  Progress: cat .claude/loop-progress/progress-SESSION_TAG.txt ║
║                                                          ║
║  ⚠️  Remember to check on this session!                   ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
```

</process>

<success_criteria>
- [ ] Prerequisites validated
- [ ] No naming conflict
- [ ] Session running in tmux
- [ ] State file updated
- [ ] User shown monitoring instructions
</success_criteria>
