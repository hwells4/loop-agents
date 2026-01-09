# Workflow: Synthesize Plans

Merge competing plans from multiple LLMs into a single "best of all worlds" hybrid.

## When to Use
- You have outputs from GPT Pro, Gemini Deep Think, Grok Heavy, Opus, etc.
- Different models produced different approaches to the same problem
- You want to extract the best ideas from each

## Prerequisites
- At least 2 competing plans (ideally 3-4)
- Plans addressing the same problem/feature
- Clear understanding of the original goals

## Steps

### 1. Collect Competing Plans

Ask user for the competing plans:

```
To synthesize competing plans, I need the plans from each LLM.

Please provide:
1. The plans (paste directly or provide file paths)
2. Which model produced each plan (for context)
3. The original goal/problem statement

You can paste the plans below or point me to files.
```

Wait for user input.

### 2. Format Plans for Agent

Structure the input:
```
ORIGINAL GOAL:
{goal from user}

PLAN 1 (GPT Pro):
{plan content}

---

PLAN 2 (Gemini Deep Think):
{plan content}

---

PLAN 3 (Grok Heavy):
{plan content}
```

### 3. Spawn Plan Synthesizer Agent

Read the full prompt from `references/sub-agents.md#plan_synthesizer`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Synthesize competing plans",
  prompt=f"""
I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan).

PLANS TO ANALYZE:
{formatted_plans}

YOUR TASK:
1. Read each competing plan carefully
2. For each plan, identify:
   - Unique strengths and good ideas
   - Better architecture decisions
   - Superior feature designs
   - More robust approaches
   - Better user experience considerations
3. Be INTELLECTUALLY HONEST - acknowledge when other plans are better
4. Create hybrid plan that takes the best from ALL sources
5. Output as git-diff style changes to the original

OUTPUT FORMAT:
## Analysis of Competing Plans

### Plan 1 Strengths
- {{strength}}

### Plan 2 Strengths
- {{strength}}

### Plan 3 Strengths
- {{strength}}

## Synthesis: Git-Diff Style Changes

```diff
- original line
+ improved line from synthesis
```

## Final Hybrid Plan
{{complete merged plan}}

Maximum: 3,000 words output. Detailed analysis stays internal.
"""
)
```

### 4. Process Results

Display:
1. Strengths identified from each plan
2. The git-diff style changes
3. The final hybrid plan

### 5. Offer Next Steps

```
PLAN SYNTHESIS COMPLETE

Strengths extracted from {N} competing plans.
Hybrid plan created with best-of-all-worlds approach.

Options:
[1] Save hybrid plan to file
[2] Convert to beads using bd
[3] Run /plan-refinery improve for further refinement
[4] Done - proceed with this plan
```

## Best Practices

- **GPT Pro web** is recommended as the "final arbiter" for plan synthesis
- Run this skill in Opus to get high-quality synthesis
- The more different the plans, the more value from synthesis
- Don't worry about attributing ideas to models in final plan

## Success Criteria
- [ ] User provided competing plans
- [ ] Plans formatted with clear separation
- [ ] Opus agent spawned with full prompt
- [ ] Agent identified strengths from each plan
- [ ] Agent was intellectually honest about better approaches
- [ ] Hybrid plan produced with git-diff changes
- [ ] User offered clear next steps
