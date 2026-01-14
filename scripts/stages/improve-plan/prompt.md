# Plan Improver

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

${CONTEXT}

## Your Task

You are a senior architect reviewing and improving a plan. Make it better.

### Step 1: Load Context

Read the progress file:
```bash
cat ${PROGRESS}
```

**Check for input files from context.json:**
```bash
# Read initial inputs (from --input CLI flag)
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading input: $file"
  cat "$file"
done

# Read previous stage outputs (if this is part of a multi-stage pipeline)
jq -r '.inputs.from_stage | to_entries[] | .value[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading from previous stage: $file"
  cat "$file"
done

# Read parallel block outputs (if this follows a parallel stage)
jq -r '.inputs.from_parallel | to_entries[] | .value[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading from parallel block: $file"
  cat "$file"
done
```

If no inputs were provided, find plan files in the repo:
```bash
ls -la docs/*.md 2>/dev/null
ls -la *.md 2>/dev/null | grep -i plan
```

Also check for ideas to incorporate:
```bash
cat docs/ideas.md 2>/dev/null || echo "No ideas file"
```

### Step 2: Review Critically

Read the plan thoroughly. Look for:

**Completeness:**
- [ ] All user flows covered?
- [ ] Edge cases handled?
- [ ] Error scenarios addressed?
- [ ] Security considerations noted?

**Clarity:**
- [ ] Ambiguous language?
- [ ] Missing details?
- [ ] Inconsistencies?
- [ ] Undefined terms?

**Feasibility:**
- [ ] Realistic scope?
- [ ] Dependencies identified?
- [ ] Risks acknowledged?
- [ ] Testing strategy?

**Architecture:**
- [ ] Clean boundaries?
- [ ] Appropriate abstractions?
- [ ] Scalability considered?
- [ ] Maintainability?

### Step 3: Make Improvements

Edit the plan file directly. For each change:
- Clarify ambiguous sections
- Add missing details
- Remove unnecessary complexity
- Fix inconsistencies
- Incorporate relevant ideas from ideas.md

### Step 4: Update Progress

Append to progress file:
```
## Iteration ${ITERATION} - Plan Improvements
- [What you changed]
- [Why you changed it]
```

### Step 5: Write Status

After completing your work, write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Brief explanation of why work should continue or stop",
  "summary": "One paragraph describing what you improved this iteration",
  "work": {
    "items_completed": [],
    "files_touched": ["docs/plan.md"]
  },
  "errors": []
}
```

**Decision guide:**
- `"continue"` - You found significant gaps or errors that need fixing, or made substantial changes that might have introduced new issues
- `"stop"` - The plan is ready to implement; remaining issues are cosmetic, not substantive
- `"error"` - Something went wrong that needs investigation

Be honest. Don't stop early just to finish faster. Don't continue just to seem thorough.
The goal is a plan that's *ready to implement*, not *perfect*.
