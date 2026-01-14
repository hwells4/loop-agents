# Agent Pipelines - Feature Reference

This document provides a complete reference for all major features in Agent Pipelines. Use this to update skills, documentation, and architectural guidance.

---

# Part I: Provider System

## 1. Provider Abstraction

Agent Pipelines supports multiple AI agent providers through a unified abstraction layer. Each provider has its own CLI, models, and execution semantics, but the pipeline engine treats them uniformly.

### Supported Providers

| Provider | Aliases | CLI Tool | Default Model | Skip Permissions Flag |
|----------|---------|----------|---------------|-----------------------|
| Claude Code | `claude`, `claude-code`, `anthropic` | `claude` | `opus` | `--dangerously-skip-permissions` |
| Codex | `codex`, `openai` | `codex` | `gpt-5.2-codex` | `--dangerously-bypass-approvals-and-sandbox` |

### Provider Normalization

The `normalize_provider()` function in `scripts/lib/provider.sh` converts aliases to canonical names:

```bash
# These all resolve to "claude"
normalize_provider "claude"        # → claude
normalize_provider "claude-code"   # → claude
normalize_provider "anthropic"     # → claude

# These all resolve to "codex"
normalize_provider "codex"         # → codex
normalize_provider "openai"        # → codex
```

### Provider Configuration Hierarchy

Configuration can be set at multiple levels, with a clear precedence order:

**Precedence: CLI flags → Env vars → Pipeline config → Stage config → Built-in defaults**

```bash
# CLI flags (highest priority)
./scripts/run.sh ralph auth 25 --provider=codex --model=gpt-5.1-codex-max

# Environment variables
CLAUDE_PIPELINE_PROVIDER=codex ./scripts/run.sh ralph auth 25
CLAUDE_PIPELINE_MODEL=sonnet ./scripts/run.sh ralph auth 25

# Combined (CLI wins for provider, env wins for model)
CLAUDE_PIPELINE_MODEL=sonnet ./scripts/run.sh ralph auth 25 --provider=claude
```

### Stage Configuration

Set provider in `stage.yaml`:

```yaml
name: my-stage
description: Uses Codex for implementation

provider: codex                    # claude or codex (default: claude)
model: gpt-5.2-codex              # provider-specific model

termination:
  type: fixed
  iterations: 3
```

### Claude Models

| Model Name | Aliases | Description |
|------------|---------|-------------|
| `opus` | `claude-opus`, `opus-4`, `opus-4.5` | Most capable, best for complex tasks |
| `sonnet` | `claude-sonnet`, `sonnet-4` | Balanced capability and speed |
| `haiku` | `claude-haiku` | Fastest, best for simple tasks |

### Codex Models and Reasoning Effort

| Model Name | Description |
|------------|-------------|
| `gpt-5.2-codex` | Default, most capable Codex model |
| `gpt-5-codex` | Previous generation |
| `gpt-5.1-codex-max` | Frontier agentic model |
| `gpt-5.1-codex-mini` | Cost-effective model |
| `gpt-5-codex-mini` | Original mini model |

**Reasoning effort** controls how much "thinking" Codex does:

| Level | Use Case |
|-------|----------|
| `minimal` | Simple tasks, fastest |
| `low` | Straightforward code |
| `medium` | **Recommended daily driver** |
| `high` | Complex tasks (default) |
| `xhigh` | Maximum reasoning, slowest |

```bash
# Set via environment variable (default: high)
CODEX_REASONING_EFFORT=medium ./scripts/run.sh ralph my-session 25
CODEX_REASONING_EFFORT=xhigh ./scripts/run.sh ralph my-session 2  # Only for 1-2 iterations
```

**Guidance:** Reserve `xhigh` for 1-2 iteration tasks (plan synthesis, task creation). For 5+ iteration loops, use `medium` or `high`—xhigh cost/latency adds up fast.

### Provider Execution

The `execute_agent()` function provides a unified interface:

```bash
# Usage: execute_agent "$provider" "$prompt" "$model" "$output_file"
execute_agent "claude" "$prompt" "opus" "/tmp/output.txt"
execute_agent "codex" "$prompt" "gpt-5.2-codex" "/tmp/output.txt"
```

Under the hood, this calls provider-specific functions:
- `execute_claude()` - Pipes prompt to `claude --model $model --dangerously-skip-permissions`
- `execute_codex()` - Calls `codex exec` with model and reasoning effort

### Mock Mode for Testing

Set `MOCK_MODE=true` to skip real API calls:

```bash
MOCK_MODE=true ./scripts/run.sh ralph test-session 5
```

In mock mode:
- `execute_agent()` returns mock responses from `get_mock_response()`
- `write_mock_status()` creates appropriate `status.json`
- Provider-specific fixtures from `$MOCK_FIXTURES_DIR/{provider}/`

---

# Part II: Input System

## 2. Initial Inputs (Pipeline-Level)

Pipelines can specify input files that are available to all stages from the start.

### Pipeline YAML Configuration

```yaml
name: my-pipeline
description: Refine a plan

# Initial inputs: files available to all stages
inputs:
  - docs/plans/my-plan.md           # Single file
  - docs/research/*.md              # Glob pattern
  - docs/context/                   # Directory (all files)

stages:
  - name: refine
    stage: improve-plan
    runs: 5
```

