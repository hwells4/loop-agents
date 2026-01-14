# Workflow: Create Pipeline

Create all files for a pipeline from an architecture specification.

## Step 1: Receive Specification

### From Pipeline Designer (Chained)

Spec is passed automatically via skill args:
```
Skill args: .claude/pipeline-specs/{name}.yaml
```

Load and parse:
```bash
cat .claude/pipeline-specs/{name}.yaml
```

### Direct Invocation

If user provides a path:
```bash
cat {user-provided-path}
```

If user describes inline, parse their YAML directly.

### Validate Spec Structure

Ensure spec contains:
- `name`: Pipeline name
- `stages`: Array of stage definitions
- Each stage has: `name`, `description`, `exists`, `termination`
- Optional: `provider` (claude or codex), `model` (provider-specific), `context`, `commands`, `inputs`

If invalid, report what's missing and stop.

## Step 2: Identify Work

Parse the stages and categorize:

```markdown
## Stages to Create

### Already Exist (reuse)
- {stage-name}: scripts/stages/{stage}/

### Need Creation
- {stage-name}: New stage required
```

Verify existing stages actually exist:
```bash
for stage in {list-of-exists-true}; do
  test -d "scripts/stages/$stage" && echo "OK: $stage" || echo "MISSING: $stage"
done
```

If a stage marked `exists: true` is missing, ask user how to proceed.

## Step 3: Create New Stages (Parallel)

For each stage where `exists: false`, spawn the `stage-creator` subagent.

**IMPORTANT:** Spawn all agents in parallel for efficiency.

The subagent is defined at `.claude/agents/stage-creator.md`.

### Prepare Stage Spec

For each new stage, extract:
```yaml
name: {stage-name}
description: {stage-description}
provider: {claude|codex}  # optional, defaults to claude
model: {opus|sonnet|haiku|o3|o3-mini|o4-mini|gpt-5.2-codex|gpt-5-codex}  # optional, provider-specific
termination:
  type: {queue|judgment|fixed}
  min_iterations: {N}
  consensus: {N}
context: {text}  # optional, injected into ${CONTEXT} variable
commands:  # optional, project-specific validation commands
  test: {command}
  lint: {command}
  format: {command}
  types: {command}
  build: {command}
inputs:  # optional, for multi-stage pipelines
  from: {previous-stage-name}
  select: {latest|all}
```

### Spawn Agents (Parallel)

Spawn all stage creators in a single message with multiple Task tool calls:

```
Task(
  subagent_type="stage-creator",
  description="Create stage: {stage-name}",
  prompt="""
Create stage with specification:

name: {stage-name}
description: {stage-description}
provider: {claude|codex}  # if specified
model: {opus|sonnet|haiku|o3|o3-mini|o4-mini|gpt-5.2-codex|gpt-5-codex}  # if specified
termination:
  type: {queue|judgment|fixed}
  min_iterations: {N}
  consensus: {N}
context: {text}  # if specified
commands:  # if specified
  test: {command}
  lint: {command}
  format: {command}
  types: {command}
  build: {command}
inputs:  # if specified
  from: {previous-stage-name}
  select: {latest|all}
"""
)
```

For multiple stages, invoke multiple Task calls in parallel (same message).

### Wait and Collect Results

All agents must complete successfully.

For each completed agent, verify files exist:
```bash
test -f scripts/stages/{stage}/stage.yaml && echo "OK" || echo "MISSING"
test -f scripts/stages/{stage}/prompt.md && echo "OK" || echo "MISSING"
```

If any failed, report the error and stop.

## Step 4: Validate Each Stage

Run lint for each new stage:

```bash
for stage in {new-stages}; do
  ./scripts/run.sh lint loop $stage
done
```

If any fail:
1. Show the lint errors
2. Ask user: fix manually or re-run agent?

## Step 5: Create Pipeline Configuration

### For Single-Stage

No pipeline.yaml needed. The stage IS the pipeline.

Skip to Step 6.

### For Multi-Stage

Spawn the `pipeline-assembler` subagent.

The subagent is defined at `.claude/agents/pipeline-assembler.md`.

```
Task(
  subagent_type="pipeline-assembler",
  description="Assemble pipeline config",
  prompt="""
Create pipeline from this architecture spec:

{full_spec_yaml}

Available stages:
- Existing: {list existing stages}
- Newly created: {list new stages}
"""
)
```

The agent produces `scripts/pipelines/{name}.yaml`.

## Step 6: Validate Pipeline

```bash
./scripts/run.sh lint pipeline {name}.yaml
```

If fails, show errors and attempt to fix.

## Step 7: Dry-Run Preview

```bash
./scripts/run.sh dry-run pipeline {name}.yaml preview
```

Show the output to user:
```markdown
## Dry-Run Preview

```
{dry-run output}
```
```

## Step 8: Present Results

### For Single-Stage

```markdown
## Stage Created

**Files:**
- `scripts/stages/{name}/stage.yaml`
- `scripts/stages/{name}/prompt.md`

**Lint:** PASSED

**Run it:**
```bash
./scripts/run.sh {name} {session-name} {max-iterations}
```

**Example:**
```bash
./scripts/run.sh {name} my-session 10
```
```

### For Multi-Stage

```markdown
## Pipeline Created

**New Stages:**
- `scripts/stages/{stage1}/` (stage.yaml, prompt.md)
- `scripts/stages/{stage2}/` (stage.yaml, prompt.md)

**Pipeline:**
- `scripts/pipelines/{name}.yaml`

**Lint:** All stages passed
**Dry-run:** Shows correct stage sequence

**Run it:**
```bash
./scripts/run.sh pipeline {name}.yaml {session-name}
```

**Example:**
```bash
./scripts/run.sh pipeline {name}.yaml my-feature
```
```

## Error Handling

### Stage Creation Failed

```markdown
## Error: Stage Creation Failed

Stage `{name}` failed to create:
{error details}

**Options:**
1. Retry stage creation
2. Create manually and continue
3. Abort pipeline creation
```

### Lint Failed

```markdown
## Error: Lint Failed

Stage `{name}` has validation errors:
```
{lint output}
```

**Common fixes:**
- Check termination type is valid
- Ensure prompt.md has status.json template
- Verify template variables use ${} syntax
```

### Dry-Run Failed

```markdown
## Warning: Dry-Run Issues

Dry-run showed potential issues:
```
{dry-run output}
```

Pipeline was created but may need adjustment.
```

## Success Criteria

- [ ] Spec loaded and validated
- [ ] Existing stages verified
- [ ] New stages created via parallel agents
- [ ] All stages pass lint
- [ ] Pipeline.yaml created (if multi-stage)
- [ ] Pipeline passes lint
- [ ] Dry-run shows expected behavior
- [ ] Execution command provided
