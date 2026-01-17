# Implement the Agreed Changes

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

Two models have debated how to improve a plan. They each:
1. Made recommendations
2. Critiqued each other's recommendations
3. Responded to the critiques

Your job is to synthesize this debate and **actually implement the changes** to the plan.

## Load Everything

```bash
# The original plan
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "=== Original Plan: $file ===" && cat "$file"
done

# All debate outputs (recommendations, critiques, responses from both models)
jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== $file ===" && cat "$file"
done

cat ${PROGRESS}
```

## First Pass: Identify What to Implement

Read through the entire debate. Categorize each recommendation:

**Consensus** - Both models agree this should be done (either originally or after debate)
- These are high-confidence changes. Implement them.

**One model convinced the other** - Started as disagreement, resolved through critique/response
- Implement the agreed-upon version.

**Unresolved disagreement** - They still disagree after the full exchange
- Use your judgment. Who has the stronger argument? What's best for the plan?

**Withdrawn** - Recommendations that were dropped after critique
- Don't implement these.

## Second Pass: Implement Changes

Now edit the plan file directly. Make small, targeted edits as you go:

- Find the section a recommendation addresses → make the edit
- Move to the next recommendation → make that edit
- Continue until all agreed changes are implemented

For each edit:
- Be faithful to what the debate concluded
- If you're resolving a disagreement, briefly note your reasoning in the plan (as a comment or "Design Decision" callout)

## Write Summary

After implementing, append to `${PROGRESS}`:

```markdown
## Implementation Summary

### Implemented (Consensus)
- [List of recommendations both models agreed on]

### Implemented (Resolved)
- [List of recommendations where one convinced the other]

### Implemented (Judgment Call)
- [List of unresolved disagreements and which side you chose + why]

### Not Implemented
- [List of withdrawn/rejected recommendations]
```

## Write Status

```json
{
  "decision": "stop",
  "reason": "Implementation complete",
  "summary": "Implemented X consensus changes, Y resolved changes, made Z judgment calls",
  "work": {
    "items_completed": [],
    "files_touched": ["plan file", "progress"]
  },
  "errors": []
}
```

Write to `${STATUS}`.

Use ultrathink.
