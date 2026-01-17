# Critique the Other Model's Recommendations

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

We asked you to recommend improvements to a plan. But we also asked another model to do the same thing.

Here's the original plan and their recommendations:

```bash
# The original plan
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== Original Plan: $file ===" && cat "$file"
done

# The other model's recommendations
jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== Other Model's Recommendations: $file ===" && cat "$file"
done

cat ${PROGRESS}
```

## Your Task

Read the original plan, then read their recommendations carefully. Tell us what you think:

- **What did they get right?** Which recommendations are genuinely good improvements?
- **What did they miss?** What important issues did they not address?
- **What did they get wrong?** Where do you disagree with their proposed changes?
- **What would you push back on?** If you were debating this, what points would you raise?
- **What did they see that you didn't?** Be honest—did they catch something you missed in your own analysis?

Don't be diplomatic for the sake of it. Be honest and direct. The goal is to surface the best ideas and catch the real problems.

Write your critique to `${PROGRESS}/../critique.md`. Be specific—reference their recommendation numbers, quote their text, explain your reasoning.

## Write Status

```json
{
  "decision": "stop",
  "reason": "Critique complete",
  "summary": "What you found—which recommendations are good, which are wrong, what they missed",
  "work": {
    "items_completed": [],
    "files_touched": ["critique.md"]
  },
  "errors": []
}
```

Write to `${STATUS}`.

Use ultrathink.