### CLI Input Flag

```bash
# Single file
./scripts/run.sh pipeline my-pipeline.yaml my-session --input docs/plans/auth.md

# Multiple files (use flag multiple times)
./scripts/run.sh pipeline my-pipeline.yaml my-session \
  --input docs/plans/auth.md \
  --input docs/requirements.md

# Globs (quote to prevent shell expansion)
./scripts/run.sh pipeline my-pipeline.yaml my-session --input "docs/*.md"
```

### How Initial Inputs Work

1. On pipeline start, `run.sh` resolves all input paths to absolute paths
2. Creates `initial-inputs.json` in the run directory with array of paths
3. `context.sh` reads this file and includes in `context.json` as `inputs.from_initial`

### Accessing Initial Inputs in Prompts

Agents read initial inputs via `context.json`:

```bash
# Read initial input paths
jq -r '.inputs.from_initial[]' ${CTX}

# Read content of first initial input
cat "$(jq -r '.inputs.from_initial[0]' ${CTX})"
```

### File Format: initial-inputs.json

```json
[
  "/absolute/path/to/docs/plans/my-plan.md",
  "/absolute/path/to/docs/research/notes.md"
]
```

---

## 3. Inter-Stage Inputs (from/select)

Stages can consume outputs from previous stages in the pipeline.

### Basic Configuration

```yaml
stages:
  - name: plan
    stage: improve-plan
    runs: 3

  - name: implement
    stage: work
    runs: 10
    inputs:
      from: plan           # Reference previous stage by name
      select: latest       # "latest" (default) or "all"
```

### Select Modes

| Mode | Behavior |
|------|----------|
| `latest` | Only the final iteration's output (default) |
| `all` | All iterations' outputs as array |

### Example: Latest (Default)

```yaml
inputs:
  from: plan
  select: latest  # or omit entirely
```

Results in `context.json`:
```json
{
  "inputs": {
    "from_stage": {
      "plan": ["/path/to/stage-00-plan/iterations/003/output.md"]
    }
  }
}
```

### Example: All Iterations

```yaml
inputs:
  from: plan
  select: all
```

Results in `context.json`:
```json
{
  "inputs": {
    "from_stage": {
      "plan": [
        "/path/to/stage-00-plan/iterations/001/output.md",
        "/path/to/stage-00-plan/iterations/002/output.md",
        "/path/to/stage-00-plan/iterations/003/output.md"
      ]
    }
  }
}
```

### Accessing Stage Inputs in Prompts

```bash
# Get path to latest output from previous stage
jq -r '.inputs.from_stage.plan[0]' ${CTX}

# Read all outputs (when select: all)
for file in $(jq -r '.inputs.from_stage.plan[]' ${CTX}); do
  cat "$file"
done
```

---

## 4. Previous Iteration Inputs

Within a stage, each iteration can see outputs from its own previous iterations.

### Automatic Collection

The engine automatically populates `inputs.from_previous_iterations`:
- Iteration 1: empty array (no previous iterations)
- Iteration 2: contains iteration 1's output
- Iteration N: contains iterations 1 through N-1

### Context.json Structure

At iteration 3:
```json
{
  "inputs": {
    "from_previous_iterations": [
      "/path/to/iterations/001/output.md",
      "/path/to/iterations/002/output.md"
    ]
  }
}
```

### Accessing in Prompts

```bash
# Check if previous iterations exist
if [ "$(jq '.inputs.from_previous_iterations | length' ${CTX})" -gt 0 ]; then
  echo "Building on previous work:"
  for file in $(jq -r '.inputs.from_previous_iterations[]' ${CTX}); do
    cat "$file"
  done
fi
```

---

## 5. Complete Inputs Object

The full `inputs` object in `context.json`:

```json
{
  "inputs": {
    "from_initial": [
      "/path/to/initial/input1.md",
      "/path/to/initial/input2.md"
    ],
    "from_stage": {
      "previous-stage-name": [
        "/path/to/stage-00-prev/iterations/003/output.md"
      ]
    },
    "from_previous_iterations": [
      "/path/to/current-stage/iterations/001/output.md",
      "/path/to/current-stage/iterations/002/output.md"
    ],
    "from_parallel": {
      "stage": "refine",
      "block": "dual-provider",
      "providers": {
        "claude": { "output": "...", "history": [...] },
        "codex": { "output": "...", "history": [...] }
      }
    }
  }
}
```

---

# Part III: Context Injection

## 6. The ${CONTEXT} Variable

The `${CONTEXT}` template variable allows injecting arbitrary text into prompts at runtime.

### Use Cases

1. **Pass instructions from outer agent**: An agent spawning a pipeline can pass specific guidance
2. **Override default behavior**: Inject focus areas or constraints
3. **Runtime customization**: Same pipeline, different goals

### Configuration Hierarchy

**Precedence: CLI flag → Env var → Pipeline stage config → Stage.yaml**

### CLI Flag

```bash
./scripts/run.sh ralph my-session 25 --context="Focus on authentication bugs only"

./scripts/run.sh pipeline refine.yaml my-session \
  --context="Read docs/plans/auth-plan.md before starting"
```

