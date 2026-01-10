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

**Always run verification after creating or editing.** Spawn the verification subagent:

```
Task tool with subagent_type: "Explore"
Prompt: See <verification_protocol> below
```

## Verification Protocol

After creating or modifying any loop or pipeline, spawn a verification subagent with this prompt:

<verification_protocol>

You are validating a loop-agents configuration. Check everything thoroughly.

**Target:** {path to created/modified files}

## Validation Checklist

### For Loops (scripts/loops/{name}/)

1. **loop.yaml syntax**
   ```bash
   # Check YAML is valid
   cat scripts/loops/{name}/loop.yaml | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"
   ```

2. **Required fields present**
   - `name` - must match directory name
   - `completion` - must be one of: beads-empty, plateau, fixed-n
   - `description` - should explain what loop does

3. **Completion strategy configuration**
   - If `plateau`: must have `output_parse` with `plateau:PLATEAU`
   - If `plateau`: should have `min_iterations: 2` or higher
   - If `beads-empty`: should have `check_before: true`

4. **prompt.md exists and is valid**
   ```bash
   test -f scripts/loops/{name}/prompt.md && echo "Prompt exists" || echo "ERROR: Missing prompt.md"
   ```

5. **Template variables are correct**
   - `${SESSION}` or `${SESSION_NAME}` - session identifier
   - `${ITERATION}` - current iteration (1-based)
   - `${PROGRESS_FILE}` or `${PROGRESS}` - path to progress file
   - No undefined variables like `${UNDEFINED}`

6. **Plateau loops have required output format**
   - Prompt must instruct agent to output `PLATEAU: true/false`
   - Prompt must instruct agent to output `REASONING: ...`

### For Pipelines (scripts/pipelines/{name}.yaml)

1. **YAML syntax**
   ```bash
   cat scripts/pipelines/{name}.yaml | python3 -c "import sys,yaml; yaml.safe_load(sys.stdin)"
   ```

2. **Required fields**
   - `name` - pipeline identifier
   - `stages` - array of stage definitions

3. **Each stage has required fields**
   - `name` - stage identifier
   - `loop` OR inline `prompt` - what to run
   - `runs` - number of iterations

4. **Referenced loops exist**
   ```bash
   # For each stage with loop: X, verify:
   test -d scripts/loops/X && echo "Loop X exists" || echo "ERROR: Loop X not found"
   ```

5. **Variable flow is correct**
   - Later stages can use `${INPUTS}` to get previous stage output
   - Named references `${INPUTS.stage-name}` must reference existing stage names

## Report Format

Output a validation report:

```
## Validation Report: {name}

### Status: PASS / FAIL

### Checks Performed
- [ ] YAML syntax valid
- [ ] Required fields present
- [ ] Completion strategy properly configured
- [ ] Template variables correct
- [ ] Referenced loops exist (for pipelines)
- [ ] Output parsing configured (for plateau loops)

### Issues Found
{List any problems, or "None"}

### Recommendations
{Suggestions for improvement, or "Configuration looks good"}
```

</verification_protocol>

## Quick Reference

**Loop types location:** `scripts/loops/{name}/`
- `loop.yaml` - configuration
- `prompt.md` - what agent does each iteration

**Pipeline location:** `scripts/pipelines/{name}.yaml`

**Run commands:**
```bash
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
