# Create Pipeline Workflow

## Step 1: Understand the Goal

Ask the user what they want the pipeline to accomplish:

```json
{
  "questions": [{
    "question": "What should this pipeline accomplish?",
    "header": "Goal",
    "options": [
      {"label": "Code Review", "description": "Multi-perspective review with synthesis"},
      {"label": "Research & Implement", "description": "Research, plan, then implement"},
      {"label": "Ideation", "description": "Generate and synthesize ideas"},
      {"label": "Custom", "description": "I'll describe my pipeline"}
    ],
    "multiSelect": false
  }]
}
```

If they choose a template option, read the corresponding template from:
`scripts/orchestrator/templates/{option}.yaml`

Use it as a starting point, then customize.

## Step 2: Gather Pipeline Details

For custom pipelines, gather:

1. **Pipeline name** - short, lowercase, hyphens (e.g., `api-review`)
2. **Description** - one sentence explaining purpose
3. **Stages** - what are the major steps?

Ask clarifying questions:
- How many stages do you need?
- Should any stage run multiple times (fan-out)?
- Should any stage aggregate results from previous (fan-in)?
- Do you need any iterative refinement (plateau detection)?

## Step 3: Design Each Stage

For each stage, determine:

| Field | Question |
|-------|----------|
| `name` | What's a short name for this stage? |
| `description` | What does this stage do? |
| `runs` | How many times should it run? |
| `parallel` | Should runs be simultaneous? |
| `completion` | Should it stop early? (plateau/beads-empty) |
| `perspectives` | If fan-out, what are the different angles? |
| `model` | Which model? (opus for complex, sonnet for fast, haiku for simple) |
| `prompt` | What instructions should the agent follow? |

## Step 4: Write the YAML

Create the pipeline definition:

```bash
# Ensure directory exists
mkdir -p .claude/pipelines
```

Write the YAML file using the Write tool to `.claude/pipelines/{name}.yaml`

**Follow this structure:**
```yaml
name: {name}
description: {description}
version: 1

defaults:
  provider: claude-code
  model: sonnet

stages:
  - name: {stage1-name}
    description: {stage1-description}
    runs: {number}
    prompt: |
      {stage1-prompt}

  - name: {stage2-name}
    # ...
```

## Step 5: Validate

Check the pipeline:

1. Read the file back
2. Verify YAML is valid
3. Check that stage names are unique
4. Verify variable references (`${INPUTS.stage-name}`) match actual stage names

## Step 6: Confirm

Tell the user:
- Pipeline saved to `.claude/pipelines/{name}.yaml`
- How to run it: `/loop-agents:pipeline` then select "Run"
- Or directly: `.claude/loop-agents/scripts/orchestrator/run.sh {name}`

## Prompt Writing Tips

**Good prompts include:**
- Clear instructions on what to do
- Where to find input: `${INPUTS.previous-stage}`
- Where to write output: `${OUTPUT}`
- For plateau: explicit `PLATEAU: true/false` and `REASONING:` format

**Variable usage:**
```
# Read from previous stage
${INPUTS.stage-name}

# Write output
Write your findings to: ${OUTPUT}

# For multi-run stages with perspectives
You are reviewer ${INDEX}, focusing on: ${PERSPECTIVE}

# For iterative stages
Previous progress: ${PROGRESS}
Update ${PROGRESS} with your work.
```
