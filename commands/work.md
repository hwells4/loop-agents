---
description: Launch autonomous work loops to implement tasks from beads
---

# /work Command

**Implementation loop:** Autonomous agents pick up beads, implement them, and close them.

## Usage

```
/work                    # Start work loop for current session
/work auth               # Start work loop for 'auth' session
/work status             # Check running work loops
/work attach NAME        # Attach to watch live
/work kill NAME          # Stop a work loop
```

---

## What This Does

The work loop runs autonomously in tmux:

1. **Pick a ready bead** - Agent selects highest priority available task
2. **Implement** - Write code, tests, handle edge cases
3. **Verify** - Run tests, type checks, linting
4. **Commit & Close** - Commit changes, close the bead
5. **Repeat** - Until all beads complete or max iterations

### Stopping Criteria

**Stops when ALL beads are complete** (status = closed/done).

The agent checks `bd ready --label=loop/{session}` before each iteration. When no beads remain, the loop exits successfully.

---

## Execution

### Check Prerequisites

```bash
# Verify beads exist for this session
bd ready --label=loop/{session} 2>/dev/null | head -5
```

If no beads:
- Offer to run `/loop-agents:create-tasks` to create them
- Or point to existing beads

### Calculate Iterations

Formula: `(number of beads * 1.5) + 3` rounded up

- 5 beads -> 11 iterations
- 10 beads -> 18 iterations
- 20 beads -> 33 iterations

### Ask for Confirmation

```yaml
question: "Launch work loop for '{session}'?"
header: "Work Loop"
options:
  - label: "Yes, start ({N} iterations)"
    description: "{M} beads ready to implement"
  - label: "Test one iteration first"
    description: "Run once to verify setup"
  - label: "Adjust iterations"
    description: "I want more or fewer"
```

### Launch in tmux

```bash
SESSION_NAME="{session}"
ITERATIONS="{iterations}"
PLUGIN_DIR=".claude/loop-agents"

tmux new-session -d -s "loop-$SESSION_NAME" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/loops/run.sh work $SESSION_NAME $ITERATIONS"
```

### Show Status

```
Work Loop Launched: loop-{session}

Running autonomously ({iterations} iterations max)
Beads: {count} ready to implement

Monitor:
  bd ready --label=loop/{session}
  tmux capture-pane -t loop-{session} -p | tail -20

Commands:
  /work status         - Check all work loops
  /work attach {name}  - Watch live (Ctrl+b d to detach)
  /work kill {name}    - Stop the loop
```

---

## Test Mode

For single iteration test:

```bash
# Run one iteration in foreground
$PLUGIN_DIR/scripts/loops/run.sh work $SESSION_NAME 1
```

This helps verify:
- Beads are well-defined
- Agent understands the codebase
- Tests pass

---

## Subcommands

### /work status

```bash
echo "=== Running Work Loops ==="
tmux list-sessions 2>/dev/null | grep "^loop-" || echo "No work loops running"

echo ""
echo "=== Beads by Session ==="
for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^loop-" | sed 's/^loop-//'); do
  count=$(bd ready --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")
  echo "  $session: $count beads remaining"
done
```

### /work attach NAME

```bash
tmux attach -t loop-{NAME}
```

Remind: `Ctrl+b` then `d` to detach without stopping.

### /work kill NAME

```bash
tmux kill-session -t loop-{NAME}
```

Confirm before killing: "This will stop the work loop. Beads in progress may be left incomplete."

---

## Progress Tracking

Work loops write to:
- **Progress file:** `.claude/loop-progress/progress-{session}.txt`
- **State file:** `.claude/loop-state-{session}.json`

Progress file accumulates learnings across iterations:
- Codebase patterns discovered
- Verification commands that work
- Gotchas to watch for

---

## When Work Completes

The loop notifies you (desktop notification on macOS/Linux).

Check results:
```bash
# Closed beads
bd list --status=closed --label=loop/{session}

# Any remaining
bd ready --label=loop/{session}

# Progress notes
cat .claude/loop-progress/progress-{session}.txt
```

---

## Troubleshooting

**Bead stuck?** Agent may be confused by requirements.
- Attach to see what's happening
- Kill and refine the bead with `/refine beads`

**Tests failing?** May need manual intervention.
- Attach, fix the issue
- Or let agent retry next iteration

**Too many iterations?** Agent may be overcounting.
- Default formula is generous
- Reduce iterations for well-defined beads

**Session already running?** Lock prevents duplicate sessions.
```bash
# Check if actually running
tmux has-session -t loop-{NAME} && echo "running" || echo "stale lock"

# View lock details (who holds it, when started)
cat .claude/locks/{NAME}.lock | jq

# Force start (override lock)
./scripts/run.sh loop work {NAME} 25 --force

# Or clear stale lock manually
rm .claude/locks/{NAME}.lock
```
