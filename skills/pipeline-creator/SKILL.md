---
name: pipeline-creator
description: Create pipeline files from architecture specs. Takes confirmed specs from pipeline-designer and produces working stage.yaml, prompt.md, and pipeline.yaml files.
---

## What This Skill Does

Takes an architecture specification and creates all necessary files:
- New stages in `scripts/stages/{name}/`
- Pipeline configs in `scripts/pipelines/{name}.yaml`
- Validates everything with lint and dry-run

## Trigger Modes

1. **Chained from pipeline-designer:** Receives spec path automatically
2. **Direct invocation:** "Create this pipeline: [spec]" or "Build from spec at [path]"
3. **Natural detection:** When user provides a complete specification

## Intake

If no spec provided, ask for it:

```json
{
  "questions": [{
    "question": "How would you like to provide the pipeline specification?",
    "header": "Spec Source",
    "options": [
      {"label": "From file", "description": "I have a spec saved (e.g., .claude/pipeline-specs/*.yaml)"},
      {"label": "Describe it", "description": "I'll describe what I want"}
    ],
    "multiSelect": false
  }]
}
```

If "Describe it", redirect to pipeline-designer for proper design first.

## Workflow

```
Step 1: RECEIVE SPEC
├─ From designer (chained)
├─ From user (direct path)
└─ From file (user provides path)

Step 2: STAGE CREATION (Parallel Subagents)
For each stage where exists: false
├─ Spawn Stage Creator Agent
└─ Wait for all to complete

Step 3: PIPELINE ASSEMBLY
├─ Create pipeline.yaml (if multi-stage)
├─ Run lint validation
├─ Run dry-run preview
└─ Return execution command
```

Read `workflows/create.md` for detailed steps.

## Subagents

This skill uses two subagents defined in `.claude/agents/`:

### stage-creator

Defined at `.claude/agents/stage-creator.md`.

Invoke for each new stage (parallel):
```
Task(
  subagent_type="stage-creator",
  description="Create stage: {name}",
  prompt="Create stage with specification:\n\nname: {name}\ndescription: {desc}\ntermination:\n  type: {type}\nprovider: {provider}\nmodel: {model}"
)
```

Produces:
- `scripts/stages/{name}/stage.yaml`
- `scripts/stages/{name}/prompt.md`

### pipeline-assembler

Defined at `.claude/agents/pipeline-assembler.md`.

Invoke for multi-stage pipelines:
```
Task(
  subagent_type="pipeline-assembler",
  description="Assemble pipeline config",
  prompt="Create pipeline from spec:\n{spec_yaml}\n\nAvailable stages:\n{stages}"
)
```

Produces:
- `scripts/pipelines/{name}.yaml`

## Validation

All generated configs must pass:

```bash
# For each new stage
./scripts/run.sh lint loop {stage-name}

# For the pipeline
./scripts/run.sh lint pipeline {name}.yaml

# Dry-run preview
./scripts/run.sh dry-run pipeline {name}.yaml preview
```

## Output

When complete, present:

```markdown
## Pipeline Created

**Files created:**
- scripts/stages/{new-stage}/stage.yaml
- scripts/stages/{new-stage}/prompt.md
- scripts/pipelines/{name}.yaml

**Validation:** All lint checks passed

**Run it:**
```bash
./scripts/run.sh pipeline {name}.yaml {session-name}
```
```

## Quick Reference

```bash
# Check what stages exist
ls scripts/stages/

# Validate a stage
./scripts/run.sh lint loop {stage-name}

# Validate a pipeline
./scripts/run.sh lint pipeline {name}.yaml

# Dry-run preview
./scripts/run.sh dry-run pipeline {name}.yaml preview
```

## References Index

| Reference | Purpose |
|-----------|---------|
| references/variables.md | Template variable reference |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| create.md | Full creation workflow |

## Success Criteria

- [ ] Spec received (from designer or direct)
- [ ] Stage creator agents spawned for new stages
- [ ] All stages created successfully
- [ ] Pipeline.yaml created (if multi-stage)
- [ ] All lint checks passed
- [ ] Dry-run shows expected behavior
- [ ] Execution command provided to user
