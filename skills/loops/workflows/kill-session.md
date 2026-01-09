# Workflow: Kill a Session

<process>

## Step 1: Verify Session Exists

```bash
tmux has-session -t loop-NAME 2>/dev/null || echo "Session not found"
```

## Step 2: Check if Work is Complete

```bash
tmux capture-pane -t loop-NAME -p | grep -q "<promise>COMPLETE</promise>" \
  && echo "✅ Work appears complete - safe to kill" \
  || echo "⚠️  Work may not be complete - check progress.txt after"
```

## Step 3: Confirm with User

If work not complete, ask:
```
Session loop-NAME has not signaled completion.
Kill anyway? Work in progress may be lost.
```

## Step 4: Kill the Session

```bash
tmux kill-session -t loop-NAME
```

## Step 5: Update State File

Remove session from `.claude/loop-sessions.json` or mark as `"status": "killed"`.

## Step 6: Verify Termination

```bash
tmux has-session -t loop-NAME 2>/dev/null \
  && echo "❌ Session still exists" \
  || echo "✅ Session terminated"
```

## Step 7: Point to Artifacts

```
Session killed. Check results:
- Progress: .claude/loop-progress/progress-{session}.txt
- Commits: git log --oneline -10
- Beads: bd list --label=loop/{session}
```

</process>

<success_criteria>
- [ ] User confirmed kill (if incomplete)
- [ ] Session terminated
- [ ] State file updated
- [ ] User pointed to artifacts
</success_criteria>