### Environment Variable

```bash
CLAUDE_PIPELINE_CONTEXT="Prioritize test coverage" ./scripts/run.sh ralph my-session 25
```

### Pipeline Configuration

```yaml
name: focused-refine
stages:
  - name: plan
    stage: improve-plan
    runs: 3
    context: "Focus on security aspects of the design"
```

### Stage Configuration

```yaml
# In stage.yaml
name: my-stage
context: "Default context for this stage"
```

### Using in Prompts

In `prompt.md`, use the `${CONTEXT}` variable:

```markdown
# Your Task

${CONTEXT}

Read the progress file at ${PROGRESS} and continue working...
```

If `--context="Focus on error handling"` is passed, this resolves to:

```markdown
# Your Task

Focus on error handling

Read the progress file at /path/to/progress.md and continue working...
```

### Empty Context

If no context is configured, `${CONTEXT}` resolves to empty string. Design prompts to handle this gracefully:

```markdown
# Your Task

${CONTEXT}

## Default Instructions
If no specific focus was provided above, work on the highest priority items...
```

---

# Part IV: Commands Passthrough

## 7. Stage Commands

Stages can define commands that agents can use for validation, testing, formatting, etc.

### Philosophy

**Config says WHAT, prompt says WHY and WHEN.**

- Stage config defines available commands (declarative)
- Prompt instructs agent on semantics (when to run, required vs optional)

### Stage Configuration

```yaml
name: work
description: Implement tasks from queue

commands:
  test: "bundle exec rspec"
  format: "bundle exec rubocop -a"
  types: "bundle exec srb tc"
  lint: "bundle exec rubocop"
  build: "bundle exec rails assets:precompile"

termination:
  type: fixed
```

### Context.json Structure

Commands are passed through to `context.json`:

```json
{
  "commands": {
    "test": "bundle exec rspec",
    "format": "bundle exec rubocop -a",
    "types": "bundle exec srb tc",
    "lint": "bundle exec rubocop",
    "build": "bundle exec rails assets:precompile"
  }
}
```

### Accessing Commands in Prompts

```markdown
## Validation

After making changes, validate using available commands:

```bash
# Get test command
TEST_CMD=$(jq -r '.commands.test // ""' ${CTX})
if [ -n "$TEST_CMD" ]; then
  eval "$TEST_CMD"
fi
```

### Required vs Optional Commands

The prompt defines semantics:

```markdown
## Required Validation

You MUST run the test command after every change:
- Test: `$(jq -r '.commands.test' ${CTX})`

## Optional Validation

Run these if they exist and are relevant:
- Format: `$(jq -r '.commands.format // ""' ${CTX})`
- Types: `$(jq -r '.commands.types // ""' ${CTX})`
```

### Project-Specific Commands

Different projects can use the same stage with different commands:

```yaml
# Ruby project
commands:
  test: "bundle exec rspec"
  format: "bundle exec rubocop -a"

# Python project
commands:
  test: "pytest"
  format: "black ."

# Node project
commands:
  test: "npm test"
  format: "npm run format"
```

---

# Part V: Parallel Blocks

## 8. What Parallel Blocks Enable

Parallel blocks allow pipelines to run multiple AI providers (Claude, Codex, etc.) **concurrently** with **isolated contexts**, then merge their outputs for downstream consumption.

### Use Cases

1. **Compare approaches**: Get Claude and Codex to independently refine a plan, then synthesize the best ideas from both
2. **Ensemble refinement**: Run the same stage through multiple providers for diversity
3. **Provider-specific optimization**: Use Claude for creative tasks, Codex for code-heavy tasks, in parallel
4. **Fault tolerance**: If one provider struggles, others may succeed

### Key Properties

- **Isolation**: Each provider has its own `progress.md`, `state.json`, and iteration history. Providers cannot see each other's work within a block.
- **Concurrency**: Providers run in parallel subshells with separate PIDs
- **Sequential within provider**: Stages inside a block run sequentially for each provider
- **All-or-nothing**: Block waits for ALL providers to complete; any failure fails the entire block
- **Crash recovery**: Each provider tracks its own state; resume skips completed providers

---

## 9. Pipeline Schema for Parallel Blocks

### Basic Structure

```yaml
name: parallel-refine
description: Compare Claude and Codex refinements
stages:
  # Sequential stage (normal)
  - name: setup
    stage: improve-plan
    termination:
      type: fixed
      iterations: 1

  # Parallel block
  - name: dual-refine
    parallel:
      providers: [claude, codex]
      stages:
        - name: plan
          stage: improve-plan
          termination:
            type: fixed
            iterations: 1
        - name: iterate
          stage: improve-plan
          termination:
            type: judgment
            consensus: 2
            max: 5

  # Sequential stage that consumes parallel outputs
  - name: synthesize
    stage: elegance
    inputs:
      from_parallel: iterate
