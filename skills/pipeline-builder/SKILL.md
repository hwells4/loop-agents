---
name: pipeline-builder
description: Create and configure loop agents and pipelines. Use when user wants to build a new loop type, create a multi-stage pipeline, or customize autonomous agent workflows.
---

## What This Skill Does

Helps you create custom loop agents and pipelines for the loop-agents system. You can:
- Create new loop types with custom prompts and completion strategies
- Chain loops into multi-stage pipelines
- Edit existing loops and pipelines
- Validate configurations before running

## Opinionated Defaults

Apply these defaults based on what the user is trying to accomplish. Only deviate if they explicitly request otherwise.

| Task Type | Completion Strategy | Rationale |
|-----------|---------------------|-----------|
| Implementation/coding/work | `beads-empty` | Stop when all tasks are done |
| Refinement/review/planning | `plateau` | Stop when 2 agents agree quality plateaued |
| Brainstorming/ideation/exploration | `fixed-n` | Run exactly N iterations |

**Model default:** `opus` (best quality for autonomous work)

**Delay default:** `3` seconds between iterations (prevents rate limiting)

**Min iterations for plateau:** `2` (need at least 2 agents to compare)

## Adaptive Requirements Gathering

**Do not follow a rigid question script.** Instead:

1. Look at what the user has already told you
2. Determine what information is missing for the task type
3. Use your judgment to decide if you need clarification or can proceed with sensible defaults

**For creating a loop, you need to know:**
- What should each iteration do? (the agent's task)
- When should the loop stop? (completion condition)
- Any special output parsing needed?

**For creating a pipeline, you need to know:**
- What stages should it have?
- How many runs per stage?
- What loops does each stage use (existing or new)?

If the user's description is clear enough, proceed. If not, ask focused questions using `AskUserQuestion`.

## Process

### 1. Understand Intent

When invoked, determine what the user wants:
- **Create loop** → `workflows/create-loop.md`
- **Create pipeline** → `workflows/create-pipeline.md`
- **Edit existing** → `workflows/edit.md`

If unclear, ask:
```json
{
  "questions": [{
    "question": "What would you like to build?",
    "header": "Build Type",
    "options": [
      {"label": "New Loop", "description": "Create a custom loop agent with its own prompt and completion strategy"},
      {"label": "New Pipeline", "description": "Chain multiple loops together into a multi-stage workflow"},
      {"label": "Edit Existing", "description": "Modify an existing loop or pipeline configuration"}
    ],
    "multiSelect": false
  }]
}
```

### 2. Execute Workflow

Read and follow the appropriate workflow file exactly.

### 3. Verify Configuration

**Always run verification after creating or editing.** Use the built-in validation commands:

```bash
# Validate a loop
./scripts/run.sh lint loop {name}

# Validate a pipeline
./scripts/run.sh lint pipeline {name}

# Preview what will happen (shows resolved prompt, files, completion strategy)
./scripts/run.sh dry-run loop {name} test-session
./scripts/run.sh dry-run pipeline {name} test-session
```

**Validation checks:**
- YAML syntax is valid
- Required fields present (`name`, `completion` for loops; `name`, `stages` for pipelines)
- Completion strategy file exists
- Prompt file exists
- Plateau loops have `output_parse` with `PLATEAU`
- Referenced loops exist (for pipelines)
- Template variables are from the known set

**If lint fails:** Fix the reported errors before telling the user the configuration is ready.

**If lint passes:** Run dry-run to show the user what will happen when they run it

## Quick Reference

**Loop types location:** `scripts/loops/{name}/`
- `loop.yaml` - configuration
- `prompt.md` - what agent does each iteration

**Pipeline location:** `scripts/pipelines/{name}.yaml`

**Commands:**
```bash
# Validate configurations
./scripts/run.sh lint                        # All loops and pipelines
./scripts/run.sh lint loop {name}            # Specific loop
./scripts/run.sh lint pipeline {name}        # Specific pipeline

# Preview execution (shows resolved prompt, files, strategy)
./scripts/run.sh dry-run loop {name} {session}
./scripts/run.sh dry-run pipeline {name} {session}

# Run a loop
./scripts/run.sh loop {name} {session} {max_iterations}

# Run a pipeline
./scripts/run.sh pipeline {name}.yaml {session}
```

## Reference Index

| Reference | Purpose |
|-----------|---------|
| references/loop-config.md | Complete loop.yaml configuration options |
| references/pipeline-config.md | Pipeline YAML structure and options |
| references/template-variables.md | All available ${VARIABLES} |
| references/completion-strategies.md | When to use each strategy |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| workflows/create-loop.md | Step-by-step loop creation |
| workflows/create-pipeline.md | Step-by-step pipeline creation |
| workflows/edit.md | Modify existing configurations |
