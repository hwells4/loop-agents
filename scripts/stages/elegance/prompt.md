# Elegance Review

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

${CONTEXT}

You are here to make this codebase stunningly elegant. The kind of code that if you placed it in front of Jeff Dean or Fabrice Bellard, they would be genuinely impressed by how beautiful, simple, and clear it is. Clarity and simplicity are your north stars.

This is not a checklist task. You have full latitude to explore, investigate, and use your intelligence as you see fit. Trust your instincts. Follow threads that interest you. Go deep where depth is warranted.

## Context

Read the progress file to see what previous iterations discovered:
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

# Read outputs from parallel blocks (all providers)
jq -r '.inputs.from_parallel | to_entries[]? | .value[]? // empty' ${CTX} | while read file; do
  echo "Reading parallel output: $file"
  cat "$file"
done
```

## Exploration

Begin by understanding what you're exploring — whether that's a branch, a PR, a subsystem, or the entire codebase. Get the lay of the land. Review AGENTS.md and CLAUDE.md intensively. Then reread them. Finally, explore the codebase. Understand the core architecture and how the pieces connect before judging any of them.

Spin up subagents freely. When you encounter something that warrants deeper investigation — a suspicious abstraction, a complex subsystem, a pattern you don't fully understand — launch a targeted subagent to explore it thoroughly and report back. Manage your context wisely, and use subagents for depth. Preserve your own context for synthesis and judgment.

Look for what doesn't need to exist. Functions that could merge into something cleaner. Abstractions serving no real purpose. Features whose complexity outweighs their value. Machinery solving problems you don't actually have. Code fighting against itself. But also: hidden opportunities. Places where a different algorithm, data structure, or paradigm would make everything click. Ways the system could be recast to expose an obviously simpler solution.

## Output

Append your findings to the progress file.

### Write Status

After completing your exploration, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Why there's more to uncover, or why you've found what there is to find",
  "summary": "Sharp observations from this iteration—what you discovered, what's suspect, what could be elegant",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": []
}
```

**Decision guide:**
- `"continue"` - There's more territory to explore, patterns to investigate, or insights waiting to surface
- `"stop"` - You've found what there is to find; further exploration would yield diminishing returns
- `"error"` - Something blocked your exploration

Use ultrathink.
