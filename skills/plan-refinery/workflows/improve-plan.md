# Workflow: Improve Plan

Iteratively improve an existing markdown plan file. Each pass proposes specific improvements with detailed rationale.

## When to Use
- You have a markdown plan file you want to improve
- Before converting a plan to beads
- After synthesis, for further refinement
- Any time you want structured plan improvement

## Prerequisites
- A markdown plan file (path required)
- Clear understanding of the plan's goals

## Steps

### 1. Get Plan File

If not provided via command args, ask user:

```
Which plan file should I improve?

Please provide the path to your markdown plan file.
```

Wait for file path.

### 2. Verify File Exists

```bash
ls -la {plan_path}
```

If file doesn't exist, inform user and ask for correct path.

### 3. Spawn Plan Improver Agent

Read the full prompt from `references/sub-agents.md#plan_improver`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Improve markdown plan",
  prompt=f"""
Carefully review this entire plan for me and come up with your best revisions in terms of better architecture, new features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc. For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style change versus the original plan shown below.

PLAN FILE: {plan_path}

YOUR TASK:
1. Read the entire plan file carefully
2. Analyze for improvement opportunities:
   - Architecture: Better design decisions?
   - Features: Missing or improvable features?
   - Robustness: Error handling, edge cases, reliability?
   - Performance: Scalability, efficiency?
   - User Experience: More compelling, easier to use?
3. For EACH proposed change:
   - Explain WHY it makes the project better
   - Provide detailed rationale/justification
   - Show git-diff style change
4. Prioritize changes by impact

OUTPUT FORMAT:
## Plan Review: {{plan_name}}

### Change 1: {{title}}
**Impact:** High/Medium/Low
**Category:** Architecture/Feature/Robustness/Performance/UX

**Analysis:**
{{detailed reasoning for why this change improves the project}}

**Rationale:**
{{justification for the change}}

**Git-diff:**
```diff
- original text
+ improved text
```

---

### Change 2: {{title}}
...

## Summary
- Total changes proposed: {{count}}
- High impact: {{count}}
- Medium impact: {{count}}
- Recommended next iteration: Yes/No (are there likely more improvements?)

Maximum: 2,500 words output.
"""
)
```

### 4. Process Results

Display:
1. Each proposed change with rationale
2. Impact categorization
3. Summary with iteration recommendation

### 5. Apply Changes (Optional)

If user wants to apply changes:

```
Would you like me to apply these changes to the plan file?

[1] Apply all changes
[2] Apply selected changes (specify numbers)
[3] Review changes manually - don't apply automatically
```

If applying, use Edit tool to make the git-diff changes.

### 6. Offer Iteration

Based on agent's "Recommended next iteration" assessment:

```
PLAN IMPROVEMENT COMPLETE (Iteration {N})

Changes proposed: {count}
High impact: {count}

{if recommended_iteration}
Agent recommends another iteration - more improvements likely.
[1] Run another improvement pass
[2] Done - plan is good enough
{else}
Agent indicates diminishing returns - consider this plan ready.
[1] Run one more pass anyway
[2] Done - proceed with this plan
{/if}
```

## Iteration Strategy

- Run until improvements plateau
- More complex plans benefit from more iterations
- Watch for "same areas getting tweaked" as plateau signal
- Consider fresh session if stuck

## Success Criteria
- [ ] Plan file path obtained and verified
- [ ] Opus agent spawned with full prompt
- [ ] Agent provided detailed rationale for each change
- [ ] Changes categorized by impact
- [ ] Agent assessed need for further iteration
- [ ] User offered apply/iterate options
- [ ] Changes applied if requested
