# Pipeline Schema Reference

This document defines the YAML schema for pipeline definitions.

## Pipeline Structure

```yaml
# Required: Pipeline identifier
name: my-pipeline

# Optional: Human-readable description
description: What this pipeline does

# Optional: Commands passed to all stages (agents access via context.json)
commands:
  test: "npm test"
  lint: "npm run lint"
  format: "npm run format"
  types: "npm run typecheck"

# Required: List of stages to execute
stages:
  - name: stage-name       # Required: Unique identifier
    stage: improve-plan    # Required: Stage type from scripts/stages/
    description: ...       # Optional: What this stage does
    provider: claude       # Optional: claude or codex (default: claude)
    model: opus            # Optional: Provider-specific model
    context: |             # Optional: Injected into prompt as ${CONTEXT}
      Custom instructions for this stage instance
    termination:           # Optional: Override stage.yaml termination
      type: judgment       # queue, judgment, or fixed
      consensus: 2         # For judgment: consecutive stops needed
      max: 5               # Optional: hard cap on iterations
    inputs:                # Optional: Wire outputs from other stages
      from_initial: true   # Pass CLI --input files
      from_stage: plan     # Outputs from named previous stage
```

## Template Variables

Use these in prompt templates - resolved at runtime:

### V3 Variables (Preferred)

| Variable | Description | Example |
|----------|-------------|---------|
| `${CTX}` | Path to context.json with full context | `.claude/pipeline-runs/.../context.json` |
| `${STATUS}` | Path to write status.json | `.claude/pipeline-runs/.../status.json` |
| `${PROGRESS}` | Path to progress file | `.claude/pipeline-runs/.../progress.md` |
| `${ITERATION}` | Current iteration (1-based) | `1`, `2`, `3` |
| `${SESSION_NAME}` | Pipeline session name | `review-20250110` |
| `${CONTEXT}` | Optional context injection | `Focus on auth module...` |
| `${OUTPUT}` | Path for direct output | `.claude/pipeline-runs/.../output.md` |

### Legacy Variables (Deprecated)

| Variable | Maps To |
|----------|---------|
| `${SESSION}` | `${SESSION_NAME}` |
| `${INDEX}` | `${ITERATION} - 1` (0-based) |
| `${PROGRESS_FILE}` | `${PROGRESS}` |

## Inter-Stage Inputs

Pass outputs between stages using the `inputs` config:

```yaml
stages:
  - name: plan
    stage: improve-plan
    termination:
      type: judgment
      consensus: 2
      max: 5

  - name: implement
    stage: ralph
    termination:
      type: fixed
      iterations: 10
    inputs:
      from_initial: true     # Pass CLI --input files
      from_stage: plan       # Outputs from "plan" stage
```

Agents access inputs via `context.json`:

```bash
# Read initial inputs (from --input CLI flag)
jq -r '.inputs.from_initial[]' ${CTX} | xargs cat

# Read previous stage outputs
jq -r '.inputs.from_stage.plan[]' ${CTX} | xargs cat

# Read this stage's previous iterations
jq -r '.inputs.from_previous_iterations[]' ${CTX} | xargs cat
```

## Parallel Blocks

Run multiple providers concurrently with isolated contexts:

```yaml
stages:
  - name: setup
    stage: improve-plan
    termination:
      type: fixed
      iterations: 1

  - name: dual-review
    parallel:
      providers: [claude, codex]
      stages:
        - name: analyze
          stage: code-review
          termination:
            type: fixed
            iterations: 1
        - name: refine
          stage: improve-plan
          termination:
            type: judgment
            consensus: 2
            max: 5

  - name: synthesize
    stage: elegance
    inputs:
      from_parallel: refine  # Read outputs from all providers
```

### Parallel Block Behavior

- Each provider has isolated progress and state (no cross-provider visibility)
- Stages within a block run sequentially per provider
- Providers execute concurrently (parallel)
- Block waits for all providers before proceeding
- Any provider failure fails the entire block

### Parallel Input Options

```yaml
# Short form - gets all providers' outputs
inputs:
  from_parallel: refine

# Full form with options
inputs:
  from_parallel:
    stage: refine
    block: dual-review         # Optional if only one parallel block
    providers: [claude]        # Filter to subset (default: all)
    select: history            # "latest" (default) or "history" (all iterations)
```

## Commands Passthrough

Pass project-specific commands to all stages:

```yaml
name: test-pipeline
commands:
  test: "npm test"
  lint: "npm run lint"
  types: "npm run typecheck"

stages:
  - name: implement
    stage: ralph
    ...
```

Agents access commands via `context.json`:

```bash
TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
$TEST_CMD
```

## Termination Strategies

| Type | How It Works | Config |
|------|--------------|--------|
| `queue` | Checks external queue (`bd ready`) is empty | (no extra config) |
| `judgment` | N consecutive agents write `decision: stop` | `consensus`, `max` |
| `fixed` | Run exactly N iterations | `iterations` |

## Providers

| Provider | Aliases | Models |
|----------|---------|--------|
| `claude` | `claude-code`, `anthropic` | opus, sonnet, haiku |
| `codex` | `openai` | gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.1-codex-mini |

**Override at runtime:**
```bash
./scripts/run.sh pipeline my-pipeline.yaml session --provider=codex --model=o3
CLAUDE_PIPELINE_PROVIDER=codex ./scripts/run.sh pipeline my-pipeline.yaml session
```

## Examples

### Simple Refinement Pipeline

```yaml
name: full-refine
description: Refine plan then tasks

stages:
  - name: plan
    stage: improve-plan
    termination:
      type: judgment
      consensus: 2
      max: 5

  - name: tasks
    stage: refine-tasks
    termination:
      type: judgment
      consensus: 2
      max: 5
    inputs:
      from_stage: plan
```

### Pipeline with Commands

```yaml
name: test-fix
description: Fix failing tests
commands:
  test: "npm test"
  lint: "npm run lint"

stages:
  - name: fix
    stage: ralph
    termination:
      type: fixed
      iterations: 10
```

### Parallel Provider Comparison

```yaml
name: dual-refine
description: Compare Claude and Codex refinements

stages:
  - name: compare
    parallel:
      providers: [claude, codex]
      stages:
        - name: refine
          stage: improve-plan
          termination:
            type: judgment
            consensus: 2
            max: 5

  - name: merge
    stage: elegance
    inputs:
      from_parallel: refine
```

## Output Structure

After running a pipeline, outputs are in:

```
.claude/pipeline-runs/{session}/
├── state.json                    # Engine state
├── progress-{session}.md         # Accumulated context
├── stage-00-{name}/
│   ├── output.md
│   └── iterations/
│       ├── 001/
│       │   ├── status.json
│       │   └── output.md
│       └── ...
├── parallel-01-{name}/           # Parallel block
│   ├── manifest.json             # Aggregated outputs
│   ├── resume.json               # Crash recovery hints
│   └── providers/
│       ├── claude/
│       │   ├── progress.md
│       │   └── stage-00-{name}/iterations/...
│       └── codex/...
└── stage-02-{name}/              # Post-parallel stage
```
