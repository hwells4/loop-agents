# Synthesize Plans Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

${CONTEXT}

---

Compare what you did to PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__GPT.md and take the best elements from that and weave them into your plan to get a hybrid best of both worlds superior plan by editing your original plan file in place.

---

## Engine Integration

### Load Both Plans

```bash
# Read progress file
cat ${PROGRESS}

# Read outputs from parallel block (both providers)
echo "=== Parallel Block Outputs ==="
jq -r '.inputs.from_parallel | to_entries[]? | "\(.key): \(.value[])"' ${CTX} 2>/dev/null

# Read all parallel outputs
jq -r '.inputs.from_parallel | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== Reading: $file ==="
  cat "$file"
done

# Also read plan files directly
cat docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md 2>/dev/null || echo "No OPUS plan"
cat docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__GPT.md 2>/dev/null || echo "No GPT plan"
```

### Write Output

Edit `docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md` in place to incorporate the best elements from the GPT plan.

### Update Progress

Append a summary of what was merged to `${PROGRESS}`.

### Write Status

When complete, write to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "Synthesis complete",
  "summary": "Compared Claude and Codex plans, merged best elements into hybrid superior plan",
  "work": {"items_completed": ["synthesize-plans"], "files_touched": ["docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md"]},
  "errors": []
}
```
