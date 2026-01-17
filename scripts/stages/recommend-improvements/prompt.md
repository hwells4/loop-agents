# Recommend Plan Improvements

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

You are analyzing a plan and recommending improvements. **Do not edit the plan directly.** Instead, write your recommendations to a file so they can be reviewed, critiqued, and debated before implementation.

## Load the Plan

```bash
cat ${PROGRESS}

jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== $file ===" && cat "$file"
done
```

## First Pass: Review

Read the entire plan carefully. As you read, ask yourself:

- **What assumptions is this plan making that might be wrong?**
- **What would confuse an engineer trying to implement this?**
- **What's the weakest part of this plan?**
- **What abstraction or approach are we missing that would make this simpler or more elegant?**
- **What hidden opportunities exist? Places where a different paradigm would make everything click?**

Follow threads that interest you. Go deep where depth is warranted.

## Second Pass: Write Recommendations

Write your recommendations to `${PROGRESS}/../recommendations.md`. For each recommendation:

1. **What to change** - Be specific. Quote the section or describe exactly where.
2. **Why** - What's the problem with the current approach? What does this fix?
3. **Proposed text** - Write the actual content you'd add or the revision you'd make.

Focus on substance:
- Gaps that need filling
- Ambiguities that need clarifying
- Weak sections that need strengthening
- Missing considerations
- Better approaches or abstractions

Don't nitpick wording. Don't suggest reorganization for its own sake. Every recommendation should make the plan materially more implementable.

## Write Status

```json
{
  "decision": "stop",
  "reason": "Recommendations complete",
  "summary": "What you found and recommended",
  "work": {
    "items_completed": [],
    "files_touched": ["recommendations.md"]
  },
  "errors": []
}
```

Write to `${STATUS}`.

Use ultrathink.
