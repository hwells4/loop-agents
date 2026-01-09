# Workflow: Monitor a Session (Safe Peek)

<process>

## Step 1: List Available Sessions

```bash
tmux list-sessions 2>/dev/null | grep "^loop-" || echo "No loop sessions found"
```

## Step 2: Capture Output (Without Attaching)

This is safe - it doesn't interrupt your terminal:

```bash
# Last 50 lines
tmux capture-pane -t loop-NAME -p | tail -50

# Full scrollback (up to 1000 lines)
tmux capture-pane -t loop-NAME -p -S -1000
```

## Step 3: Check Completion Status

```bash
# Extract session tag from name (e.g., "auth" from "loop-auth")
SESSION_TAG="${NAME#loop-}"

# Check remaining beads
bd ready --label="loop/$SESSION_TAG" 2>/dev/null | wc -l
# 0 = complete, >0 = work remaining

# Check for completion signal in output
tmux capture-pane -t loop-NAME -p | grep -q "<promise>COMPLETE</promise>" \
  && echo "✅ COMPLETE" || echo "⏳ In progress"

# Check for errors
tmux capture-pane -t loop-NAME -p | grep -i "error\|failed\|exception" | tail -5
```

## Step 4: Check Session Age

```bash
# Get session creation time (approximate from state file)
cat .claude/loop-sessions.json 2>/dev/null | grep -A5 "loop-NAME"
```

If session is > 2 hours old, warn:
```
⚠️  Session "loop-NAME" has been running for over 2 hours.
Consider checking if it's stuck or needs intervention.
```

## Step 5: Report Status

Show summary:
```
Session: loop-NAME
Status:  Running / Complete / Possibly stuck
Runtime: ~X hours
Stories remaining: bd ready --label=loop/SESSION_TAG | wc -l
Last output: [last 3 lines]
```

</process>

<success_criteria>
- [ ] Session output captured without attaching
- [ ] Completion status checked
- [ ] Stale warning shown if applicable
- [ ] User has clear picture of session state
</success_criteria>
