# Autonomous Agent

## Context

Read context from: ${CTX}
Progress file: ${PROGRESS}

## Workflow

1. **Read progress file** for accumulated context and patterns:
   ```bash
   cat ${PROGRESS}
   ```

2. **List available stories** for this session:
   ```bash
   bd ready --label=loop/${SESSION_NAME}
   ```

3. **Choose the most logical next story** based on:
   - What was already implemented (from progress file)
   - Dependencies and building blocks
   - Your judgment on what makes sense next

4. **Claim the story** you've chosen:
   ```bash
   bd update <bead-id> --status=in_progress
   ```

5. **Read full story details** including acceptance criteria:
   ```bash
   bd show <bead-id>
   ```

6. **Implement that ONE story**

## Verification

Check the progress file header for a `Verify:` line. If commands are specified, run them and fix any failures before proceeding.

If no verification commands specified, skip this step.

## After Verification Passes

7. **Commit** with detailed message:
   ```
   feat: [bead-id] - [Title]

   - What was added/changed
   - Key implementation details
   - Any notable decisions made
   ```

8. **Close the story**:
   ```bash
   bd close <bead-id>
   ```

9. **Append to progress file**:
   ```
   ## [Date] - [bead-id]
   - What was implemented
   - Files changed
   - Learnings/gotchas discovered
   ---
   ```

   Add new patterns to **Codebase Patterns** section at top of progress file.

## Write Status

After completing your work, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Completed [bead-id], more work remains",
  "summary": "What was implemented this iteration",
  "work": {
    "items_completed": ["bead-id"],
    "files_touched": ["path/to/modified/files"]
  },
  "errors": []
}
```

**Decision guide:**
- `"continue"` - Work completed, ready for next iteration
- `"stop"` - Queue empty, no more beads to work on
- `"error"` - Something went wrong (tests fail, blocked, etc.)

## Stop Condition

Check if any work remains:
```bash
bd ready --label=loop/${SESSION_NAME}
```

If no beads returned (empty output), all work is complete. Set decision to "stop".
