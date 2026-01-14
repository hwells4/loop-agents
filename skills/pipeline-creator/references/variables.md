# Template Variables Reference

Complete reference for variables available in prompt templates.

## V3 Variables (Preferred)

Use these in all new stage prompts.

| Variable | Type | Description |
|----------|------|-------------|
| `${CTX}` | Path | Path to context.json with full session metadata |
| `${STATUS}` | Path | Path where agent writes status.json |
| `${PROGRESS}` | Path | Path to progress file (accumulated context) |
| `${ITERATION}` | Number | Current iteration (1-based) |
| `${SESSION_NAME}` | String | Session identifier |
| `${CONTEXT}` | Text | Optional context injection (from CLI/env/config) |
| `${OUTPUT}` | Path | Path to write output (multi-stage pipelines) |

## Legacy Variables (Deprecated)

Still work for backwards compatibility but prefer V3 variables.

| Legacy | Maps To | Notes |
|--------|---------|-------|
| `${SESSION}` | `${SESSION_NAME}` | Renamed for clarity |
| `${INDEX}` | `${ITERATION} - 1` | 0-based vs 1-based |
| `${PROGRESS_FILE}` | `${PROGRESS}` | Shortened |

**Note:** `${INPUTS}` is deprecated. Use `context.json` inputs object instead.

## context.json Structure

Available at `${CTX}`:

```json
{
  "session": "auth-refactor",
  "pipeline": "refine",
  "stage": {
    "id": "improve-plan",
    "index": 0,
    "template": "improve-plan"
  },
  "iteration": 5,
  "paths": {
    "session_dir": ".claude/pipeline-runs/auth-refactor",
    "stage_dir": ".claude/pipeline-runs/auth-refactor/stage-00-improve-plan",
    "progress": ".claude/pipeline-runs/auth-refactor/progress-auth-refactor.md",
    "status": ".claude/pipeline-runs/auth-refactor/stage-00-improve-plan/iterations/005/status.json",
    "output": ".claude/pipeline-runs/auth-refactor/stage-00-improve-plan/iterations/005/output.md"
  },
  "inputs": {
    "from_initial": ["docs/plans/auth.md"],
    "from_stage": {
      "plan": [".claude/pipeline-runs/auth-refactor/stage-00-plan/iterations/003/output.md"]
    },
    "from_parallel": {
      "claude": ["parallel-01-review/providers/claude/iterations/001/output.md"],
      "codex": ["parallel-01-review/providers/codex/iterations/001/output.md"]
    },
    "from_previous_iterations": [
      "iterations/001/output.md",
      "iterations/002/output.md"
    ]
  },
  "commands": {
    "test": "npm test",
    "lint": "npm run lint",
    "format": "npm run format",
    "types": "npm run typecheck"
  },
  "limits": {
    "max_iterations": 25,
    "remaining_seconds": -1
  }
}
```

### Input Types

| Field | Description |
|-------|-------------|
| `from_initial` | Files passed via `--input` CLI flag |
| `from_stage` | Outputs from named previous stages |
| `from_parallel` | Outputs from parallel block providers |
| `from_previous_iterations` | This stage's prior iteration outputs |

### Commands Passthrough

The `commands` object passes project-specific commands from pipeline config:

```yaml
# In pipeline.yaml
commands:
  test: "npm test"
  lint: "npm run lint"
  format: "npm run format"
  types: "npm run typecheck"
```

Agents access via:
```bash
TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
$TEST_CMD
```

## status.json Format

Agent writes to `${STATUS}`:

```json
{
  "decision": "continue | stop | error",
  "reason": "Why this decision was made",
  "summary": "What happened this iteration",
  "work": {
    "items_completed": ["beads-001"],
    "files_touched": ["src/auth.ts"]
  },
  "errors": []
}
```

## Usage in Prompts

### Reading Context

```markdown
## Context

Read the full context:
```bash
cat ${CTX} | jq
```

Read the progress file:
```bash
cat ${PROGRESS}
```
```

### Reading Inputs

```markdown
## Inputs

Read initial inputs (from `--input` CLI flag):
```bash
jq -r '.inputs.from_initial[]' ${CTX} | xargs cat
```

Read from a named previous stage:
```bash
jq -r '.inputs.from_stage.plan[]' ${CTX} | xargs cat
```

Read from parallel block providers:
```bash
jq -r '.inputs.from_parallel.claude[]' ${CTX} | xargs cat
```
```

### Using Commands Passthrough

```markdown
## Run Tests

Use the configured test command:
```bash
TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
$TEST_CMD
```
```

### Writing Status

```markdown
### Write Status

After completing your work, write to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "More work remains",
  "summary": "Completed X and Y",
  "work": {
    "items_completed": ["item-1"],
    "files_touched": ["file.ts"]
  },
  "errors": []
}
```
```

### Multi-Stage Input

```markdown
## Previous Stage Output

Read outputs from previous stages via context.json:
```bash
# Get outputs from named "plan" stage
jq -r '.inputs.from_stage.plan[]' ${CTX} | xargs cat

# Get outputs from parallel block providers
jq -r '.inputs.from_parallel | to_entries[] | .value[]' ${CTX} | xargs cat
```
```

## Common Patterns

### Check Iteration Number

```markdown
This is iteration ${ITERATION}.

Read what previous iterations found:
```bash
cat ${PROGRESS}
```
```

### Append to Progress

```markdown
## Output

Append your findings to the progress file:
```bash
echo "## Iteration ${ITERATION}" >> ${PROGRESS}
echo "" >> ${PROGRESS}
echo "Findings here..." >> ${PROGRESS}
```
```

### Error Handling

```markdown
If you encounter an error, write to `${STATUS}`:

```json
{
  "decision": "error",
  "reason": "Description of what went wrong",
  "summary": "Attempted X but failed because Y",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": ["Error message here"]
}
```
```

## Environment Variables (Override)

These env vars override stage/pipeline configuration without editing files:

| Variable | Purpose |
|----------|---------|
| `CLAUDE_PIPELINE_PROVIDER` | Override provider (claude, codex) |
| `CLAUDE_PIPELINE_MODEL` | Override model (opus, o3, etc.) |

CLI flags `--provider=X` and `--model=X` take precedence over env vars.

**Precedence:** CLI flags → Env vars → Stage config → Built-in defaults

## Variable Resolution

The engine resolves variables before passing to Claude:

1. `${CTX}` → `.claude/pipeline-runs/session/context.json`
2. `${STATUS}` → `.claude/pipeline-runs/session/iterations/NNN/status.json`
3. `${PROGRESS}` → `.claude/pipeline-runs/session/progress-session.md`
4. `${ITERATION}` → `5` (number)
5. `${SESSION_NAME}` → `session` (string)

Variables are replaced literally in the prompt text.
