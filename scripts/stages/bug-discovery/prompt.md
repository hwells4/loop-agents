# Bug Discovery

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

First, read the progress file to see what previous iterations explored and found:
```bash
cat ${PROGRESS}
```

I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc.

**Do NOT fix the bugs.** Just document bugs, recommended fixes, and any changes you'd make.

Append what you find to the progress file. Include:
- Which files/areas you explored
- Any bugs you found (what the bug is, where it is, what the fix would be)
- Suspicious patterns worth investigating later
- What areas you intentionally skipped so future iterations don't repeat your work

Use ultrathink. Be methodical. Be critical.

## Write Status

After exploring, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "More areas to explore",
  "summary": "Brief summary of what you found",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": []
}
```
