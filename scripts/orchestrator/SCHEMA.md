# Pipeline Schema Reference

This document defines the YAML schema for pipeline definitions.

## Pipeline Structure

```yaml
# Required: Pipeline identifier
name: my-pipeline

# Optional: Human-readable description
description: What this pipeline does

# Optional: Schema version (default: 1)
version: 1

# Optional: Default settings for all stages
defaults:
  provider: claude-code    # claude-code, codex, gemini
  model: sonnet            # Provider-specific model name

# Required: List of stages to execute
stages:
  - name: stage-name       # Required: Unique identifier
    description: ...       # Optional: What this stage does
    runs: 1                # Optional: How many times to run (default: 1)
    model: opus            # Optional: Override default model
    provider: claude-code  # Optional: Override default provider
    completion: plateau    # Optional: Early-stop strategy
    parallel: false        # Optional: Run iterations in parallel
    perspectives: []       # Optional: Array of values for ${PERSPECTIVE}
    prompt: |              # Required: The prompt template
      Your instructions here...
```

## Variables

Use these in your prompts - they're resolved at runtime:

| Variable | Description | Example |
|----------|-------------|---------|
| `${SESSION}` | Pipeline session name | `review-20250110-1423` |
| `${INDEX}` | Current run index (0-based) | `0`, `1`, `2` |
| `${PERSPECTIVE}` | Current item from perspectives array | `security` |
| `${OUTPUT}` | Path to write this run's output | `.claude/pipeline-runs/.../run-0.md` |
| `${PROGRESS}` | Path to accumulating progress file | `.claude/pipeline-runs/.../progress.md` |
| `${INPUTS.stage-name}` | All outputs from named stage | File contents |
| `${INPUTS}` | Outputs from previous stage | File contents |

## Completion Strategies

- **none** (default): Run exactly `runs` times
- **plateau**: Stop when 2 consecutive runs output `PLATEAU: true`
- **beads-empty**: Stop when `bd ready --label=loop/${SESSION}` returns 0

## Providers

| Provider | CLI | Models |
|----------|-----|--------|
| `claude-code` | `claude` | opus, sonnet, haiku |
| `codex` | `codex` | o3, o3-mini, gpt-4o |
| `gemini` | `gemini` | flash, pro |

## Examples

### Simple One-Shot

```yaml
name: analyze
stages:
  - name: analyze
    runs: 1
    prompt: |
      Analyze the codebase structure.
      Write findings to ${OUTPUT}
```

### Fan-Out and Fan-In

```yaml
name: multi-review
stages:
  - name: review
    runs: 4
    parallel: true
    perspectives:
      - security
      - performance
      - maintainability
      - testing
    prompt: |
      Review from ${PERSPECTIVE} perspective.
      Write to ${OUTPUT}

  - name: synthesize
    runs: 1
    prompt: |
      Combine all reviews:
      ${INPUTS.review}

      Write synthesis to ${OUTPUT}
```

### Iterative Refinement

```yaml
name: refine-doc
stages:
  - name: improve
    runs: 10
    completion: plateau
    prompt: |
      Read the document and improve it.

      Previous progress: ${PROGRESS}

      Make improvements and update ${PROGRESS}.

      PLATEAU: true/false
      REASONING: why
```

## Output Structure

After running a pipeline, outputs are in:

```
.claude/pipeline-runs/{session}/
├── pipeline.yaml          # Copy of pipeline definition
├── state.json             # Execution state
├── stage-1-{name}/
│   ├── output.md          # Single run output
│   └── progress.md        # If using ${PROGRESS}
├── stage-2-{name}/
│   ├── run-0.md           # Multiple run outputs
│   ├── run-1.md
│   └── ...
└── ...
```
