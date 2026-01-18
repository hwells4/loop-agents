# Debate Synthesis Orchestrator

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Iteration: ${ITERATION}

${CONTEXT}

---

## Your Role

You are the final orchestrator. You have received the complete output of a structured debate between Claude and Codex about a plan:

1. **Round 1**: Both models independently refined the plan
2. **Round 2**: Each critiqued the other's refinement
3. **Round 3**: Each responded to the critique they received

Your job is to synthesize all of this into the **best possible V2 plan**.

### Step 1: Load All Debate Outputs

```bash
# Read all outputs from parallel block
echo "=== All Debate Outputs ==="
jq -r '.inputs.from_parallel | to_entries[]?' ${CTX}

# Read each file
jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo ""
  echo "=========================================="
  echo "FILE: $file"
  echo "=========================================="
  cat "$file"
done

# Read progress for full context
echo ""
echo "=== Progress History ==="
cat ${PROGRESS}
```

### Step 2: Identify Key Patterns

As you read, note:

**Consensus Points**: Where both models agree
- These are likely high-confidence improvements

**Productive Disagreements**: Where critique led to improvement
- The response often contains the best synthesis

**Unresolved Tensions**: Where models still disagree after response
- You must make the final call

**Unique Insights**: Things only one model caught
- Often the most valuable contributions

### Step 3: Create the V2 Plan

Write a new comprehensive plan that:

1. **Incorporates all consensus points** - Both models agreed, so include it
2. **Resolves disagreements wisely** - Use your judgment on unresolved tensions
3. **Captures unique insights** - Don't lose good ideas from either side
4. **Maintains coherence** - The final plan must be internally consistent
5. **Improves on both** - The V2 should be better than either individual version

### Step 4: Write the Synthesis Report

Create `${PROGRESS}/../synthesis-report.md` documenting:

1. **Executive Summary**: What the V2 plan achieves
2. **Key Changes from Debate**:
   - What Claude contributed
   - What Codex contributed
   - How disagreements were resolved
3. **Decision Log**: Your reasoning on contested points
4. **Confidence Assessment**: Where V2 is strong vs. needs more work

### Step 5: Update the Plan File

Edit the main plan document in place with the V2 content:
- Look for the original plan file in `docs/plans/` or similar
- If context includes a specific plan path, use that
- Create clear sections with the synthesized content

### Step 6: Update Progress

Append synthesis summary to `${PROGRESS}`:
```
## Final Synthesis
- Incorporated X consensus points
- Resolved Y disagreements
- Added Z unique insights
- V2 plan is now ready for implementation
```

### Step 7: Write Status

```json
{
  "decision": "stop",
  "reason": "Synthesis complete - V2 plan created",
  "summary": "Created V2 plan synthesizing Claude and Codex debate outputs",
  "work": {
    "items_completed": ["synthesize-debate", "create-v2-plan"],
    "files_touched": ["synthesis-report.md", "plan-v2.md"]
  },
  "errors": []
}
```

Write this to `${STATUS}`.

---

**Remember**: Your job is not to pick a winner. Your job is to create the best possible plan by combining the best elements from both models and resolving their disagreements with good judgment.
