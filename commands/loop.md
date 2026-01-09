---
description: Plan, launch, and monitor autonomous loop agents
---

# /loop Command

**Full workflow:** Gather context → Generate PRD → Create tasks → Launch autonomous work loop

## Usage

```
/loop                    # Full adaptive flow
/loop status             # Check running loops
/loop attach NAME        # Attach to a session
/loop kill NAME          # Stop a session
```

---

## Plugin Path

The plugin is installed at `.claude/loop-agents/`. Scripts are at:
```
.claude/loop-agents/scripts/loop-engine/run.sh
.claude/loop-agents/scripts/loop-engine/pipeline.sh
```

---

## ADAPTIVE EXECUTION

**Key principle:** Be intelligent about what's needed. Skip phases that aren't necessary.

### Phase 1: Gather Context

**If invoked with no context** (user just typed `/loop`):

Use `AskUserQuestion`:
```yaml
question: "What do you want to build?"
header: "Goal"
options:
  - label: "Build a new feature"
    description: "Add new functionality"
  - label: "Execute existing plan"
    description: "I have a PRD or beads ready"
  - label: "Improve/refactor code"
    description: "Work on existing code"
```

**If user has existing beads:**
```bash
bd ready 2>/dev/null | head -5
```

If beads exist, ask if they want to use them or start fresh.

### Phase 2: Generate PRD (if needed)

If no PRD exists and user wants to build something new:
```
Skill(skill="loop-agents:prd")
```

This creates: `docs/plans/{date}-{slug}-prd.md`

**Skip if:**
- User said "Execute existing plan"
- PRD already exists at `docs/plans/`
- User has beads ready

### Phase 3: Generate Beads (if needed)

If PRD exists but no beads:
```
Skill(skill="loop-agents:create-tasks")
```

This creates beads tagged `loop/{session-name}`.

**Skip if:**
- Beads already exist for this session
- User pointed to existing beads

### Phase 4: Confirm and Launch

**Calculate suggested iterations:**
- Formula: `(number of beads * 1.5) + 3` rounded up
- 5 beads → ~11 iterations
- 10 beads → ~18 iterations

Use `AskUserQuestion`:
```yaml
question: "Ready to launch loop '{session-name}' with {N} beads?"
header: "Launch"
options:
  - label: "Yes, start ({suggested} iterations)"
    description: "Launch in background"
  - label: "Test one iteration first"
    description: "Run once to verify setup"
  - label: "Adjust iterations"
    description: "I want more or fewer"
```

### Phase 5: Launch in tmux

```bash
SESSION_NAME="{session-name}"
ITERATIONS="{iterations}"
PLUGIN_DIR=".claude/loop-agents"

tmux new-session -d -s "loop-$SESSION_NAME" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/loop-engine/run.sh work $SESSION_NAME $ITERATIONS"
```

**Show confirmation:**
```
╔════════════════════════════════════════════════════════════╗
║  Loop Launched: loop-{session-name}                        ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  Running autonomously ({iterations} iterations max)        ║
║                                                            ║
║  Monitor:                                                  ║
║    bd ready --label=loop/{session-name}                    ║
║    tmux capture-pane -t loop-{session-name} -p | tail -20  ║
║                                                            ║
║  Commands:                                                 ║
║    /loop status           - Check all loops                ║
║    /loop attach {name}    - Watch live (Ctrl+b d detach)   ║
║    /loop kill {name}      - Stop the loop                  ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

---

## Subcommands

### /loop status

```bash
echo "=== Running Loops ==="
tmux list-sessions 2>/dev/null | grep "^loop-" || echo "No loops running"

echo ""
echo "=== Available Beads ==="
bd ready 2>/dev/null | head -10 || echo "No beads"
```

### /loop attach NAME

```bash
tmux attach -t loop-{NAME}
```

Remind user: `Ctrl+b` then `d` to detach without stopping.

### /loop kill NAME

```bash
tmux kill-session -t loop-{NAME}
```

Confirm before killing.

---

## Multi-Session Support

Multiple loops can run simultaneously:
```bash
# Each has separate beads and progress
tmux new-session -d -s "loop-auth" "$PLUGIN_DIR/scripts/loop-engine/run.sh work auth 15"
tmux new-session -d -s "loop-api" "$PLUGIN_DIR/scripts/loop-engine/run.sh work api 15"
```

---

## ALWAYS USE AskUserQuestion

Every interaction should use `AskUserQuestion` with practical options. Users can always select "Other" for custom input.
