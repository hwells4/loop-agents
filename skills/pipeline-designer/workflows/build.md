# Workflow: Build a Pipeline

Design a new pipeline architecture through understanding, architecture recommendation, and user confirmation.

## Step 1: Understanding Phase

**Philosophy:** This is not a checklist task. You have full latitude to explore and understand what the user wants. Trust your instincts. Follow the conversation where it leads. Use your intelligence to intuit what the user is trying to accomplish.

### Guidance (Not Constraints)

You may:
- Ask clarifying questions using AskUserQuestion
- Infer from context if intent is clear
- Explore the codebase to understand existing patterns
- Suggest alternatives if you see a better approach

You don't have to:
- Ask every possible question
- Follow a rigid script
- Get explicit answers to everything

### What You Need to Understand

Before proceeding, develop a clear mental model of:

1. **What problem are they solving?**
   - What outcome do they want?
   - What does success look like?

2. **What should each iteration accomplish?**
   - Is there a queue of work items?
   - Is it about progressive refinement?
   - Is it about generating ideas?

3. **When should the work stop?**
   - When a queue is empty?
   - When quality plateaus (consensus)?
   - After exactly N iterations?

4. **What outputs matter?**
   - Files produced?
   - State changes?
   - Handoff to next stage?

### When to Proceed

Proceed when you genuinely understand—not when you've asked N questions.

If the user's intent is clear from their initial message, you can proceed immediately. If it's ambiguous, ask targeted questions.

### Example Questions (Use AskUserQuestion)

Only if needed:

```json
{
  "questions": [{
    "question": "What triggers each iteration of this pipeline?",
    "header": "Trigger",
    "options": [
      {"label": "External queue (beads)", "description": "Work until all items are done"},
      {"label": "Quality improvement", "description": "Iterate until quality plateaus"},
      {"label": "Fixed count", "description": "Run exactly N times"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Architecture Agent (Mandatory)

**CRITICAL:** You MUST spawn the `pipeline-architect` subagent before presenting recommendations. This is not optional.

The subagent is defined at `.claude/agents/pipeline-architect.md`.

### Prepare the Summary

Before spawning, synthesize your understanding into a requirements summary:

```markdown
## Requirements Summary

**Problem:** [What they're solving]

**Iteration behavior:**
- Each iteration does: [description]
- Input per iteration: [what it reads]
- Output per iteration: [what it produces]

**Termination:**
- Stop when: [condition]
- Estimated iterations: [rough guess]

**Constraints:**
- Model preference: [opus/sonnet/haiku or inferred]
- Existing stages to reuse: [list or none]
- Special requirements: [any mentioned]
```

### Spawn the Agent

First, get existing stages:
```bash
ls scripts/stages/
```

Then invoke the subagent:

```
Task(
  subagent_type="pipeline-architect",
  description="Design pipeline architecture",
  prompt="""
REQUIREMENTS SUMMARY:
{your_requirements_summary}

EXISTING STAGES:
{output from ls scripts/stages/}
"""
)
```

### Process Agent Output

The architecture agent returns a YAML recommendation with:
- Stage definitions
- Termination strategies
- Data flow
- Rationale

Review the output for completeness before presenting to user.

## Step 3: Validate and Confirm

Present the architecture clearly. Use formatting to make it scannable.

### Presentation Template

```markdown
## Proposed Pipeline Architecture

**Name:** {name}
**Type:** {single-stage | multi-stage}

### Stages

| Stage | Termination | Model | Description |
|-------|-------------|-------|-------------|
| {name} | {type} | {model} | {description} |

### How It Works

{brief explanation of the flow}

### Existing Stages Reused

- {stage}: Already exists in scripts/stages/
- {stage}: Will be created

### Rationale

{why this architecture fits your use case}
```

### Get Confirmation

Use AskUserQuestion for explicit yes/no:

```json
{
  "questions": [{
    "question": "Does this architecture look right?",
    "header": "Confirm",
    "options": [
      {"label": "Yes, build it", "description": "Proceed to create the pipeline"},
      {"label": "No, let's adjust", "description": "I have changes to make"}
    ],
    "multiSelect": false
  }]
}
```

### On "No, let's adjust"

Either:
- Return to Step 1 for more discussion
- Re-invoke architecture agent with updated requirements
- Make targeted adjustments without full re-architecture

### On "Yes, build it"

1. Create spec directory if needed:
   ```bash
   mkdir -p .claude/pipeline-specs
   ```

2. Save the confirmed spec:
   ```bash
   # Write to .claude/pipeline-specs/{name}.yaml
   ```

3. Invoke pipeline-creator:
   ```
   Invoke skill: pipeline-creator
   Args: .claude/pipeline-specs/{name}.yaml
   ```

## Success Criteria

- [ ] Genuine understanding achieved (not just checklist)
- [ ] Architecture agent was spawned (mandatory)
- [ ] Architecture presented clearly
- [ ] User gave explicit confirmation
- [ ] Spec saved to `.claude/pipeline-specs/{name}.yaml`
- [ ] Pipeline-creator invoked with spec path