```

### Parallel Block Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Block name (used in directory naming and references) |
| `parallel` | Yes | Container for parallel configuration |
| `parallel.providers` | Yes | Array of provider names: `[claude, codex, gemini]` |
| `parallel.stages` | Yes | Array of stages to run for each provider |

### Stage Fields Within Parallel Block

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Stage name (must be unique within block) |
| `stage` | Yes | Reference to stage definition in `scripts/stages/` |
| `termination` | Yes | Termination config (`type`, `iterations`, `consensus`, `max`) |
| `provider` | **NO** | Cannot override provider inside block (controlled by block) |

### Validation Rules (from `validate.sh`)

1. **P012**: `parallel.providers` required and non-empty
2. **P013**: `parallel.stages` required and non-empty
3. **P014**: No nested parallel blocks allowed
4. **P015**: Stages inside block cannot override `provider`
5. **P016**: Stage names must be unique within block
6. **P017**: `from_parallel` must reference a stage that exists in a parallel block

---

## 10. Directory Structure

When a parallel block runs, it creates:

```
.claude/pipeline-runs/{session}/
├── stage-00-setup/                      # Sequential stage before block
│   └── iterations/001/
│       ├── context.json
│       ├── status.json
│       └── output.md
│
├── parallel-01-dual-refine/             # Parallel block (index 01, name dual-refine)
│   ├── manifest.json                    # Aggregated outputs for downstream stages
│   ├── resume.json                      # Per-provider crash recovery hints
│   └── providers/
│       ├── claude/
│       │   ├── progress.md              # Claude-isolated progress
│       │   ├── state.json               # Claude-specific state
│       │   ├── stage-00-plan/
│       │   │   └── iterations/001/
│       │   │       ├── context.json
│       │   │       ├── status.json
│       │   │       └── output.md
│       │   └── stage-01-iterate/
│       │       └── iterations/001/
│       │           └── ...
│       └── codex/
│           ├── progress.md              # Codex-isolated progress
│           ├── state.json               # Codex-specific state
│           ├── stage-00-plan/
│           │   └── iterations/001/
│           │       └── ...
│           └── stage-01-iterate/
│               └── iterations/001/
│                   └── ...
│
└── stage-02-synthesize/                 # Sequential stage after block
    └── iterations/001/
        └── ...
```

### Directory Naming

- Block directory: `parallel-{XX}-{name}` where XX is zero-padded stage index
- If no name provided: `parallel-{XX}` (auto-generated)
- Provider directories: `providers/{provider-name}/`
- Stage directories within provider: `stage-{XX}-{stage-name}/`

---

## 11. Downstream Consumption (`from_parallel`)

Stages after a parallel block can consume outputs from all or subset of providers.

### Shorthand Form

```yaml
# Gets all providers' outputs from the "iterate" stage
inputs:
  from_parallel: iterate
```

### Full Form

```yaml
inputs:
  from_parallel:
    stage: iterate              # Stage name within the parallel block
    block: dual-refine          # Block name (optional if only one parallel block)
    providers: [claude]         # Filter to subset (default: all providers)
    select: history             # "latest" (default) or "history" (all iterations)
