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
  prompt="Create stage with specification:\n\nname: {name}\ndescription: {desc}\ntermination:\n  type: {type}\nprovider: {provider}\nmodel: {model}\ncontext: {context}\ncommands:\n  test: {test_cmd}\n  lint: {lint_cmd}\ninputs:\n  from_initial: {from_initial}\n  from_stage: {from_stage}\n  from_parallel: {from_parallel}"
)
```

**Stage specification format:**
```yaml
name: stage-name
description: What this stage does
termination:
  type: queue | judgment | fixed
  min_iterations: N
  consensus: N
  max_iterations: N
provider: claude | codex
model: opus | sonnet | haiku | gpt-5.2-codex | gpt-5.1-codex-max | gpt-5.1-codex-mini
context: |
  Optional instructions injected into prompt as ${CONTEXT}
commands:
  test: "npm test"
  lint: "npm run lint"
  types: "npm run typecheck"
inputs:
  from_initial: true         # Pass CLI --input files
  from_stage: plan           # Outputs from named stage
  from_parallel: analyze     # Outputs from parallel block
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

**Pipeline specification format:**
```yaml
name: pipeline-name
description: What this pipeline does
commands:
  test: "npm test"
  lint: "npm run lint"
stages:
  - name: stage-name
    stage: improve-plan
    runs: 5
    inputs:
      from: previous-stage    # Wire outputs between stages
      select: latest          # "latest" (default) or "history"

  # Parallel block: run multiple providers concurrently
  - name: dual-review
    parallel:
      providers: [claude, codex]
      stages:
        - name: analyze
          stage: code-review
          termination:
            type: fixed
            iterations: 1

  # Post-parallel stage: consume parallel outputs
  - name: synthesize
    stage: elegance
    inputs:
      from_parallel: analyze  # Gets outputs from all parallel providers
```

Produces:
- `scripts/pipelines/{name}.yaml`

## Provider/Model Options

| Provider | Models | Best For |
|----------|--------|----------|
| **claude** | opus, sonnet, haiku | General coding, nuanced judgment |
| **codex** | gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.1-codex-mini | Code generation, agentic tasks |

### Codex Reasoning Effort

Codex supports `model_reasoning_effort` to control thinking depth:

| Level | Use Case |
|-------|----------|
| `minimal` | Simple tasks, fastest |
| `low` | Straightforward code |
| `medium` | **Recommended daily driver** |
| `high` | Complex tasks (default) |
| `xhigh` | Maximum reasoning, slowest |

Set via `CODEX_REASONING_EFFORT` environment variable.

**Guidance:** Reserve `xhigh` for 1-2 iteration tasks (plan synthesis, task creation). For 5+ iteration loops, use `medium` or `high`—xhigh cost/latency adds up fast.

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
