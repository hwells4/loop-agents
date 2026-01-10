# Pipeline Configuration Reference

Pipelines chain multiple loops together in sequence. Each stage can:
- Reference an existing loop type
- Define an inline prompt for custom behavior
- Pass outputs to subsequent stages

## File Location

Pipelines live in `scripts/pipelines/{name}.yaml`

## Basic Structure

```yaml
name: my-pipeline
description: What this pipeline accomplishes

stages:
  - name: stage-one
    loop: improve-plan    # Reference existing loop
    runs: 5               # Number of iterations

  - name: stage-two
    loop: refine-beads
    runs: 5
```

## Stage Configuration

### Using Existing Loops

```yaml
stages:
  - name: planning
    loop: improve-plan     # References scripts/loops/improve-plan/
    runs: 5
    model: opus            # Override loop's default model
```

### Inline Custom Prompt

For one-off stages that don't need a reusable loop:

```yaml
stages:
  - name: synthesize
    runs: 1
    prompt: |
      Previous stage outputs:
      ${INPUTS}

      Synthesize these into a single coherent document.
      Write to: ${OUTPUT}
    completion: fixed-n    # Must specify for inline prompts
```

### Stage with Perspectives (Fan-out)

Run multiple parallel passes with different perspectives:

```yaml
stages:
  - name: multi-review
    loop: review-plan
    runs: 3
    perspectives:
      - "Review as a security engineer"
      - "Review as a UX designer"
      - "Review as a junior developer"
```

Each run gets `${PERSPECTIVE}` set to the corresponding value.

## Variable Flow Between Stages

### ${INPUTS} - Previous Stage Outputs

Later stages can access outputs from previous stages:

```yaml
stages:
  - name: stage-one
    loop: improve-plan
    runs: 3

  - name: stage-two
    runs: 1
    prompt: |
      Previous improvements:
      ${INPUTS}

      Now synthesize these changes.
```

`${INPUTS}` contains the content of all output files from the previous stage.

### ${INPUTS.stage-name} - Named Stage Reference

Reference a specific stage by name:

```yaml
stages:
  - name: planning
    loop: improve-plan
    runs: 3

  - name: beads
    loop: refine-beads
    runs: 3

  - name: final
    runs: 1
    prompt: |
      Plan from planning stage:
      ${INPUTS.planning}

      Beads from beads stage:
      ${INPUTS.beads}

      Create final summary.
```

## Complete Examples

### Simple Two-Stage Pipeline

```yaml
name: quick-refine
description: Quick planning refinement

stages:
  - name: improve-plan
    loop: improve-plan
    runs: 3

  - name: refine-beads
    loop: refine-beads
    runs: 3
```

### Multi-Stage with Synthesis

```yaml
name: deep-analysis
description: Analyze from multiple perspectives, then synthesize

stages:
  - name: security-review
    loop: code-review
    runs: 3
    perspectives:
      - "security"

  - name: perf-review
    loop: code-review
    runs: 3
    perspectives:
      - "performance"

  - name: synthesize
    runs: 1
    prompt: |
      Security findings:
      ${INPUTS.security-review}

      Performance findings:
      ${INPUTS.perf-review}

      Create unified improvement plan.
      Write to: ${OUTPUT}
    completion: fixed-n
```

### Pipeline with Model Overrides

```yaml
name: cost-efficient
description: Use cheaper models where possible

stages:
  - name: draft
    loop: improve-plan
    runs: 5
    model: sonnet          # Cheaper for drafting

  - name: polish
    loop: improve-plan
    runs: 2
    model: opus            # Best quality for final pass
```

## Run Directory Structure

When a pipeline runs, it creates:

```
.claude/pipeline-runs/{session}/
├── pipeline.yaml          # Copy of pipeline config
├── state.json             # Pipeline state
├── stage-1-{name}/        # Each stage gets a directory
│   ├── progress.md
│   ├── output.md          # Single run output
│   └── run-0.md, run-1.md # Multiple run outputs
└── stage-2-{name}/
    └── ...
```