```

### Options

| Field | Default | Description |
|-------|---------|-------------|
| `stage` | Required | Name of stage within parallel block |
| `block` | Auto | Block name (required if multiple parallel blocks exist) |
| `providers` | All | Array of providers to include; omit for all |
| `select` | `latest` | `latest` = final iteration only; `history` = all iterations |

### What Gets Injected into context.json

When a downstream stage has `from_parallel`, the generated `context.json` includes:

```json
{
  "inputs": {
    "from_parallel": {
      "stage": "iterate",
      "block": "dual-refine",
      "select": "latest",
      "manifest": "/path/to/manifest.json",
      "providers": {
        "claude": {
          "output": "/path/to/claude/stage-01-iterate/iterations/002/output.md",
          "status": "/path/to/claude/stage-01-iterate/iterations/002/status.json",
          "history": [
            "/path/to/claude/stage-01-iterate/iterations/001/output.md",
            "/path/to/claude/stage-01-iterate/iterations/002/output.md"
          ]
        },
        "codex": {
          "output": "/path/to/codex/stage-01-iterate/iterations/001/output.md",
          "status": "/path/to/codex/stage-01-iterate/iterations/001/status.json",
          "history": [
            "/path/to/codex/stage-01-iterate/iterations/001/output.md"
          ]
        }
      }
    }
  }
}
```

---

## 12. Provider Isolation Within Block

### How It Works

Each provider operates in complete isolation:

1. **Separate progress.md**: Each provider has its own accumulated context file
2. **Separate state.json**: Each provider tracks its own iteration count, stages completed, and status
3. **Scoped context generation**: When generating `context.json` for a stage inside a block, the `parallel_scope` restricts visibility

### parallel_scope in Context Generation

When generating context for a stage inside a parallel block:

```json
{
  "parallel_scope": {
    "scope_root": "/path/to/parallel-block/providers/claude",
    "pipeline_root": "/path/to/pipeline-run"
  }
}
```

- **scope_root**: Where to look first for inputs (provider's directory)
- **pipeline_root**: Fallback for inputs from stages outside the block

### Example: Stage Inside Block Reading Previous Stage

If `iterate` stage (inside block) has `inputs: { from: plan }`:

1. First looks in `scope_root` for `stage-*-plan`
2. Finds `providers/claude/stage-00-plan` → uses Claude's plan output
3. Does NOT see Codex's plan output

If the input references a stage outside the block (like `setup`):
1. Not found in `scope_root`
2. Falls back to `pipeline_root`
3. Finds `stage-00-setup` → uses shared setup output

---

## 13. Manifest File Format

After ALL providers complete successfully, `manifest.json` is written:

```json
{
  "block": {
    "name": "dual-refine",
    "index": 1
  },
  "stages": ["plan", "iterate"],
  "completed_at": "2026-01-13T21:30:00Z",
  "providers": {
    "claude": {
      "status": "complete",
      "stages": [
        {
          "name": "plan",
          "iterations": 1,
          "termination_reason": "fixed"
        },
        {
          "name": "iterate",
          "iterations": 3,
          "termination_reason": "plateau"
        }
      ],
      "outputs": {
        "plan": {
          "latest": "/path/to/iterations/001/output.md",
          "all": ["/path/to/iterations/001/output.md"]
        },
        "iterate": {
          "latest": "/path/to/iterations/003/output.md",
          "all": [
            "/path/to/iterations/001/output.md",
            "/path/to/iterations/002/output.md",
            "/path/to/iterations/003/output.md"
          ]
        }
      }
    },
    "codex": {
      "status": "complete",
      "stages": [...],
      "outputs": {...}
    }
  }
}
```

**Important**: Manifest is ONLY written when ALL providers complete successfully. If any provider fails, no manifest is written.

---

## 14. Resume and Crash Recovery

### Resume Hints (resume.json)

During execution, `resume.json` tracks each provider's progress:

```json
{
  "claude": {
    "stage_index": 1,
    "iteration": 2,
    "status": "complete"
  },
  "codex": {
    "stage_index": 0,
    "iteration": 1,
    "status": "running"
  }
}
```

### How Resume Works

When `--resume` is passed:

1. `run_parallel_block_resume()` is called instead of `run_parallel_block()`
2. For each provider:
   - Check `resume.json` and `state.json` for status
   - If `status == "complete"`, skip (print "already complete, skipping")
   - If `status != "complete"`, restart that provider
3. Only incomplete providers are spawned
4. When all providers complete, manifest is written

### Provider State Tracking

Each provider's `state.json`:

```json
{
  "provider": "claude",
  "session": "my-session",
  "started_at": "2026-01-13T21:00:00Z",
  "status": "running",           // pending, running, complete, failed
  "current_stage_name": "plan",
  "iteration": 1,
  "iteration_completed": 0,
  "stages": []                   // Populated as stages complete
}
```

---

## 15. Execution Flow

### run_parallel_block()

```
1. Parse block config (providers, stages)
2. Initialize block directory (init_parallel_block)
3. Initialize provider states (init_provider_state for each)
4. Print block header
5. For each provider:
   - Spawn subshell
   - Run run_parallel_provider() in subshell
   - Track PID
6. Wait for all PIDs
7. Check for failures
8. If all succeeded: write manifest
9. Update pipeline state
```

### run_parallel_provider()

```
For each provider (runs in subshell):
1. Mark provider status = "running"
2. For each stage in block:
   a. Load stage definition
   b. Source completion strategy
   c. For each iteration (up to max):
      - Generate context.json with parallel_scope
      - Resolve prompt template
      - Execute agent
      - Save output
      - Validate status.json
      - Check termination condition
   d. Record stage completion
3. Mark provider status = "complete"
```

---

## 16. Termination Strategies Per Provider

Each stage within a parallel block has its own termination config:

### Fixed Termination

```yaml
termination:
  type: fixed
  iterations: 3
```

Provider runs exactly N iterations, regardless of agent decision.

### Judgment Termination

```yaml
termination:
  type: judgment
  consensus: 2
  min_iterations: 2
  max: 5
```

Provider runs until N consecutive `decision: stop` in status.json (plateau), checked after min_iterations.

**Important**: Each provider has its own independent judgment. Claude might plateau at iteration 3, Codex at iteration 5.

### Queue Termination

```yaml
termination:
  type: queue
