# Workflow: Manage Session

<required_reading>
**Read these reference files NOW:**
1. references/commands.md (full command reference)
2. references/troubleshooting.md (if issues arise)
</required_reading>

<process>

## Adding Agents

Add more agents to running session:

```bash
ntm add {session} --cc=2 --cod=1
```

Verify new agents:
```bash
ntm status {session}
```

## Interrupting Agents

Send Ctrl+C to all agent panes:

```bash
ntm interrupt {session}
```

Use when:
- Agents going off track
- Need to redirect work
- Emergency stop

## Creating Checkpoints

Save session state before risky operations:

```bash
ntm checkpoint save {session} -m "before refactor"
```

List checkpoints:
```bash
ntm checkpoint list {session}
```

Show checkpoint details:
```bash
ntm checkpoint show {session} {checkpoint-id}
```

Delete old checkpoint:
```bash
ntm checkpoint delete {session} {checkpoint-id}
```

## Detaching and Reattaching

**Detach (keep session running):**
Press `Ctrl+B` then `D` inside tmux.

**Reattach:**
```bash
ntm attach {session}
```

**Check if session exists:**
```bash
ntm list
```

## Killing Sessions

**Graceful shutdown:**
```bash
# Ask agents to finish
ntm send {session} --all "Finish current task and summarize progress"

# Wait for completion
ntm activity {session}

# Save outputs
ntm save {session} -o ~/outputs/

# Kill
ntm kill {session}
```

**Force kill:**
```bash
ntm kill {session} -f
```

## Viewing Session Layout

```bash
ntm view {session}
```

Zoom to specific pane:
```bash
ntm zoom {session} 2
```

## Using Command Palette

Open interactive palette:
```bash
ntm palette {session}
```

Or press F6 inside tmux (if bound).

Features:
- Fuzzy search commands
- Pin favorites with Ctrl+P
- Quick select with 1-9

</process>

<checkpoint_strategy>

**When to checkpoint:**
- Before major refactors
- After completing milestones
- Before sending risky prompts
- At regular intervals for long sessions

**Checkpoint naming:**
```bash
ntm checkpoint save {session} -m "auth complete"
ntm checkpoint save {session} -m "tests passing"
ntm checkpoint save {session} -m "before db migration"
```

</checkpoint_strategy>

<session_recovery>

If session crashes:

1. Check if session still exists:
   ```bash
   tmux list-sessions
   ```

2. Try to reattach:
   ```bash
   ntm attach {session}
   ```

3. If lost, check for checkpoints:
   ```bash
   ntm checkpoint list {session}
   ```

4. Save any remaining output:
   ```bash
   tmux capture-pane -t {session}:0 -p > recovery.txt
   ```

5. Start fresh if needed:
   ```bash
   ntm spawn {session}-v2 --cc=3 --cod=2
   ```

</session_recovery>

<success_criteria>

Session management successful when:
- [ ] Can add agents to running session
- [ ] Can interrupt agents when needed
- [ ] Checkpoints created at milestones
- [ ] Can detach and reattach cleanly
- [ ] Sessions terminate without orphan processes

</success_criteria>
