# Plan Improver

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

## Your Task

You are a senior architect reviewing and improving a plan. Make it better.

### Step 1: Load Context

Read the progress file and find the plan:
```bash
cat ${PROGRESS_FILE}
```

Find plan files:
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

### Step 5: Output Summary

At the END of your response, output exactly:
```
CHANGES: {number of distinct improvements made}
SUMMARY: {one-line summary of what you improved}
```

If the plan is solid and needs no changes:
```
CHANGES: 0
SUMMARY: Plan is comprehensive and ready
```

## Guidelines

- Make substantive improvements, not cosmetic ones
- If you find yourself making tiny tweaks, the plan may be ready
- Don't add complexity for its own sake
- Focus on clarity and completeness