```

Provider runs until its queue is empty. (Less common for parallel blocks since queues are typically shared.)

---

## 17. Test Coverage

78 tests across 5 phases in `scripts/tests/test_parallel_blocks.sh`:

### Phase 1: Validation (10 tests)

| Test | What It Verifies |
|------|------------------|
| `test_parallel_block_requires_providers` | Missing providers array fails validation |
| `test_parallel_block_requires_stages` | Missing stages array fails validation |
| `test_parallel_block_rejects_nested` | Nested parallel blocks are rejected |
| `test_parallel_stage_no_provider_override` | Provider override inside block is rejected |
| `test_parallel_block_empty_providers` | Empty providers array fails |
| `test_parallel_block_empty_stages` | Empty stages array fails |
| `test_parallel_block_duplicate_stage_names` | Duplicate names within block fail |
| `test_parallel_block_valid_schema` | Valid parallel block passes |
| `test_from_parallel_validates_stage` | Invalid `from_parallel` reference fails |
| `test_from_parallel_valid_reference` | Valid `from_parallel` reference passes |

### Phase 2: Directory Structure (7 tests)

| Test | What It Verifies |
|------|------------------|
| `test_parallel_creates_provider_dirs` | Provider directories are created |
| `test_parallel_provider_isolation` | Each provider has own progress.md and state.json |
| `test_parallel_manifest_written` | Manifest is written after block completes |
| `test_parallel_manifest_format` | Manifest has correct JSON structure |
| `test_parallel_block_naming_auto` | Auto-naming works (parallel-XX) |
| `test_parallel_block_naming_custom` | Custom naming works (parallel-XX-name) |
| `test_parallel_resume_json_written` | Resume.json is created for crash recovery |

### Phase 3: Context Generation (6 tests)

| Test | What It Verifies |
|------|------------------|
| `test_context_parallel_scope_generates` | Context generated in provider scope |
| `test_context_parallel_same_provider_only` | Provider only sees its own outputs |
| `test_context_from_parallel_latest` | `from_parallel` with `select: latest` works |
| `test_context_from_parallel_history` | `from_parallel` with `select: history` works |
| `test_block_stage_inputs_can_read_previous_stage` | Stage inside block can read pre-block stage |
| `test_from_parallel_provider_subset` | Provider filtering works |

### Phase 4: Execution (7 tests)

| Test | What It Verifies |
|------|------------------|
| `test_parallel_block_runs_all_providers` | All providers run and produce output |
| `test_parallel_block_failure_bubbles_up` | Provider failure fails the block |
| `test_parallel_judgment_per_provider` | Judgment termination works per provider |
| `test_parallel_fixed_iteration_count` | Fixed iteration count is respected |
| `test_parallel_providers_run_concurrently` | Providers run in parallel (PID check) |
| `test_parallel_multi_stage_within_block` | Multiple stages run sequentially per provider |
| `test_parallel_block_state_tracking` | Pipeline state tracks parallel block |

### Phase 5: Resume and Integration (6 tests)

| Test | What It Verifies |
|------|------------------|
| `test_parallel_block_resume_skips_completed_providers` | Resume only runs incomplete providers |
| `test_parallel_manifest_not_written_on_failure` | No manifest when provider fails |
| `test_from_parallel_select_subset` | Provider subset filtering in downstream |
| `test_pipeline_with_sequential_parallel_sequential` | Full flow: setup → parallel → synthesize |
| `test_parallel_resume_updates_resume_json` | Resume.json is updated during execution |
| `test_parallel_block_all_providers_must_complete` | Block waits for all providers |

### How Tests Work

Tests use `MOCK_MODE=true` which:
- Skips actual Claude/Codex API calls
- Uses mock fixtures from `$MOCK_FIXTURES_DIR`
- Provider-specific fixtures: `$MOCK_FIXTURES_DIR/{provider}/{stage}-iteration-{NNN}.txt`
- Allows verifying orchestration logic without real execution

---

## 18. Implementation Files

| File | Purpose |
|------|---------|
| `scripts/lib/parallel.sh` | `run_parallel_block()`, `run_parallel_provider()`, `run_parallel_block_resume()` |
| `scripts/lib/state.sh` | `init_parallel_block()`, `init_provider_state()`, `write_parallel_manifest()`, `write_parallel_resume()`, `get_parallel_resume_hint()` |
| `scripts/lib/context.sh` | `build_inputs_json()` with `parallel_scope`, `build_from_parallel_inputs()` |
| `scripts/lib/validate.sh` | `_validate_parallel_block()`, validation rules P012-P017 |
| `scripts/engine.sh` | Sources `parallel.sh`, calls `run_parallel_block()` when stage has `parallel:` key |

---

## 19. Key Functions Reference

### init_parallel_block()

```bash
# Creates block directory and provider subdirectories
# Usage: block_dir=$(init_parallel_block "$run_dir" "$stage_idx" "$block_name" "$providers")
# Returns: Path to block directory
```

### init_provider_state()

```bash
# Creates state.json and progress.md for a provider
# Usage: init_provider_state "$block_dir" "$provider" "$session"
```

### run_parallel_block()

```bash
# Orchestrates parallel execution: spawn providers, wait, build manifest
# Usage: run_parallel_block "$stage_idx" "$block_config" "$defaults" "$state_file" "$run_dir" "$session"
# Returns: 0 on success, 1 on any provider failure
```

### run_parallel_provider()

```bash
# Runs stages sequentially for a single provider (called in subshell)
# Usage: run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults_json"
# Returns: 0 on success, 1 on failure
```

### run_parallel_block_resume()

```bash
# Resumes a parallel block: skip completed providers, restart others
# Usage: run_parallel_block_resume "$stage_idx" "$block_config" "$defaults" "$state_file" "$run_dir" "$session" "$block_dir"
```

### write_parallel_manifest()

```bash
# Creates manifest.json with aggregated provider outputs
# Usage: write_parallel_manifest "$block_dir" "$block_name" "$block_idx" "$stages" "$providers"
```

### build_from_parallel_inputs()

```bash
# Builds from_parallel inputs based on manifest
# Usage: build_from_parallel_inputs "$stage_config" "$run_dir"
# Returns: JSON object with providers and their outputs
```

---

## 20. Common Patterns

### Pattern: Compare and Synthesize

```yaml
stages:
  - name: initial-plan
    stage: improve-plan
    termination: { type: fixed, iterations: 1 }

  - name: dual-refine
    parallel:
      providers: [claude, codex]
      stages:
        - name: refine
          stage: improve-plan
          termination: { type: judgment, consensus: 2, max: 5 }

  - name: synthesize
    stage: elegance
    inputs:
      from_parallel: refine
