# Fresh Eyes Review

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

Reread AGENTS.md and CLAUDE.md so they're still fresh in your mind.

Now carefully read over the entire plan document with "fresh eyes," looking super carefully for any errors, mistakes, problems, issues, confusion, conceptual errors, logical validations, ignoring of probability theory, sloppy thinking, inaccurate information/data, bad implicit assumptions, etc.

Carefully fix anything you uncover by revising the plan document in place in a series of small edits, not one big edit.

When you're done, write your result to `${STATUS}`:

```json
{
  "decision": "continue or stop",
  "reason": "What you found and fixed",
  "summary": "Brief summary of this iteration",
  "work": { "items_completed": [], "files_touched": [] },
  "errors": []
}
```
When deciding "continue" or "stop," use your judgment to assess whether the plan has reached a quality plateau. Stop when further review would yield diminishing returns. 

Be honest. Don't stop early just to finish faster. Don't continue just to seem thorough.