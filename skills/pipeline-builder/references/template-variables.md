# Template Variables Reference

All prompt templates (prompt.md files and inline pipeline prompts) support variable substitution using `${VARIABLE}` syntax.

## Available Variables

### Session & Iteration

| Variable | Description | Example |
|----------|-------------|---------|
| `${SESSION}` | Session name | `auth-feature` |
| `${SESSION_NAME}` | Same as SESSION | `auth-feature` |
| `${ITERATION}` | Current iteration, 1-based | `1`, `2`, `3` |
| `${INDEX}` | Current iteration, 0-based | `0`, `1`, `2` |

### Files & Paths

| Variable | Description | Example |
|----------|-------------|---------|
| `${PROGRESS}` | Path to progress file | `.claude/loop-progress/progress-auth.txt` |
| `${PROGRESS_FILE}` | Same as PROGRESS | `.claude/loop-progress/progress-auth.txt` |
| `${OUTPUT}` | Path to write output (pipelines) | `.claude/pipeline-runs/session/stage-1/output.md` |

### Pipeline-Specific

| Variable | Description | Example |
|----------|-------------|---------|
| `${INPUTS}` | Outputs from previous stage | Contents of previous stage output files |
| `${INPUTS.stage-name}` | Outputs from named stage | Contents of specific stage output files |
| `${PERSPECTIVE}` | Current perspective (fan-out) | `"security engineer"` |

## Usage in Prompts

### Basic Usage

```markdown
# My Agent

Session: ${SESSION_NAME}
Iteration: ${ITERATION}

Read the progress file:
```bash
cat ${PROGRESS_FILE}
```
```

### Pipeline Stage with Inputs

```markdown
# Synthesis Agent

Previous stage outputs:
${INPUTS}

Your task: Synthesize these into a coherent summary.

Write your output to:
${OUTPUT}
```

### Named Stage References

```markdown
# Final Review

Planning phase results:
${INPUTS.planning}

Implementation phase results:
${INPUTS.implementation}

Create final report.
```

### Using Perspectives

```markdown
# Multi-Perspective Review

You are reviewing this code as a ${PERSPECTIVE}.

Focus on issues relevant to your expertise.
```

## Variable Resolution

Variables are resolved at runtime by `scripts/lib/resolve.sh`. The resolution happens:

1. **Before** the prompt is sent to Claude
2. **Each iteration** gets fresh resolution
3. **Missing variables** result in empty strings (no errors)

## Tips

1. **Always use braces**: `${SESSION}` not `$SESSION`
2. **Case sensitive**: `${SESSION}` works, `${session}` does not
3. **Check spelling**: Typos like `${SESION}` will not be caught
4. **Progress files accumulate**: Each iteration should append, not overwrite
5. **Iteration is 1-based**: First iteration is `${ITERATION}` = 1