```

### Pattern: Provider-Specific Strengths

```yaml
stages:
  - name: dual-work
    parallel:
      providers: [claude, codex]
      stages:
        - name: design
          stage: improve-plan    # Claude excels at design
          termination: { type: fixed, iterations: 2 }
        - name: implement
          stage: work           # Both implement their designs
          termination: { type: queue }
```

### Pattern: Read Only Claude's Output

```yaml
stages:
  - name: multi-provider
    parallel:
      providers: [claude, codex, gemini]
      stages:
        - name: brainstorm
          stage: idea-wizard
          termination: { type: fixed, iterations: 3 }

  - name: claude-only-synthesis
    stage: elegance
    inputs:
      from_parallel:
        stage: brainstorm
        providers: [claude]    # Only use Claude's ideas
```

---

## 21. Limitations and Constraints

1. **No nested parallel blocks**: Cannot have `parallel:` inside a parallel block's stages
2. **No provider override inside block**: Block controls provider; stages cannot specify their own
3. **All-or-nothing completion**: If any provider fails, entire block fails (no partial results)
4. **Shared stage definitions**: All providers use the same stage definition (same prompt, same termination config)
5. **No cross-provider communication**: Providers cannot see each other's outputs within a block
6. **Sequential stages within provider**: Stages run one after another per provider (not parallel within provider)

---

## 22. Architecture Guidance for Skills

### When to Recommend Parallel Blocks

Suggest parallel blocks when user wants:
- Multiple perspectives on the same task
- Comparison between providers
- Ensemble approaches
- Fault tolerance through redundancy

### When NOT to Use Parallel Blocks

Avoid when:
- Task requires sequential dependencies between different providers
- Single provider is sufficient
- Cost is a primary concern (runs N providers = N × cost)
- Task is trivially simple (overhead not worth it)

### Designer Questions to Ask

1. "Do you want to compare approaches from different AI providers?"
2. "Should the providers work independently, or do they need to see each other's work?"
3. "How do you want to combine the results? Take best one? Merge them? Let a synthesizer decide?"
4. "What should happen if one provider fails?"

---

## 23. CLI Usage

```bash
# Run a pipeline with parallel blocks
./scripts/run.sh pipeline parallel-refine.yaml my-session

# Resume after crash (skips completed providers)
./scripts/run.sh pipeline parallel-refine.yaml my-session --resume

# Validate before running
./scripts/run.sh lint pipeline parallel-refine.yaml

# Dry-run preview
./scripts/run.sh dry-run pipeline parallel-refine.yaml my-session
```

---

## 24. Debugging Parallel Blocks

```bash
# Check block directory structure
ls -la .claude/pipeline-runs/{session}/parallel-*

# Check provider states
cat .claude/pipeline-runs/{session}/parallel-*/providers/*/state.json | jq

# Check resume hints
cat .claude/pipeline-runs/{session}/parallel-*/resume.json | jq

# Check manifest (only exists after successful completion)
cat .claude/pipeline-runs/{session}/parallel-*/manifest.json | jq

# Watch specific provider's progress
cat .claude/pipeline-runs/{session}/parallel-*/providers/claude/progress.md

# Check why a provider failed
cat .claude/pipeline-runs/{session}/parallel-*/providers/codex/state.json | jq '.error'
```

---

---

# Part VI: CLI Reference

## 25. Complete CLI Options

### Run Modes

```bash
# Single-stage pipeline (loop)
./scripts/run.sh ralph my-session 25
./scripts/run.sh loop ralph my-session 25
./scripts/run.sh pipeline --single-stage ralph my-session 25

# Multi-stage pipeline
./scripts/run.sh pipeline my-pipeline.yaml my-session
```

### Provider and Model Overrides

```bash
# Override provider
./scripts/run.sh ralph my-session 25 --provider=codex
./scripts/run.sh ralph my-session 25 --provider=claude

# Override model
./scripts/run.sh ralph my-session 25 --model=opus
./scripts/run.sh ralph my-session 25 --model=sonnet
./scripts/run.sh ralph my-session 25 --model=gpt-5.1-codex-max

# Both
./scripts/run.sh ralph my-session 25 --provider=codex --model=gpt-5.2-codex
```

### Context Injection

```bash
# Inject context into prompts
./scripts/run.sh ralph my-session 25 --context="Focus on authentication"

# Multi-word context
./scripts/run.sh ralph my-session 25 --context="Read docs/plan.md before starting. Focus on error handling."
```

### Initial Inputs

```bash
# Single input
./scripts/run.sh pipeline my-pipeline.yaml my-session --input docs/plan.md

# Multiple inputs
./scripts/run.sh pipeline my-pipeline.yaml my-session \
  --input docs/plan.md \
  --input docs/research.md \
  --input "specs/*.md"
```

### Tmux Execution (Default)

All pipelines run in tmux by default for persistent background execution. This prevents blocking the calling agent and enables monitoring.

```bash
# Default: runs in tmux, returns immediately
./scripts/run.sh ralph my-session 25

