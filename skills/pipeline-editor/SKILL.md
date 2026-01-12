---
name: pipeline-editor
description: Edit existing stages and pipelines. Use when user wants to modify stage.yaml, prompt.md, or pipeline.yaml configurations.
---

## What This Skill Does

Modifies existing stage and pipeline configurations, and answers questions about them. Conversational approach—understand what the user wants, figure out what to do, act with intelligence.

## Natural Skill Detection

Trigger on:
- "Edit the elegance stage"
- "Change the termination strategy for..."
- "Modify the work loop to use..."
- "Make the improve-plan stage use opus"
- "How does the work stage decide when to stop?"
- "What model does elegance use?"
- `/pipeline edit`

## Philosophy

**Use your intelligence.** This is not a checklist task.

You might be editing. You might be answering questions. You might be exploring options with the user. The conversation will tell you what's needed.

When editing:
1. Listen to what they want
2. Figure out which files need editing
3. Propose a plan
4. Execute after confirmation

When answering questions:
1. Investigate the actual configuration
2. Give a direct, specific answer
3. Offer to make changes if relevant

When exploring:
1. Probe specific ideas - "Would increasing consensus help with false positives?"
2. Show real examples from the codebase
3. Help them think through the implications

**Don't standardize.** Each conversation is different. Trust your judgment about when you have enough context to act.

## Intake

If the user says `/pipeline edit` without context:

> What would you like to change or know about?

Then follow the conversation. They might want to:
- Edit something: "Make the elegance stage run longer"
- Ask a question: "What termination strategy does work use?"
- Explore options: "I'm not sure if judgment or queue is right for my use case"

## Workflow

There's no fixed workflow. Use your judgment. Common patterns:

**For edits:**
```
Listen → Investigate → Propose → Confirm → Execute
```

**For questions:**
```
Investigate → Answer directly → Offer related changes if relevant
```

**For exploration:**
```
Probe their thinking → Show real examples → Help them decide → Offer to implement
```

The key is: **investigate before acting**. Read the actual files. Understand what exists. Then respond appropriately.

## Investigation

Before proposing changes, read the relevant files:

```bash
# For a stage
cat scripts/stages/{stage}/stage.yaml
cat scripts/stages/{stage}/prompt.md

# For a pipeline
cat scripts/pipelines/{name}.yaml

# To see what exists
ls scripts/stages/
ls scripts/pipelines/*.yaml
```

## Proposing Changes

Present a clear plan before editing:

```markdown
## Proposed Changes

**Target:** `scripts/stages/elegance/stage.yaml`

**Current:**
```yaml
termination:
  type: judgment
  consensus: 2
```

**After:**
```yaml
termination:
  type: judgment
  consensus: 3
```

Does this look right?
```

Only proceed after explicit confirmation.

## Validation

After making changes, always validate:

```bash
./scripts/run.sh lint loop {stage}
# or
./scripts/run.sh lint pipeline {name}.yaml
```

If validation fails, fix the issue before presenting the result.

## Editable Properties

### Stage (stage.yaml)

| Property | Description |
|----------|-------------|
| `termination.type` | queue, judgment, or fixed |
| `termination.min_iterations` | Start checking after N (judgment) |
| `termination.consensus` | Consecutive stops needed (judgment) |
| `termination.max_iterations` | Hard limit (fixed) |
| `model` | opus, sonnet, or haiku |
| `delay` | Seconds between iterations |

### Stage (prompt.md)

| Section | Notes |
|---------|-------|
| Context section | Preserve ${CTX}, ${PROGRESS}, ${STATUS} |
| Autonomy grant | Preserve the philosophy |
| Guidance | Edit task-specific instructions |
| Status template | Preserve JSON format |

### Pipeline (pipeline.yaml)

| Property | Description |
|----------|-------------|
| `stages[].loop` | Which stage to run |
| `stages[].runs` | Max iterations for this stage |
| `stages[].inputs` | Dependencies on previous stages |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| edit.md | Full editing workflow |

## Success Criteria

- [ ] Responded appropriately to what the user actually wanted
- [ ] Investigated actual configuration before acting
- [ ] For edits: proposed plan and got confirmation before changing
- [ ] For edits: validated with lint after changing
- [ ] For questions: gave specific, accurate answers
- [ ] Used intelligence, not checklists
