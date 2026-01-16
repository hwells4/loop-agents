# Review Oversights Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

${CONTEXT}

---

Great. Look over everything again for any obvious oversights or omissions or mistakes, conceptual errors, blunders, etc. Use ultrathink.

OK, save all of that as PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md (or PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__GPT.md if running as Codex).

---

## Engine Integration

### Load Previous Work

```bash
# Read progress file
cat ${PROGRESS}

# Read outputs from previous stages
jq -r '.inputs.from_stage | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== Previous stage output: $file ==="
  cat "$file"
done
```

### Write Output

Save the reviewed and corrected plan to `docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md` (or `*_GPT.md` if running as Codex).

### Update Progress

Append a summary of corrections to `${PROGRESS}`.

### Write Status

When complete, write to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "Review complete",
  "summary": "Reviewed optimization plan for oversights and corrected issues",
  "work": {"items_completed": ["review-oversights"], "files_touched": []},
  "errors": []
}
```
