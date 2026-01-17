# Plan Refinement

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

You are refining a plan to make it genuinely excellent. The kind of plan that if you handed it to a senior engineer, they could implement it without asking clarifying questions. Clarity, completeness, and implementability are your north stars.

This is not a checklist task. You have full latitude to think deeply, follow threads that interest you, and use your intelligence as you see fit. Trust your instincts.

## Load the Plan

```bash
cat ${PROGRESS}

jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== $file ===" && cat "$file"
done

jq -r '.inputs.from_stage | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== $file ===" && cat "$file"
done

jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
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

## Second Pass: Edit As You Go

Now go through the plan again and **make small, targeted edits as you find things**. Don't save everything up for one big edit at the end.

- Find an issue → fix it immediately with a small edit
- Find a gap → add a section right then
- Find ambiguity → clarify it on the spot

Each edit should be focused and surgical. This keeps edits reliable and lets you build improvements incrementally.

**Append and expand.** The goal right now is to strengthen the plan—add sections, expand thin areas, clarify ambiguities, fill gaps.

Be thoughtful about deletion. If something should be removed, think carefully about why. Removal should be rare and deliberate.

## Write Status

When you've made your improvements:

```json
{
  "decision": "continue",
  "reason": "What still needs attention",
  "summary": "What you improved and why",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": []
}
```

Write to `${STATUS}`. Set `"decision": "stop"` only when the plan is genuinely ready for implementation and further changes would be cosmetic.

Use ultrathink.
