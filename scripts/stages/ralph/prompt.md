# Ralph Agent Instructions

Read context from: ${CTX}
Progress file: ${PROGRESS}

${CONTEXT}

## Your Task

1. Read `${PROGRESS}`
   (check Codebase Patterns first)

2. **Check for initial inputs** (requirements, plans, etc.):
   ```bash
   jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
     echo "Reading input: $file"
     cat "$file"
   done
   ```

3. Check remaining tasks:
   ```bash
   bd ready --label=pipeline/${SESSION_NAME}
   ```

4. Pick highest priority task

5. Claim it:
   ```bash
   bd update <bead-id> --status=in_progress
   ```

6. Implement that ONE task

7. **Run tests** (use commands from context.json):
   ```bash
   # Get test command from context.json (fallback to npm test)
   TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
   echo "Running tests: $TEST_CMD"
   $TEST_CMD

   # Optional: run lint if configured
   if jq -e '.commands.lint' ${CTX} > /dev/null 2>&1; then
     LINT_CMD=$(jq -r '.commands.lint' ${CTX})
     echo "Running lint: $LINT_CMD"
     $LINT_CMD
   fi
   ```

8. Commit: `feat: [bead-id] - [Title]`

9. Close the task:
   ```bash
   bd close <bead-id>
   ```

10. Append learnings to progress file

## Progress Format

APPEND to ${PROGRESS}:

```markdown
## [Date] - [bead-id]
- What was implemented
- Files changed
- **Learnings:**
  - Patterns discovered
  - Gotchas encountered
---
```

## Codebase Patterns

Add reusable patterns to the TOP of progress file:

```markdown
## Codebase Patterns
- [Pattern]: [How to use it]
- [Pattern]: [How to use it]
```

## Stop Condition

If queue is empty:
```bash
bd ready --label=pipeline/${SESSION_NAME}
# Returns nothing = done
```

Write to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "All tasks complete",
  "summary": "Queue empty",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

Otherwise, write `"decision": "continue"` and end normally.
