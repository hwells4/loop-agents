# Workflow: Idea Wizard

Generate 30 improvement ideas for a project, rigorously evaluate each, then winnow to the very best 5 with full rationale.

## When to Use
- Early in planning to generate fresh ideas
- When feeling stuck or in tunnel vision
- Before finalizing a plan to ensure nothing was missed
- When you want rigorous evaluation of potential improvements

## Prerequisites
- Project context available (beads, plan file, or codebase)
- Understanding of project goals

## Steps

### 1. Determine Context Source

Ask user how to provide project context:

```
The Idea Wizard needs project context to generate relevant ideas.

How should I provide context?
[1] Use current beads (bd list)
[2] Use a plan file (provide path)
[3] Explore the codebase
[4] I'll paste/describe the project
```

### 2. Gather Context

Based on user choice:

**Option 1 - Beads:**
```bash
bd list --status=open
bd stats
```
Capture output as context.

**Option 2 - Plan file:**
Read the file content.

**Option 3 - Codebase:**
Let agent explore with Task tool (include instruction in prompt).

**Option 4 - User input:**
Wait for user to provide context.

### 3. Spawn Idea Wizard Agent

Read the full prompt from `references/sub-agents.md#idea_wizard`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Generate best improvement ideas",
  prompt=f"""
Come up with your very best ideas for improving this project to make it more robust, reliable, performant, intuitive, user-friendly, ergonomic, useful, compelling, etc. while still being obviously accretive and pragmatic. Come up with 30 ideas and then really think through each idea carefully, how it would work, how users are likely to perceive it, how we would implement it, etc; then winnow that list down to your VERY best 5 ideas. Explain each of the 5 ideas in order from best to worst and give your full, detailed rationale and justification for how and why it would make the project obviously better and why you're confident of that assessment. Use ultrathink.

PROJECT CONTEXT:
{project_context}

YOUR TASK:
1. Understand the project thoroughly first
2. Brainstorm 30 improvement ideas across all dimensions:
   - Robustness and reliability
   - Performance and efficiency
   - Intuitive design and user-friendliness
   - Ergonomics and developer experience
   - Usefulness and value proposition
   - Compelling features that delight users
3. For EACH of the 30 ideas, think through:
   - How would this actually work?
   - How would users perceive it?
   - How would we implement it?
   - Is it pragmatic and accretive?
4. Winnow to your VERY BEST 5 ideas
5. Rank them best to worst with full justification

OUTPUT FORMAT:
## Idea Generation: {{project_name}}

### Initial 30 Ideas (Brief List)
1. {{idea}}
2. {{idea}}
...
30. {{idea}}

### Winnowed to Top 5

#### #1: {{title}} (BEST)
**What it is:**
{{description}}

**How it works:**
{{mechanics}}

**User perception:**
{{how users will experience this}}

**Implementation approach:**
{{how to build it}}

**Why this is the best idea:**
{{detailed rationale and justification}}

**Confidence level:** High/Medium
{{why you're confident}}

---

#### #2: {{title}}
...

(continue for all 5)

## Summary
These 5 ideas were selected from 30 because they best combine:
- Obvious value to users
- Pragmatic implementation
- Meaningful improvement to the project

Maximum: 3,000 words output. The 30→5 winnowing process stays internal.
"""
)
```

### 4. Process Results

Display the full output:
- The 30 initial ideas (brief list)
- The top 5 with full rationale
- The summary

### 5. Act on Ideas

Present options:

```
IDEA WIZARD COMPLETE

Top 5 ideas generated with full rationale.

What would you like to do with these ideas?

[1] Add selected ideas as beads (specify which: 1-5)
[2] Update existing plan with these ideas
[3] Run another Idea Wizard pass (different angle)
[4] Save ideas to file for later
[5] Done - I'll act on these manually
```

**If adding to beads:**
For each selected idea, create a bead:
```bash
bd create --title="{idea title}" --type=feature --body="{idea details}"
```

**If updating plan:**
Run the plan-improver workflow with these ideas as input.

## The 30→5 Process

The magic of this prompt is the **winnowing process**:

1. **Divergent thinking:** 30 ideas forces breadth
2. **Rigorous evaluation:** Each idea gets thought through
3. **Convergent selection:** Only the truly best 5 survive
4. **Full justification:** No hand-waving - real rationale

This process happens inside the agent's reasoning, so you get the best 5 without paying for 30 detailed write-ups.

## Success Criteria
- [ ] Project context gathered appropriately
- [ ] Opus agent spawned with full prompt
- [ ] Agent generated 30 initial ideas
- [ ] Agent winnowed to exactly 5
- [ ] Each of 5 has full rationale and justification
- [ ] Ideas ranked best to worst
- [ ] User offered actionable next steps
