# Bug Elegance

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

${CONTEXT}

You are here to transform a raw list of discovered bugs into elegant action. Your job is to see patterns, find consolidations, and determine what's actually worth fixing versus what adds complexity for negligible gain.

This is not a checklist task. You have full latitude to explore, investigate, and use your intelligence as you see fit. Trust your instincts. Follow threads that interest you. Go deep where depth is warranted.

## Context

Read the progress file to see all the bugs that were discovered:
```bash
cat ${PROGRESS}
```

### Inputs from Previous Stages

If this stage is part of a multi-stage pipeline, you may have inputs from previous stages or initial files:

```bash
# Read initial inputs (CLI --input files)
jq -r '.inputs.from_initial[]? // empty' ${CTX} | while read file; do
  echo "Reading: $file"
  cat "$file"
done

# Read outputs from previous stages
jq -r '.inputs.from_stage | to_entries[]? | .value[]? // empty' ${CTX} | while read file; do
  echo "Reading previous stage output: $file"
  cat "$file"
done

# Read outputs from parallel blocks (if applicable)
jq -r '.inputs.from_parallel | to_entries[]? | .value[]? // empty' ${CTX} | while read file; do
  echo "Reading parallel output: $file"
  cat "$file"
done
```

## Exploration

Spin up subagents freely. When you need to understand a bug more deeply, trace its root cause through the codebase, or investigate whether a pattern you're seeing is real—launch a targeted subagent to explore it thoroughly and report back. Manage your context wisely. Use subagents for depth. Preserve your own context for synthesis and judgment.

Look at the set of potential bugs and determine which ones are critical, which need to be fixed, which would be nice to have, and which would actually add complexity for negligible gains.

But more importantly: look for elegant solutions. The solutions may not necessarily be exactly what the discovery agent suggested. If you notice a pattern between bugs, you might say "This abstraction would solve all these bugs and actually make the overall program simpler." That's the ideal—finding where one change makes multiple bugs disappear. Places where a different structure would make this class of bugs impossible.

## Output

Append your findings and triage decisions to the progress file.

Once you've identified elegant solutions worth implementing, create beads for them:

```bash
bd create --title="[Solution title]" --type=bug --priority=2 --label="pipeline/${SESSION_NAME}"
```

Use priority 0-1 for critical, 2 for should-fix, 3 for nice-to-have.

## Write Status

After completing your analysis, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Why there's more to analyze or why you've found what there is to find",
  "summary": "Sharp observations—what patterns you found, what elegant consolidations emerged",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": []
}
```

**Decision guide:**
- `"continue"` - More patterns to investigate, elegant solutions still emerging
- `"stop"` - You've synthesized what there is to synthesize; further analysis would yield diminishing returns

Use ultrathink.