# Monitor the session
tmux capture-pane -t pipeline-my-session -p | tail -50
tmux attach -t pipeline-my-session

# Run in foreground instead (blocks until complete)
./scripts/run.sh ralph my-session 25 --foreground
./scripts/run.sh ralph my-session 25 --no-tmux
```

### Session Management

```bash
# Force start (override existing lock)
./scripts/run.sh ralph my-session 25 --force

# Resume crashed session
./scripts/run.sh ralph my-session 25 --resume

# Check status
./scripts/run.sh status my-session

# Kill a running session
tmux kill-session -t pipeline-my-session
```

### Validation and Testing

```bash
# Lint a stage
./scripts/run.sh lint loop my-stage

# Lint a pipeline
./scripts/run.sh lint pipeline my-pipeline.yaml

# Dry run (no execution)
./scripts/run.sh dry-run pipeline my-pipeline.yaml my-session
```

---

## 26. Environment Variables

### Provider Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_PIPELINE_PROVIDER` | Override provider for all stages | (from config) |
| `CLAUDE_PIPELINE_MODEL` | Override model for all stages | (from config) |
| `CODEX_MODEL` | Default Codex model | `gpt-5.2-codex` |
| `CODEX_REASONING_EFFORT` | Reasoning effort for Codex | `high` |

### Context and Debugging

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_PIPELINE_CONTEXT` | Inject text into prompts via ${CONTEXT} | (empty) |
| `MOCK_MODE` | Skip real API calls, use mock responses | `false` |
| `MOCK_FIXTURES_DIR` | Directory for mock response fixtures | (varies) |

### Session Info (Set by Engine)

| Variable | Description |
|----------|-------------|
| `CLAUDE_PIPELINE_AGENT` | Always `1` inside a pipeline |
| `CLAUDE_PIPELINE_SESSION` | Current session name |
| `CLAUDE_PIPELINE_TYPE` | Current stage type |

---

# Part VII: context.json Complete Reference

## 27. Full context.json Structure

Every iteration receives a `context.json` file with complete session state:

```json
{
  "session": "my-session",
  "pipeline": "refine",
  "stage": {
    "id": "improve-plan",
    "index": 0,
    "template": "improve-plan"
  },
  "iteration": 3,
  "paths": {
    "session_dir": "/path/to/.claude/pipeline-runs/my-session",
    "stage_dir": "/path/to/.claude/pipeline-runs/my-session/stage-00-improve-plan",
    "progress": "/path/to/.claude/pipeline-runs/my-session/stage-00-improve-plan/progress.md",
    "output": "/path/to/.claude/pipeline-runs/my-session/stage-00-improve-plan/output.md",
    "status": "/path/to/.claude/pipeline-runs/my-session/stage-00-improve-plan/iterations/003/status.json"
  },
  "inputs": {
    "from_initial": ["/path/to/initial/input.md"],
    "from_stage": {
      "previous-stage": ["/path/to/prev/output.md"]
    },
    "from_previous_iterations": [
      "/path/to/iterations/001/output.md",
      "/path/to/iterations/002/output.md"
    ],
    "from_parallel": {
      "stage": "refine",
      "block": "dual-provider",
      "providers": {...}
    }
  },
  "limits": {
    "max_iterations": 50,
    "remaining_seconds": 3600
  },
  "commands": {
    "test": "bundle exec rspec",
    "format": "bundle exec rubocop -a"
  }
}
```

## 28. Template Variables Quick Reference

| Variable | Description | Source |
|----------|-------------|--------|
| `${CTX}` | Path to context.json | Engine |
| `${STATUS}` | Path to write status.json | Engine |
| `${PROGRESS}` | Path to progress file | Engine |
| `${OUTPUT}` | Path for output file | Engine |
| `${ITERATION}` | 1-based iteration number | Engine |
| `${SESSION_NAME}` | Session name | Engine |
| `${CONTEXT}` | Injected context text | CLI/Env/Config |

### Deprecated Variables (Still Work)

| Variable | Replacement |
|----------|-------------|
| `${SESSION}` | `${SESSION_NAME}` |
| `${INDEX}` | `${ITERATION}` - 1 |
| `${PROGRESS_FILE}` | `${PROGRESS}` |

---

# Summary

This document covers all major features of Agent Pipelines:

1. **Provider System** (§1): Multi-provider support (Claude, Codex) with unified abstraction
2. **Initial Inputs** (§2): Pipeline-level input files via YAML or CLI
3. **Inter-Stage Inputs** (§3): `from`/`select` for stage-to-stage data flow
4. **Previous Iteration Inputs** (§4): Automatic collection of within-stage history
5. **Complete Inputs Object** (§5): Full structure reference
6. **Context Injection** (§6): `${CONTEXT}` variable for runtime customization
7. **Commands Passthrough** (§7): Stage-defined commands for validation
8. **Parallel Blocks** (§8-24): Multi-provider concurrent execution with isolation
9. **CLI Reference** (§25-26): Complete command-line options
10. **context.json Reference** (§27-28): Full structure and template variables

Use this document to update skills, documentation, and architectural guidance.
