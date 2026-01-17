# Respond to the Critique

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

You made recommendations for improving a plan. Another model reviewed your recommendations and critiqued them.

Here's everything:

```bash
# The original plan
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== Original Plan: $file ===" && cat "$file"
done

# Your recommendations and their critique
jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== $file ===" && cat "$file"
done

cat ${PROGRESS}
```

## Your Task

Read their critique of your recommendations. For each point they raised:

- **Where are they right?** Acknowledge valid criticisms. Update or withdraw recommendations that don't hold up.
- **Where are they wrong?** Defend your position if you still believe it's correct. Explain why.
- **Where is it nuanced?** Sometimes both perspectives have merit. Explain the tradeoffs.

Also consider:
- Did their critique reveal something you missed?
- Should you add new recommendations based on this exchange?
- Are there points where you've both identified the same underlying issue but proposed different solutions?

Write your response to `${PROGRESS}/../response.md`. Be specific:
- Reference which of your recommendations you're defending, updating, or withdrawing
- Reference which of their critique points you're accepting or pushing back on
- If you're updating a recommendation, write the revised version

The goal is to converge on the best set of improvements, not to win the argument.

## Write Status

```json
{
  "decision": "stop",
  "reason": "Response complete",
  "summary": "What you accepted, what you defended, what you updated",
  "work": {
    "items_completed": [],
    "files_touched": ["response.md"]
  },
  "errors": []
}
```

Write to `${STATUS}`.

Use ultrathink.
