# feat: Parallel Provider Execution in Pipeline Stages

## Overview

Enable pipeline stages to run multiple AI providers (Claude, Codex, Gemini) in parallel. Two modes:

1. **`providers:`** - Same iteration, multiple providers (comparison)
2. **`tracks:`** - Independent iteration loops in parallel (full development)

## Design Philosophy

**Parallel execution is for comparison, not consensus.** Agents running simultaneously can't see each other, so they can't agree. If you need consensus, use a subsequent single-provider stage that sees all parallel outputs.

## Schema

```yaml
# Single provider (existing, unchanged)
provider: claude

# Multiple providers (new)
providers: [claude, codex, gemini]
```

That's it. No per-provider models for v1. Stage-level `model:` applies to all.

## Directory Structure

```
.claude/pipeline-runs/{session}/
└── stage-00-brainstorm/
    └── iterations/
        └── 001/
            ├── claude/
            │   ├── output.md
            │   └── status.json
            ├── codex/
            │   ├── output.md
            │   └── status.json
            └── context.json    # Shared context, includes paths to all provider outputs
```

## Execution Flow

```
1. Engine detects providers array
2. Creates provider subdirectories
3. Spawns background job per provider (writes to isolated dir)
4. Waits for all (wait $pid)
5. Collects exit codes - ALL must succeed (no policy options for v1)
6. Updates context.json with provider output paths
7. Continues to next iteration or stage
```

## Termination

**Parallel stages use fixed termination only.**

```yaml
stages:
  - name: brainstorm
    providers: [claude, codex]
    termination:
      type: fixed
      iterations: 3
```

No judgment/plateau with parallel providers. Those require visibility between agents.

If you need consensus, chain a single-provider stage:

```yaml
stages:
  - name: brainstorm
    providers: [claude, codex]
    termination:
      type: fixed
      iterations: 1

  - name: synthesize
    provider: claude
    inputs:
      from: brainstorm
    termination:
      type: judgment  # This agent sees all outputs, can judge
```

## Context.json Extension

```json
{
  "inputs": {
    "providers": {
      "claude": {
        "output": "/path/to/claude/output.md",
        "status": "/path/to/claude/status.json"
      },
      "codex": {
        "output": "/path/to/codex/output.md",
        "status": "/path/to/codex/status.json"
      }
    }
  }
}
```

## Implementation

### Files to Modify

1. **`scripts/lib/provider.sh`** (~20 lines)
   - Add `get_providers_list()` - parse providers array from config
   - Add `validate_providers()` - preflight check all CLIs exist

2. **`scripts/engine.sh`** (~50 lines)
   - Add parallel branch in `run_stage()` when providers array detected
   - Spawn background jobs, wait, collect exit codes
   - Fail if any provider fails

3. **`scripts/lib/context.sh`** (~20 lines)
   - Add provider output paths to `inputs.providers` in context.json

4. **`scripts/lib/validate.sh`** (~10 lines)
   - Error if both `provider:` and `providers:` specified
   - Error if `providers:` with `termination.type: judgment`

### Core Implementation

```bash
# In engine.sh

execute_parallel_providers() {
  local providers_json=$1
  local prompt=$2
  local iter_dir=$3

  local -a pids=()
  local -a names=()

  # Spawn all providers
  for provider in $(echo "$providers_json" | jq -r '.[]'); do
    local provider_dir="$iter_dir/$provider"
    mkdir -p "$provider_dir"

    (
      execute_agent "$provider" "$prompt" "$provider_dir/output.md"
      echo $? > "$provider_dir/exit_code"
    ) &

    pids+=($!)
    names+=("$provider")
  done

  # Wait and check all succeeded
  local failed=0
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"
    local code=$(cat "$iter_dir/${names[$i]}/exit_code" 2>/dev/null || echo "1")
    if [ "$code" -ne 0 ]; then
      log_error "Provider ${names[$i]} failed with exit code $code"
      ((failed++))
    fi
  done

  [ $failed -eq 0 ]
}
```

## Validation Rules

| Condition | Result |
|-----------|--------|
| `provider:` and `providers:` both set | Error |
| `providers:` with `termination.type: judgment` | Error |
| `providers:` with `termination.type: plateau` | Error |
| Provider CLI not found | Error at preflight |

## Example Pipeline

```yaml
name: multi-provider-brainstorm
description: Get ideas from multiple providers, synthesize with one

stages:
  - name: brainstorm
    providers: [claude, codex]
    termination:
      type: fixed
      iterations: 2

  - name: synthesize
    provider: claude
    model: opus
    inputs:
      from: brainstorm
    termination:
      type: judgment
      consensus: 2
    prompt: |
      Review ideas from multiple providers:
      ${INPUTS}

      Synthesize the best elements into a unified recommendation.
```

---

# Part 2: Tracks (Independent Iteration Loops)

## Overview

`tracks:` runs multiple providers as independent iteration loops in parallel. Each track iterates until its own termination condition. Stage completes when ALL tracks finish.

## Use Case

"Let Claude and Codex each fully develop their own approach, then synthesize the best of both."

```
┌─────────────────────────────────────────────────────────┐
│                    Stage: Planning                       │
│  ┌─────────────────────┐   ┌─────────────────────────┐  │
│  │   Claude Track      │   │     Codex Track         │  │
│  │  iter 1 → continue  │   │  iter 1 → continue      │  │
│  │  iter 2 → continue  │   │  iter 2 → continue      │  │
│  │  iter 3 → stop ✓    │   │  iter 3 → continue      │  │
│  │  (plateaued)        │   │  iter 4 → stop ✓        │  │
│  └─────────────────────┘   └─────────────────────────┘  │
│            Wait for ALL tracks to complete...           │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│               Stage: Synthesize                          │
│   Sees both final plans, builds unified result          │
└─────────────────────────────────────────────────────────┘
```

## Schema

```yaml
stages:
  - name: planning
    tracks:
      - provider: claude
        loop: improve-plan        # Uses existing stage definition
        termination:
          type: judgment
          consensus: 2
          max: 5
      - provider: codex
        loop: improve-plan
        termination:
          type: judgment
          consensus: 2
          max: 5

  - name: synthesize
    provider: claude
    model: opus
    inputs:
      from: planning
    prompt: |
      Two AI systems independently refined a plan:

      ## Claude's Final Plan
      ${INPUTS.tracks.claude}

      ## Codex's Final Plan
      ${INPUTS.tracks.codex}

      Synthesize into the best, most elegant unified plan.
```

## How Tracks Differ from Providers

| Aspect | `providers:` | `tracks:` |
|--------|--------------|-----------|
| Parallelism | Same iteration, multiple providers | Independent iteration loops |
| Termination | Fixed only (all run N times) | Each track has own termination |
| When complete | All finish same iteration | All tracks reach own plateau |
| Use case | Compare outputs on same prompt | Let each fully develop approach |
| Iterations | Shared count | Independent counts |

## Directory Structure

```
.claude/pipeline-runs/my-session/
└── stage-00-planning/
    ├── tracks/
    │   ├── claude/
    │   │   ├── state.json           # Claude's iteration state
    │   │   └── iterations/
    │   │       ├── 001/
    │   │       ├── 002/
    │   │       └── 003/             # Plateaued here
    │   └── codex/
    │       ├── state.json           # Codex's iteration state
    │       └── iterations/
    │           ├── 001/
    │           ├── 002/
    │           ├── 003/
    │           └── 004/             # Plateaued here
    └── outputs.json                 # Final output paths from each track
```

## Context.json for Next Stage

```json
{
  "inputs": {
    "tracks": {
      "claude": {
        "output": "/path/to/tracks/claude/iterations/003/output.md",
        "iterations_completed": 3,
        "termination_reason": "plateau"
      },
      "codex": {
        "output": "/path/to/tracks/codex/iterations/004/output.md",
        "iterations_completed": 4,
        "termination_reason": "plateau"
      }
    }
  }
}
```

## Execution Flow

```
1. Engine detects tracks array
2. Spawns background process per track
3. Each track runs its own iteration loop:
   - Reads its own progress file
   - Writes to its own iteration directories
   - Checks its own termination condition
   - Stops independently when plateaued
4. Engine waits for ALL tracks to complete
5. Collects final outputs from each track
6. Writes outputs.json with paths
7. Continues to next stage
```

## Implementation

### Additional Files to Modify

1. **`scripts/engine.sh`** (~60 lines)
   - Add `run_tracks()` function
   - Spawn background process per track, each calling `run_iteration_loop()`
   - Wait for all, collect final outputs

2. **`scripts/lib/context.sh`** (~15 lines)
   - Add `inputs.tracks` to context.json
   - Include final output path and iteration count per track

3. **`scripts/lib/validate.sh`** (~10 lines)
   - Validate tracks config
   - Each track must have `provider` and `loop`

### Core Implementation

```bash
# In engine.sh

run_tracks() {
  local tracks_json=$1
  local stage_dir=$2

  local -a pids=()
  local -a providers=()

  # Spawn independent iteration loops
  for track in $(echo "$tracks_json" | jq -c '.[]'); do
    local provider=$(echo "$track" | jq -r '.provider')
    local loop=$(echo "$track" | jq -r '.loop')
    local termination=$(echo "$track" | jq -c '.termination')
    local track_dir="$stage_dir/tracks/$provider"

    mkdir -p "$track_dir"

    (
      # Run full iteration loop for this track
      run_iteration_loop "$loop" "$provider" "$track_dir" "$termination"
      echo $? > "$track_dir/exit_code"
    ) &

    pids+=($!)
    providers+=("$provider")
  done

  # Wait for ALL tracks to complete
  local failed=0
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"
    local code=$(cat "$stage_dir/tracks/${providers[$i]}/exit_code" 2>/dev/null || echo "1")
    if [ "$code" -ne 0 ]; then
      log_error "Track ${providers[$i]} failed"
      ((failed++))
    fi
  done

  # Collect final outputs
  collect_track_outputs "$stage_dir/tracks" "$stage_dir/outputs.json"

  [ $failed -eq 0 ]
}
```

## Example: Dual Refinement Pipeline

```yaml
name: dual-refinement
description: Two providers refine independently, then synthesize best plan

stages:
  - name: planning
    tracks:
      - provider: claude
        loop: improve-plan
        termination:
          type: judgment
          consensus: 2
          max: 5
      - provider: codex
        loop: improve-plan
        termination:
          type: judgment
          consensus: 2
          max: 5

  - name: synthesize
    provider: claude
    model: opus
    inputs:
      from: planning
    termination:
      type: fixed
      iterations: 1
    prompt: |
      Two AI systems independently developed plans:

      ## Claude's Approach (${INPUTS.tracks.claude.iterations_completed} iterations)
      ${INPUTS.tracks.claude.output}

      ## Codex's Approach (${INPUTS.tracks.codex.iterations_completed} iterations)
      ${INPUTS.tracks.codex.output}

      Your task: Synthesize these into the best, most elegant unified plan.
      - Take the strongest ideas from each
      - Resolve any contradictions
      - Produce a clear, actionable result
```

## Validation Rules

| Condition | Result |
|-----------|--------|
| Track missing `provider` | Error |
| Track missing `loop` | Error |
| Track references non-existent loop | Error |
| `tracks:` with `providers:` | Error: mutually exclusive |

## outputs.json Format

When a tracks stage completes, it writes `outputs.json` with paths to final outputs:

```json
{
  "claude": {
    "output": "/absolute/path/to/tracks/claude/iterations/003/output.md",
    "status": "/absolute/path/to/tracks/claude/iterations/003/status.json",
    "iterations_completed": 3,
    "termination_reason": "plateau"
  },
  "codex": {
    "output": "/absolute/path/to/tracks/codex/iterations/005/output.md",
    "status": "/absolute/path/to/tracks/codex/iterations/005/status.json",
    "iterations_completed": 5,
    "termination_reason": "max_iterations"
  }
}
```

**Tests for outputs.json:**
```bash
test_tracks_outputs_json_format()
# After tracks stage completes
# Expected: outputs.json exists in stage directory
# Expected: Each track has output, status, iterations_completed, termination_reason
# Expected: All paths are absolute and files exist

test_tracks_outputs_json_termination_reasons()
# Configure: claude plateaus at 3, codex hits max at 5
# Expected: claude.termination_reason = "plateau"
# Expected: codex.termination_reason = "max_iterations"

test_tracks_outputs_json_used_by_next_stage()
# Pipeline with tracks stage followed by single stage
# Expected: Next stage's context.json has inputs.tracks populated from outputs.json
```

---

# Summary: Three Parallelism Modes

| Mode | Schema | Use Case |
|------|--------|----------|
| Single | `provider: claude` | Normal iteration |
| Comparison | `providers: [claude, codex]` | Same prompt, compare outputs |
| Independent | `tracks: [{provider: claude, ...}]` | Each fully develops, then merge |

---

## What's NOT in v1

- Per-provider model configuration
- `fail_policy` options (all must succeed)
- `merged/` directory (unnecessary)
- `perspectives:` + `providers:` + `tracks:` composition

These can be added later if real use cases emerge.

---

# Test Strategy

## TDD Implementation Order

Tests should be written and pass in this order. Write the test first, verify it fails, then implement.

### Dependency Graph

```
Phase 1 (Validation)
    │
    ├── test_validation_provider_and_providers_exclusive
    ├── test_validation_providers_rejects_judgment
    └── test_validation_track_requires_provider
    │
    ▼
Phase 2 (Provider Abstraction) ─── depends on Phase 1
    │
    ├── test_get_providers_list_single
    ├── test_get_providers_list_array
    └── test_validate_providers_all_installed
    │
    ▼
Phase 3 (Directory Structure) ─── depends on Phase 2
    │
    ├── test_parallel_creates_provider_subdirs
    └── test_tracks_creates_tracks_directory
    │
    ▼
Phase 4 (Context.json) ─── depends on Phase 3
    │
    ├── test_context_providers_in_inputs
    └── test_context_tracks_in_inputs
    │
    ▼
Phase 5 (Execution) ─── depends on Phase 2, 3, 4
    │
    ├── test_parallel_spawns_all_providers
    ├── test_parallel_waits_for_all
    ├── test_tracks_spawns_independent_loops
    └── test_tracks_waits_for_all_on_failure
    │
    ▼
Phase 6 (Integration) ─── depends on all above
    │
    ├── test_pipeline_parallel_to_single
    └── test_pipeline_tracks_to_single
```

### Implementation Sprint Order

For efficient TDD development, implement in this order:

1. **Sprint 1: Validation (1-2 hours)**
   - Write all Phase 1 tests → all should fail
   - Implement validation in `validate.sh`
   - All Phase 1 tests pass

2. **Sprint 2: Provider Abstraction (1-2 hours)**
   - Write all Phase 2 tests → all should fail
   - Implement `get_providers_list()` in `provider.sh`
   - All Phase 2 tests pass

3. **Sprint 3: Directory & Context (2-3 hours)**
   - Write Phase 3 + 4 tests → all should fail
   - Implement directory creation in `engine.sh`
   - Implement context.json extension in `context.sh`
   - All Phase 3 + 4 tests pass

4. **Sprint 4: Parallel Execution (3-4 hours)**
   - Write Phase 5 parallel tests → all should fail
   - Implement `execute_parallel_providers()` in `engine.sh`
   - All parallel tests pass

5. **Sprint 5: Tracks Execution (3-4 hours)**
   - Write Phase 5 tracks tests → all should fail
   - Implement `run_tracks()` in `engine.sh`
   - All tracks tests pass

6. **Sprint 6: Integration (1-2 hours)**
   - Write Phase 6 tests → all should fail
   - Fix any integration issues
   - All Phase 6 tests pass

**Total estimated effort: 12-17 hours of focused TDD work**

### Phase 1: Validation Tests (test_validation.sh additions)

These tests define the contract - what configurations are allowed/disallowed.

#### 1.1 Mutual Exclusion Tests
```bash
test_validation_provider_and_providers_exclusive()
# Input: {"provider": "claude", "providers": ["claude", "codex"]}
# Expected: Error - cannot specify both provider and providers

test_validation_provider_and_tracks_exclusive()
# Input: {"provider": "claude", "tracks": [...]}
# Expected: Error - cannot specify both provider and tracks

test_validation_providers_and_tracks_exclusive()
# Input: {"providers": ["claude", "codex"], "tracks": [...]}
# Expected: Error - cannot specify both providers and tracks
```

#### 1.2 Termination Restriction Tests
```bash
test_validation_providers_rejects_judgment()
# Input: {"providers": ["claude", "codex"], "termination": {"type": "judgment"}}
# Expected: Error - parallel providers require fixed termination

test_validation_providers_rejects_plateau()
# Input: {"providers": ["claude", "codex"], "termination": {"type": "plateau"}}
# Expected: Error - parallel providers require fixed termination

test_validation_providers_accepts_fixed()
# Input: {"providers": ["claude", "codex"], "termination": {"type": "fixed", "iterations": 3}}
# Expected: Success
```

#### 1.3 Tracks Schema Tests
```bash
test_validation_track_requires_provider()
# Input: {"tracks": [{"loop": "improve-plan"}]}
# Expected: Error - track missing required field: provider

test_validation_track_requires_loop()
# Input: {"tracks": [{"provider": "claude"}]}
# Expected: Error - track missing required field: loop

test_validation_track_validates_loop_exists()
# Input: {"tracks": [{"provider": "claude", "loop": "nonexistent-loop"}]}
# Expected: Error - track references non-existent loop: nonexistent-loop
```

#### 1.4 Provider Preflight Tests
```bash
test_validation_providers_preflight_checks_all()
# Input: {"providers": ["claude", "nonexistent"]}
# Expected: Error - provider CLI not found: nonexistent
# Note: Should check ALL providers before starting, not fail on first execution
```

### Phase 2: Provider Abstraction Tests (test_providers.sh additions)

#### 2.1 Provider List Parsing
```bash
test_get_providers_list_single()
# Input: {"provider": "claude"}
# Expected: ["claude"]

test_get_providers_list_array()
# Input: {"providers": ["claude", "codex"]}
# Expected: ["claude", "codex"]

test_get_providers_list_empty()
# Input: {}
# Expected: ["claude"] (default)

test_get_providers_list_normalizes_aliases()
# Input: {"providers": ["anthropic", "openai"]}
# Expected: ["claude", "codex"]

test_get_providers_list_deduplicates()
# Input: {"providers": ["claude", "anthropic", "claude-code"]}
# Expected: ["claude"] (all aliases resolve to same provider)

test_get_providers_list_preserves_order()
# Input: {"providers": ["codex", "claude"]}
# Expected: ["codex", "claude"] (order preserved, codex first)
```

#### 2.2 Validate All Providers
```bash
test_validate_providers_all_installed()
# Mock: claude and codex both available
# Expected: Success

test_validate_providers_missing_one()
# Mock: claude available, codex NOT available
# Expected: Error listing missing provider

test_validate_providers_empty_list()
# Input: []
# Expected: Error - no providers specified
```

### Phase 3: Directory Structure Tests (test_context.sh additions)

#### 3.1 Parallel Provider Directories
```bash
test_parallel_creates_provider_subdirs()
# Run parallel iteration with providers: [claude, codex]
# Expected: iterations/001/claude/, iterations/001/codex/ exist

test_parallel_provider_dirs_contain_output()
# Expected: iterations/001/claude/output.md, iterations/001/codex/output.md

test_parallel_provider_dirs_contain_status()
# Expected: iterations/001/claude/status.json, iterations/001/codex/status.json
```

#### 3.2 Tracks Directory Structure
```bash
test_tracks_creates_tracks_directory()
# Run with tracks configuration
# Expected: stage-*/tracks/ directory exists

test_tracks_creates_provider_subdirs()
# Expected: tracks/claude/, tracks/codex/ directories

test_tracks_each_has_own_state()
# Expected: tracks/claude/state.json, tracks/codex/state.json

test_tracks_each_has_own_iterations()
# Expected: tracks/claude/iterations/001/, tracks/codex/iterations/001/
```

### Phase 4: Context.json Extension Tests (test_context.sh additions)

#### 4.1 Parallel Provider Inputs
```bash
test_context_providers_in_inputs()
# After parallel iteration, read context.json for next iteration
# Expected: inputs.providers object exists

test_context_providers_has_output_paths()
# Expected: inputs.providers.claude.output = "/path/to/claude/output.md"
# Expected: inputs.providers.codex.output = "/path/to/codex/output.md"

test_context_providers_has_status_paths()
# Expected: inputs.providers.claude.status = "/path/to/claude/status.json"
# Expected: inputs.providers.codex.status = "/path/to/codex/status.json"
```

#### 4.2 Tracks Inputs
```bash
test_context_tracks_in_inputs()
# After tracks stage completes, context for next stage
# Expected: inputs.tracks object exists

test_context_tracks_has_final_output()
# Expected: inputs.tracks.claude.output = path to final iteration output

test_context_tracks_has_iteration_count()
# Expected: inputs.tracks.claude.iterations_completed = 3

test_context_tracks_has_termination_reason()
# Expected: inputs.tracks.claude.termination_reason = "plateau" or "max_iterations"
```

### Phase 5: Execution Tests (integration/test_parallel.sh - NEW FILE)

These require the mock infrastructure.

#### 5.1 Parallel Provider Execution
```bash
test_parallel_spawns_all_providers()
# Run engine with providers: [claude, codex]
# Expected: Both execute_agent calls made (check mock call log)

test_parallel_waits_for_all()
# One provider fast, one slow (use MOCK_DELAY per provider)
# Expected: Engine waits for both to complete

test_parallel_all_must_succeed()
# Configure one provider to fail (exit code 1)
# Expected: Overall iteration fails

test_parallel_creates_all_outputs()
# Expected: Both provider output files exist with content
```

#### 5.2 Parallel Iteration Progression
```bash
test_parallel_runs_n_iterations()
# Config: providers: [claude, codex], termination: {type: fixed, iterations: 3}
# Expected: 3 iterations run, each with both provider outputs

test_parallel_state_tracks_iterations()
# Expected: state.json iteration_completed = 3
```

#### 5.3 Tracks Execution
```bash
test_tracks_spawns_independent_loops()
# Config: tracks with claude and codex
# Expected: Two independent iteration loops started

test_tracks_each_has_own_termination()
# Config: claude max 3, codex max 5
# Expected: Claude stops at 3, codex continues to 5

test_tracks_stage_completes_when_all_done()
# Expected: Stage status = complete only after both tracks finish

test_tracks_collects_final_outputs()
# Expected: outputs.json with paths to each track's final output
```

#### 5.4 Track Failure Handling

**Policy Decision (v1):** When one track fails, we **wait for all running tracks to complete** before reporting failure. This preserves partial results and avoids orphaned processes. Cleanup can happen in future versions.

```bash
test_tracks_fails_if_any_track_fails()
# Configure one track to fail (exit code 1 in mock)
# Expected: Overall stage fails with exit code != 0
# Expected: All track outputs collected before failure reported

test_tracks_waits_for_all_on_failure()
# Configure track-1 to fail at iteration 2, track-2 continues to iteration 4
# Expected: Engine waits for track-2 to complete before reporting failure
# Expected: Both tracks have their final outputs recorded

test_tracks_reports_which_tracks_failed()
# Configure two tracks, one fails, one succeeds
# Expected: Error message includes "Track claude failed" (not just generic failure)
# Expected: Successful track's output is still available
```

#### 5.5 Edge Case Tests

```bash
test_parallel_single_provider_array()
# Config: providers: ["claude"]  (array with one element)
# Expected: Treated same as provider: "claude" (no parallel overhead)
# Expected: Creates iterations/001/output.md (not iterations/001/claude/output.md)

test_parallel_empty_providers_fails()
# Config: providers: []
# Expected: Validation error "no providers specified"

test_parallel_timing_independence()
# Configure MOCK_DELAY: claude=0s, codex=2s
# Expected: Both outputs exist, engine waits for slower provider
# Expected: Status shows both completed (not just the fast one)

test_parallel_invalid_status_from_one()
# Provider claude writes valid status.json, provider codex writes invalid JSON
# Expected: Overall iteration fails (cannot determine decision)
# Expected: Error message mentions "invalid status.json from codex"

test_tracks_independent_iteration_counts()
# Track claude runs 3 iterations (plateau), track codex runs 5 iterations
# Expected: outputs.json shows claude.iterations_completed=3, codex.iterations_completed=5
# Expected: context for next stage includes both iteration counts
```

### Phase 6: End-to-End Integration Tests

#### 6.1 Pipeline With Parallel Stage
```bash
test_pipeline_parallel_to_single()
# pipeline.yaml:
#   - name: brainstorm
#     providers: [claude, codex]
#     termination: {type: fixed, iterations: 1}
#   - name: synthesize
#     provider: claude
#     inputs: {from: brainstorm}
# Expected: synthesize stage sees both provider outputs in inputs
```

#### 6.2 Pipeline With Tracks
```bash
test_pipeline_tracks_to_single()
# pipeline.yaml:
#   - name: planning
#     tracks: [...]
#   - name: synthesize
#     provider: claude
#     inputs: {from: planning}
# Expected: synthesize stage sees both track final outputs
```

### Phase 7: Existing Tests That Will Be Affected

These tests should continue to pass unchanged:

| Test File | Affected Tests | Expected Behavior |
|-----------|---------------|-------------------|
| test_providers.sh | All existing | Single provider logic unchanged |
| test_validation.sh | All existing | Single provider validation unchanged |
| test_context.sh | All existing | Single provider context unchanged |
| integration/test_single_stage.sh | All | Single provider runs as before |
| integration/test_multi_stage.sh | All | inputs.from_stage still works |

New tests should NOT break any existing tests. If they do, we have a regression.

## Test File Organization

Clear mapping of which tests go in which files:

### Unit Tests (scripts/tests/)

| File | New Tests | Purpose |
|------|-----------|---------|
| `test_validation.sh` | `test_validation_provider_and_providers_exclusive`, `test_validation_providers_rejects_judgment`, `test_validation_providers_rejects_plateau`, `test_validation_providers_accepts_fixed`, `test_validation_provider_and_tracks_exclusive`, `test_validation_providers_and_tracks_exclusive`, `test_validation_track_requires_provider`, `test_validation_track_requires_loop`, `test_validation_track_validates_loop_exists`, `test_validation_providers_preflight_checks_all` | Stage config validation |
| `test_providers.sh` | `test_get_providers_list_single`, `test_get_providers_list_array`, `test_get_providers_list_empty`, `test_get_providers_list_normalizes_aliases`, `test_get_providers_list_deduplicates`, `test_get_providers_list_preserves_order`, `test_validate_providers_all_installed`, `test_validate_providers_missing_one`, `test_validate_providers_empty_list` | Provider abstraction |
| `test_context.sh` | `test_parallel_creates_provider_subdirs`, `test_parallel_provider_dirs_contain_output`, `test_parallel_provider_dirs_contain_status`, `test_context_providers_in_inputs`, `test_context_providers_has_output_paths`, `test_context_providers_has_status_paths`, `test_tracks_creates_tracks_directory`, `test_tracks_creates_provider_subdirs`, `test_tracks_each_has_own_state`, `test_tracks_each_has_own_iterations`, `test_context_tracks_in_inputs`, `test_context_tracks_has_final_output`, `test_context_tracks_has_iteration_count`, `test_context_tracks_has_termination_reason` | Context generation |
| `test_mock.sh` | `test_mock_provider_specific_response`, `test_mock_provider_fallback_to_shared`, `test_mock_provider_delay` | Mock infrastructure |

### Integration Tests (scripts/tests/integration/)

| File | New Tests | Purpose |
|------|-----------|---------|
| `test_parallel.sh` (NEW) | `test_parallel_spawns_all_providers`, `test_parallel_waits_for_all`, `test_parallel_all_must_succeed`, `test_parallel_creates_all_outputs`, `test_parallel_runs_n_iterations`, `test_parallel_state_tracks_iterations`, `test_parallel_single_provider_array`, `test_parallel_empty_providers_fails`, `test_parallel_timing_independence`, `test_parallel_invalid_status_from_one`, `test_pipeline_parallel_to_single` | Parallel provider execution |
| `test_tracks.sh` (NEW) | `test_tracks_spawns_independent_loops`, `test_tracks_each_has_own_termination`, `test_tracks_stage_completes_when_all_done`, `test_tracks_collects_final_outputs`, `test_tracks_fails_if_any_track_fails`, `test_tracks_waits_for_all_on_failure`, `test_tracks_reports_which_tracks_failed`, `test_tracks_independent_iteration_counts`, `test_tracks_outputs_json_format`, `test_tracks_outputs_json_termination_reasons`, `test_tracks_outputs_json_used_by_next_stage`, `test_pipeline_tracks_to_single` | Tracks (independent loops) execution |

## Test Infrastructure Requirements

### New Fixtures Needed

```
scripts/tests/fixtures/integration/
├── parallel-2/                    # Two providers, 2 iterations
│   ├── stage.yaml                 # providers: [claude, codex]
│   ├── prompt.md
│   ├── claude/                    # Claude-specific responses
│   │   ├── iteration-001.txt
│   │   ├── status-001.json
│   │   ├── iteration-002.txt
│   │   └── status-002.json
│   └── codex/                     # Codex-specific responses
│       ├── iteration-001.txt
│       ├── status-001.json
│       ├── iteration-002.txt
│       └── status-002.json
└── tracks-dual/                   # Two tracks configuration
    ├── pipeline.yaml              # tracks definition
    ├── stage-00-planning/         # Stage with tracks
    │   ├── stage.yaml
    │   ├── claude/
    │   │   ├── iteration-001.txt
    │   │   ├── status-001.json
    │   │   ├── iteration-002.txt
    │   │   ├── status-002.json    # decision: stop (plateau)
    │   │   └── iteration-003.txt
    │   │   └── status-003.json    # decision: stop (confirm)
    │   └── codex/
    │       ├── iteration-001.txt
    │       ├── status-001.json
    │       ├── iteration-002.txt
    │       ├── status-002.json
    │       ├── iteration-003.txt
    │       ├── status-003.json
    │       ├── iteration-004.txt
    │       ├── status-004.json    # decision: stop (plateau)
    │       └── iteration-005.txt
    │       └── status-005.json    # decision: stop (confirm)
    └── stage-01-synthesize/       # Next stage sees both outputs
        ├── stage.yaml
        └── ...
```

### Concrete Fixture File Examples

**parallel-2/stage.yaml:**
```yaml
name: test-parallel-2
description: Test parallel provider execution

providers: [claude, codex]

termination:
  type: fixed
  iterations: 2

delay: 0
```

**parallel-2/claude/iteration-001.txt:**
```
# Claude Analysis - Iteration 1

## Observations
- Analyzed requirements from Claude's perspective
- Identified key architectural patterns

## Recommendations
- Use service-oriented approach
- Implement retry logic with exponential backoff

## Status
Written to status.json with decision: continue
```

**parallel-2/claude/status-001.json:**
```json
{
  "decision": "continue",
  "reason": "Parallel iteration 1 - more analysis needed",
  "summary": "Claude analyzed requirements, recommended service-oriented approach",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**parallel-2/codex/iteration-001.txt:**
```
# Codex Analysis - Iteration 1

## Observations
- Analyzed requirements from Codex's perspective
- Focus on implementation patterns

## Recommendations
- Use functional composition
- Implement event-driven architecture

## Status
Written to status.json with decision: continue
```

**parallel-2/codex/status-001.json:**
```json
{
  "decision": "continue",
  "reason": "Parallel iteration 1 - more analysis needed",
  "summary": "Codex analyzed requirements, recommended functional composition",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**tracks-dual/pipeline.yaml:**
```yaml
name: test-tracks-dual
description: Test tracks with dual providers

stages:
  - name: planning
    tracks:
      - provider: claude
        loop: test-plan
        termination:
          type: judgment
          consensus: 2
          max: 5
      - provider: codex
        loop: test-plan
        termination:
          type: judgment
          consensus: 2
          max: 5

  - name: synthesize
    provider: claude
    loop: test-synthesize
    inputs:
      from: planning
    termination:
      type: fixed
      iterations: 1
```

### Mock Infrastructure Updates

The mock.sh needs extension to support per-provider responses:

```bash
#-------------------------------------------------------------------------------
# Per-Provider Mock Support
#-------------------------------------------------------------------------------

# Get mock response for specific provider in parallel mode
# Usage: get_mock_response_for_provider "$iteration" "$provider"
# Fixture lookup order:
#   1. $MOCK_FIXTURES_DIR/$provider/iteration-NNN.txt (provider-specific)
#   2. $MOCK_FIXTURES_DIR/iteration-NNN.txt (shared fallback)
#   3. $MOCK_FIXTURES_DIR/$provider/default.txt (provider default)
#   4. $MOCK_FIXTURES_DIR/default.txt (global default)
get_mock_response_for_provider() {
  local iteration=$1
  local provider=$2
  local iter_formatted=$(printf "%03d" "$iteration")

  # Try provider-specific iteration file
  local file="$MOCK_FIXTURES_DIR/$provider/iteration-${iter_formatted}.txt"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Try shared iteration file (same response for all providers)
  file="$MOCK_FIXTURES_DIR/iteration-${iteration}.txt"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Try provider default
  file="$MOCK_FIXTURES_DIR/$provider/default.txt"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Global default
  get_mock_response "$iteration"
}

# Get mock status for specific provider
# Usage: get_mock_status_for_provider "$iteration" "$provider"
# Same lookup order as get_mock_response_for_provider
get_mock_status_for_provider() {
  local iteration=$1
  local provider=$2
  local iter_formatted=$(printf "%03d" "$iteration")

  # Try provider-specific status
  local file="$MOCK_FIXTURES_DIR/$provider/status-${iter_formatted}.json"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Try shared status
  file="$MOCK_FIXTURES_DIR/status-${iteration}.json"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Try provider default status
  file="$MOCK_FIXTURES_DIR/$provider/status.json"
  [ -f "$file" ] && { cat "$file"; return 0; }

  # Generate default
  get_mock_status "$iteration"
}

# Configure mock delay per provider (for timing tests)
# Usage: set_mock_provider_delay "codex" 2
# Reads from: MOCK_DELAY_$provider or MOCK_DELAY (default)
get_mock_provider_delay() {
  local provider=$1
  local var_name="MOCK_DELAY_$(echo "$provider" | tr '[:lower:]' '[:upper:]')"
  local delay=${!var_name:-$MOCK_DELAY}
  echo "${delay:-0}"
}

# Write mock status to provider-specific location
# Usage: write_mock_status_for_provider "$iter_dir" "$iteration" "$provider"
write_mock_status_for_provider() {
  local iter_dir=$1
  local iteration=$2
  local provider=$3
  local status_file="$iter_dir/$provider/status.json"

  mkdir -p "$(dirname "$status_file")"
  get_mock_status_for_provider "$iteration" "$provider" > "$status_file"
}
```

**Test for mock infrastructure itself:**
```bash
# In test_mock.sh (new tests)

test_mock_provider_specific_response()
# Setup: fixtures/claude/iteration-001.txt = "claude response"
#        fixtures/codex/iteration-001.txt = "codex response"
# Expected: get_mock_response_for_provider 1 "claude" returns "claude response"
# Expected: get_mock_response_for_provider 1 "codex" returns "codex response"

test_mock_provider_fallback_to_shared()
# Setup: fixtures/iteration-001.txt = "shared response" (no per-provider files)
# Expected: get_mock_response_for_provider 1 "claude" returns "shared response"
# Expected: get_mock_response_for_provider 1 "codex" returns "shared response"

test_mock_provider_delay()
# Setup: MOCK_DELAY_CODEX=2, MOCK_DELAY=0
# Expected: get_mock_provider_delay "claude" returns 0
# Expected: get_mock_provider_delay "codex" returns 2
```

### Harness Updates

The harness.sh needs new helpers:

```bash
#-------------------------------------------------------------------------------
# Parallel Provider Test Helpers
#-------------------------------------------------------------------------------

# Setup parallel test environment
# Usage: setup_parallel_test "$test_dir" "parallel-2"
setup_parallel_test() {
  local test_dir=$1
  local fixture_name=${2:-"parallel-2"}

  # Base setup
  setup_integration_test "$test_dir" "$fixture_name"

  # Copy parallel-specific stage
  local fixture_dir="$FIXTURES_BASE/$fixture_name"
  if [ -f "$fixture_dir/stage.yaml" ]; then
    local stage_name="test-$fixture_name"
    mkdir -p "$test_dir/stages/$stage_name"
    cp "$fixture_dir/stage.yaml" "$test_dir/stages/$stage_name/"
    cp "$fixture_dir/prompt.md" "$test_dir/stages/$stage_name/" 2>/dev/null || true

    # Copy per-provider fixture directories
    for provider_dir in "$fixture_dir"/claude "$fixture_dir"/codex "$fixture_dir"/gemini; do
      if [ -d "$provider_dir" ]; then
        cp -r "$provider_dir" "$test_dir/stages/$stage_name/fixtures/"
      fi
    done
  fi
}

# Run engine with parallel providers
# Usage: run_mock_parallel_engine "$test_dir" "$session" "$max" ["$stage_type"]
run_mock_parallel_engine() {
  local test_dir=$1
  local session=$2
  local max_iterations=${3:-3}
  local stage_type=${4:-"test-parallel-2"}

  export MOCK_MODE=true

  (
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline --single-stage "$stage_type" "$session" "$max_iterations" 2>&1
  )
  return $?
}

# Count provider directories in iteration
# Usage: count_provider_dirs "$run_dir" "$iteration"
# Returns: number of provider subdirectories (excluding context.json, status.json, output.md)
count_provider_dirs() {
  local run_dir=$1
  local iteration=$2

  # Find the stage directory first
  local stage_dir=""
  for d in "$run_dir"/stage-*/iterations; do
    [ -d "$d" ] && stage_dir="$d" && break
  done

  if [ -z "$stage_dir" ]; then
    echo "0"
    return
  fi

  local iter_dir="$stage_dir/$(printf '%03d' $iteration)"
  if [ ! -d "$iter_dir" ]; then
    echo "0"
    return
  fi

  # Count subdirectories only (not files)
  find "$iter_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' '
}

# Get provider output path
# Usage: get_provider_output "$run_dir" "$iteration" "$provider"
get_provider_output() {
  local run_dir=$1
  local iteration=$2
  local provider=$3

  # Find stage directory
  local stage_dir=""
  for d in "$run_dir"/stage-*/iterations; do
    [ -d "$d" ] && stage_dir="$d" && break
  done

  echo "$stage_dir/$(printf '%03d' $iteration)/$provider/output.md"
}

# Get provider status path
# Usage: get_provider_status "$run_dir" "$iteration" "$provider"
get_provider_status() {
  local run_dir=$1
  local iteration=$2
  local provider=$3

  local stage_dir=""
  for d in "$run_dir"/stage-*/iterations; do
    [ -d "$d" ] && stage_dir="$d" && break
  done

  echo "$stage_dir/$(printf '%03d' $iteration)/$provider/status.json"
}

# Assert all providers created output
# Usage: assert_all_providers_have_output "$run_dir" "$iteration" "claude" "codex"
assert_all_providers_have_output() {
  local run_dir=$1
  local iteration=$2
  shift 2
  local providers=("$@")

  for provider in "${providers[@]}"; do
    local output=$(get_provider_output "$run_dir" "$iteration" "$provider")
    assert_file_exists "$output" "Provider $provider should have output at iteration $iteration"
  done
}

#-------------------------------------------------------------------------------
# Tracks Test Helpers
#-------------------------------------------------------------------------------

# Setup tracks test environment
# Usage: setup_tracks_test "$test_dir" "tracks-dual"
setup_tracks_test() {
  local test_dir=$1
  local fixture_name=${2:-"tracks-dual"}

  setup_multi_stage_test "$test_dir" "$fixture_name"
}

# Get track directory path
# Usage: get_track_dir "$run_dir" "$stage_name" "$provider"
get_track_dir() {
  local run_dir=$1
  local stage_name=$2
  local provider=$3

  # Find stage directory by name
  local stage_dir=""
  for d in "$run_dir"/stage-*-"$stage_name"; do
    [ -d "$d" ] && stage_dir="$d" && break
  done

  echo "$stage_dir/tracks/$provider"
}

# Get track state file
# Usage: get_track_state "$run_dir" "$stage_name" "$provider"
get_track_state() {
  local track_dir=$(get_track_dir "$@")
  echo "$track_dir/state.json"
}

# Get track iteration count from state
# Usage: get_track_iteration_count "$run_dir" "$stage_name" "$provider"
get_track_iteration_count() {
  local state_file=$(get_track_state "$@")
  if [ -f "$state_file" ]; then
    jq -r '.iteration_completed // 0' "$state_file"
  else
    echo "0"
  fi
}

# Assert track outputs.json exists and is valid
# Usage: assert_track_outputs_valid "$run_dir" "$stage_name" "claude" "codex"
assert_track_outputs_valid() {
  local run_dir=$1
  local stage_name=$2
  shift 2
  local providers=("$@")

  local stage_dir=""
  for d in "$run_dir"/stage-*-"$stage_name"; do
    [ -d "$d" ] && stage_dir="$d" && break
  done

  local outputs_file="$stage_dir/outputs.json"
  assert_file_exists "$outputs_file" "outputs.json should exist for stage $stage_name"

  for provider in "${providers[@]}"; do
    local output_path=$(jq -r ".$provider.output // empty" "$outputs_file")
    assert_not_empty "$output_path" "outputs.json should contain $provider.output"
    assert_file_exists "$output_path" "Track $provider output file should exist"
  done
}
```

### Example Test Implementations

Complete, copy-paste-ready test examples showing how to use the helpers:

**Example: test_parallel.sh - test_parallel_creates_all_outputs**
```bash
#!/bin/bash
# integration/test_parallel.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/integration/harness.sh"

test_parallel_creates_all_outputs() {
  local test_dir=$(mktemp -d)

  # Setup with parallel-2 fixture
  setup_parallel_test "$test_dir" "parallel-2"

  # Run engine with parallel providers (2 iterations)
  local output
  output=$(run_mock_parallel_engine "$test_dir" "test-session" 2)
  local exit_code=$?

  # Get run directory
  local run_dir=$(get_run_dir "$test_dir" "test-session")

  # Assert both providers created output for each iteration
  for iter in 1 2; do
    assert_all_providers_have_output "$run_dir" "$iter" "claude" "codex"

    # Verify output content is provider-specific
    local claude_output=$(get_provider_output "$run_dir" "$iter" "claude")
    local codex_output=$(get_provider_output "$run_dir" "$iter" "codex")

    assert_file_contains "$claude_output" "Claude" "Claude output should contain Claude-specific content"
    assert_file_contains "$codex_output" "Codex" "Codex output should contain Codex-specific content"
  done

  # Assert engine succeeded
  assert_eq "0" "$exit_code" "Engine should exit successfully"

  # Cleanup
  teardown_integration_test "$test_dir"
}

test_parallel_waits_for_all() {
  local test_dir=$(mktemp -d)

  # Setup with parallel-2 fixture
  setup_parallel_test "$test_dir" "parallel-2"

  # Configure codex to be slow
  export MOCK_DELAY_CODEX=1
  export MOCK_DELAY=0

  # Run engine - should wait for both
  local start_time=$(date +%s)
  run_mock_parallel_engine "$test_dir" "test-session" 1 > /dev/null
  local end_time=$(date +%s)
  local elapsed=$((end_time - start_time))

  # Both providers should have run (engine waited for slow one)
  local run_dir=$(get_run_dir "$test_dir" "test-session")
  local provider_count=$(count_provider_dirs "$run_dir" 1)
  assert_eq "2" "$provider_count" "Both providers should have directories"

  # Should have taken at least 1 second (waiting for slow codex)
  assert_ge "$elapsed" "1" "Should wait for slow provider"

  unset MOCK_DELAY_CODEX
  teardown_integration_test "$test_dir"
}

# Run tests
run_test "Parallel creates all outputs" test_parallel_creates_all_outputs
run_test "Parallel waits for all providers" test_parallel_waits_for_all

test_summary
```

**Example: test_tracks.sh - test_tracks_collects_final_outputs**
```bash
#!/bin/bash
# integration/test_tracks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/integration/harness.sh"

test_tracks_collects_final_outputs() {
  local test_dir=$(mktemp -d)

  # Setup with tracks-dual fixture
  setup_tracks_test "$test_dir" "tracks-dual"

  # Run pipeline
  local output
  output=$(run_mock_pipeline "$test_dir" ".claude/pipelines/pipeline.yaml" "test-session")
  local exit_code=$?

  # Get run directory
  local run_dir=$(get_run_dir "$test_dir" "test-session")

  # Assert outputs.json exists and is valid
  assert_track_outputs_valid "$run_dir" "planning" "claude" "codex"

  # Verify iteration counts differ (each track plateaus independently)
  local outputs_file="$run_dir/stage-00-planning/outputs.json"
  local claude_iters=$(jq -r '.claude.iterations_completed' "$outputs_file")
  local codex_iters=$(jq -r '.codex.iterations_completed' "$outputs_file")

  # Claude plateaus at 3, codex at 5 (per fixture design)
  assert_eq "3" "$claude_iters" "Claude should plateau at iteration 3"
  assert_eq "5" "$codex_iters" "Codex should plateau at iteration 5"

  # Verify termination reasons
  local claude_reason=$(jq -r '.claude.termination_reason' "$outputs_file")
  local codex_reason=$(jq -r '.codex.termination_reason' "$outputs_file")

  assert_eq "plateau" "$claude_reason" "Claude should stop due to plateau"
  assert_eq "plateau" "$codex_reason" "Codex should stop due to plateau"

  # Assert engine succeeded
  assert_eq "0" "$exit_code" "Engine should exit successfully"

  teardown_integration_test "$test_dir"
}

test_tracks_waits_for_all_on_failure() {
  local test_dir=$(mktemp -d)

  # Setup with tracks-dual-fail fixture (or modify tracks to have one fail)
  setup_tracks_test "$test_dir" "tracks-dual"

  # Inject failure: create an invalid status.json for one track
  local fixture_dir="$test_dir/stages/test-plan/fixtures/claude"
  mkdir -p "$fixture_dir"
  echo '{"decision": "error", "reason": "simulated failure"}' > "$fixture_dir/status-002.json"

  # Run pipeline - should fail but wait for all
  local output
  output=$(run_mock_pipeline "$test_dir" ".claude/pipelines/pipeline.yaml" "test-session" 2>&1)
  local exit_code=$?

  # Should have failed
  assert_neq "0" "$exit_code" "Engine should fail when track fails"

  # But codex track should still have completed
  local run_dir=$(get_run_dir "$test_dir" "test-session")
  local codex_state=$(get_track_state "$run_dir" "planning" "codex")

  # Codex should have iterations (waited for it)
  local codex_iters=$(get_track_iteration_count "$run_dir" "planning" "codex")
  assert_gt "$codex_iters" "0" "Codex should have completed iterations before failure reported"

  teardown_integration_test "$test_dir"
}

# Run tests
run_test "Tracks collects final outputs" test_tracks_collects_final_outputs
run_test "Tracks waits for all on failure" test_tracks_waits_for_all_on_failure

test_summary
```

---

## Acceptance Criteria

### Providers (Comparison Mode)
- [ ] `providers: [claude, codex]` runs both in parallel on same iteration
- [ ] Each provider writes to isolated directory
- [ ] `inputs.providers` available in context.json for next stage
- [ ] Validation error if `providers:` with judgment termination
- [ ] Validation error if provider CLI missing (preflight)
- [ ] `provider: claude` (single) continues unchanged

### Tracks (Independent Loops Mode)
- [ ] `tracks:` spawns independent iteration loops per provider
- [ ] Each track iterates until its own termination condition
- [ ] Stage completes when ALL tracks finish
- [ ] `inputs.tracks` available in context.json for next stage
- [ ] Each track has isolated state.json and iterations directory
- [ ] Validation error if `tracks:` combined with `providers:`

---

## Acceptance Criteria → Test Mapping

Each acceptance criterion MUST have at least one test. This mapping ensures complete coverage:

| Acceptance Criterion | Test Function | Test File |
|---------------------|---------------|-----------|
| `providers: [claude, codex]` runs both in parallel | `test_parallel_spawns_all_providers` | integration/test_parallel.sh |
| Each provider writes to isolated directory | `test_parallel_creates_provider_subdirs`, `test_parallel_provider_dirs_contain_output` | test_context.sh |
| `inputs.providers` available in context.json | `test_context_providers_in_inputs`, `test_context_providers_has_output_paths` | test_context.sh |
| Validation error if `providers:` with judgment | `test_validation_providers_rejects_judgment` | test_validation.sh |
| Validation error if provider CLI missing | `test_validation_providers_preflight_checks_all` | test_validation.sh |
| `provider: claude` continues unchanged | All existing provider tests (regression) | test_providers.sh |
| `tracks:` spawns independent loops | `test_tracks_spawns_independent_loops` | integration/test_tracks.sh |
| Each track iterates until own termination | `test_tracks_each_has_own_termination` | integration/test_tracks.sh |
| Stage completes when ALL tracks finish | `test_tracks_stage_completes_when_all_done` | integration/test_tracks.sh |
| `inputs.tracks` available in context.json | `test_context_tracks_in_inputs`, `test_context_tracks_has_final_output` | test_context.sh |
| Each track has isolated state.json/iterations | `test_tracks_each_has_own_state`, `test_tracks_each_has_own_iterations` | test_context.sh |
| Validation error if `tracks:` combined with `providers:` | `test_validation_providers_and_tracks_exclusive` | test_validation.sh |

---

## Additional Test Scenarios (TDD Gap Analysis)

These tests were identified during TDD review to fill coverage gaps:

### Phase 5.6: Progress File Isolation Tests (test_context.sh)

```bash
test_parallel_each_provider_has_progress_file()
# Config: providers: [claude, codex]
# Expected: iterations/001/claude/progress.md exists (provider-isolated)
# Expected: iterations/001/codex/progress.md exists (provider-isolated)
# Note: Each provider reads its OWN progress, not cross-contaminated

test_parallel_progress_not_shared()
# Run iteration 1, claude writes to progress
# Run iteration 2, verify codex doesn't see claude's progress content
# Expected: Provider isolation is complete

test_tracks_each_has_own_progress_file()
# Config: tracks with claude and codex
# Expected: tracks/claude/progress.md independent from tracks/codex/progress.md
```

### Phase 5.7: Crash Recovery Tests for Parallel (integration/test_parallel.sh)

```bash
test_parallel_crash_during_provider_execution()
# Simulate crash: claude completes, codex crashes mid-execution
# Expected: State shows partial completion
# Resume expected: Both providers re-run for that iteration (atomic iteration)

test_parallel_resume_replays_failed_iteration()
# Setup: State shows iteration 2 started but not completed
# Resume: Should replay iteration 2 for ALL providers (even if some succeeded)
# Reason: Can't know which providers actually completed

test_parallel_crash_preserves_successful_iterations()
# Complete iterations 1-2, crash during iteration 3
# Resume: iterations 1-2 outputs preserved, iteration 3 re-runs
# Expected: No double-running of successful iterations
```

### Phase 5.8: Exit Code Aggregation Tests (integration/test_parallel.sh)

```bash
test_parallel_exit_code_zero_when_all_succeed()
# All providers succeed (exit 0)
# Expected: Engine exits 0

test_parallel_exit_code_nonzero_when_any_fails()
# Claude succeeds (exit 0), Codex fails (exit 1)
# Expected: Engine exits non-zero

test_parallel_exit_code_reflects_first_failure()
# Multiple providers fail with different exit codes
# Expected: Engine exits with first non-zero code encountered
```

### Phase 5.9: Context.json Provider Visibility Tests (test_context.sh)

```bash
test_context_iteration_2_sees_iteration_1_all_providers()
# After iteration 1 completes with [claude, codex]
# Iteration 2 context.json should have inputs.from_previous_iterations
# Expected: Contains paths to BOTH claude/output.md and codex/output.md from iter 1

test_context_provider_sees_own_previous_not_others_same_iteration()
# During iteration N, provider should NOT see other providers' outputs FROM SAME iteration
# (They run in parallel - can't see each other)
# Expected: No cross-contamination within single iteration
```

### Phase 5.10: Timeout and Hung Provider Tests (integration/test_parallel.sh)

```bash
test_parallel_timeout_kills_hung_provider()
# Configure: MOCK_DELAY_CODEX=999 (simulates hung)
# Expected: Engine should timeout after configured max time
# Expected: Both providers' processes are terminated
# Note: v1 may not have timeout - document if skipped

test_parallel_one_slow_one_fast()
# Configure: MOCK_DELAY_CLAUDE=0, MOCK_DELAY_CODEX=5
# Expected: Engine waits for slow provider (codex)
# Expected: Fast provider (claude) output not lost
```

### Phase 6.2: Regression Tests for Existing Behavior

```bash
test_single_provider_unchanged_directory_structure()
# Config: provider: "claude" (not providers array)
# Expected: iterations/001/output.md (NOT iterations/001/claude/output.md)
# Ensures single-provider mode doesn't change directory structure

test_single_provider_context_unchanged()
# Config: provider: "claude"
# Expected: context.json has NO inputs.providers field
# Expected: context.json structure matches pre-parallel-feature format

test_all_existing_tests_still_pass()
# Meta-test: run full existing test suite
# Expected: 0 failures - confirms no regressions
```

---

## Pre-Implementation Test Verification

Before writing ANY implementation code, verify:

### Phase 1 Tests Ready to Write
```bash
# Create test_validation.sh additions (these define the contract)
./scripts/tests/run_tests.sh validation

# These should ALL FAIL initially (feature not implemented)
- test_validation_provider_and_providers_exclusive → FAIL expected
- test_validation_providers_rejects_judgment → FAIL expected
- test_validation_track_requires_provider → FAIL expected
```

### Test Execution Commands
```bash
# Run specific phase tests
./scripts/tests/run_tests.sh unit             # Phases 1-4
./scripts/tests/run_tests.sh integration      # Phases 5-6

# Run new parallel tests only (after files created)
./scripts/tests/test_validation.sh            # Phase 1
./scripts/tests/test_providers.sh             # Phase 2
./scripts/tests/test_context.sh               # Phases 3-4
./scripts/tests/integration/test_parallel.sh  # Phase 5 parallel
./scripts/tests/integration/test_tracks.sh    # Phase 5 tracks

# Full regression
./scripts/tests/run_tests.sh
```

---

## Test-First Implementation Checklist

Use this checklist for each sprint. DO NOT proceed to implementation until tests are written.

### Sprint 1: Validation (Phase 1)
- [ ] Write `test_validation_provider_and_providers_exclusive` → verify it fails
- [ ] Write `test_validation_providers_rejects_judgment` → verify it fails
- [ ] Write `test_validation_providers_rejects_plateau` → verify it fails
- [ ] Write `test_validation_providers_accepts_fixed` → verify it fails
- [ ] Write `test_validation_provider_and_tracks_exclusive` → verify it fails
- [ ] Write `test_validation_providers_and_tracks_exclusive` → verify it fails
- [ ] Write `test_validation_track_requires_provider` → verify it fails
- [ ] Write `test_validation_track_requires_loop` → verify it fails
- [ ] Write `test_validation_track_validates_loop_exists` → verify it fails
- [ ] Write `test_validation_providers_preflight_checks_all` → verify it fails
- [ ] **IMPLEMENT**: Add validation logic to `validate.sh`
- [ ] Re-run all Phase 1 tests → all should PASS
- [ ] Run existing validation tests → all should PASS (regression)

### Sprint 2: Provider Abstraction (Phase 2)
- [ ] Write all `test_get_providers_list_*` tests → verify they fail
- [ ] Write all `test_validate_providers_*` tests → verify they fail
- [ ] **IMPLEMENT**: Add functions to `provider.sh`
- [ ] Re-run all Phase 2 tests → all should PASS
- [ ] Run existing provider tests → all should PASS (regression)

### Sprint 3: Directory & Context (Phases 3-4)
- [ ] Write all directory structure tests → verify they fail
- [ ] Write all context.json extension tests → verify they fail
- [ ] **IMPLEMENT**: Update `engine.sh` for directory creation
- [ ] **IMPLEMENT**: Update `context.sh` for provider inputs
- [ ] Re-run all Phase 3-4 tests → all should PASS
- [ ] Run existing context tests → all should PASS (regression)

### Sprint 4: Parallel Execution (Phase 5 - parallel)
- [ ] Create `scripts/tests/integration/test_parallel.sh` (NEW FILE)
- [ ] Create `scripts/tests/fixtures/integration/parallel-2/` fixture
- [ ] Write all parallel execution tests → verify they fail
- [ ] **IMPLEMENT**: Add `execute_parallel_providers()` to `engine.sh`
- [ ] Re-run all parallel tests → all should PASS
- [ ] Run existing integration tests → all should PASS (regression)

### Sprint 5: Tracks Execution (Phase 5 - tracks)
- [ ] Create `scripts/tests/integration/test_tracks.sh` (NEW FILE)
- [ ] Create `scripts/tests/fixtures/integration/tracks-dual/` fixture
- [ ] Write all tracks tests → verify they fail
- [ ] **IMPLEMENT**: Add `run_tracks()` to `engine.sh`
- [ ] Re-run all tracks tests → all should PASS
- [ ] Run existing integration tests → all should PASS (regression)

### Sprint 6: Integration (Phase 6)
- [ ] Write `test_pipeline_parallel_to_single` → verify it fails
- [ ] Write `test_pipeline_tracks_to_single` → verify it fails
- [ ] Write regression tests → should already PASS
- [ ] Fix any integration issues
- [ ] **FULL TEST SUITE**: `./scripts/tests/run_tests.sh` → ALL PASS

---

## Definition of Done

A feature is DONE when:

1. [ ] All Phase 1-6 tests are written and passing
2. [ ] All existing tests still pass (zero regressions)
3. [ ] Test coverage includes:
   - Happy path (normal execution)
   - Error paths (validation failures, provider failures)
   - Edge cases (single-item array, empty array, timing)
   - Resume/crash recovery scenarios
4. [ ] Mock infrastructure updated with per-provider support
5. [ ] Harness helpers added for parallel/tracks testing
6. [ ] New fixtures created:
   - `scripts/tests/fixtures/integration/parallel-2/`
   - `scripts/tests/fixtures/integration/tracks-dual/`
7. [ ] Implementation matches test expectations exactly

---

## Appendix A: Available Test Assertions (from test.sh)

The existing `scripts/lib/test.sh` provides these assertions - use them in new tests:

| Assertion | Usage | Purpose |
|-----------|-------|---------|
| `assert_eq` | `assert_eq "expected" "$actual" "message"` | Values should be equal |
| `assert_neq` | `assert_neq "not_expected" "$actual" "message"` | Values should not be equal |
| `assert_gt` | `assert_gt "$actual" "$threshold" "message"` | Value > threshold |
| `assert_ge` | `assert_ge "$actual" "$threshold" "message"` | Value >= threshold |
| `assert_le` | `assert_le "$actual" "$threshold" "message"` | Value <= threshold |
| `assert_file_exists` | `assert_file_exists "/path/file"` | File should exist |
| `assert_file_not_exists` | `assert_file_not_exists "/path/file"` | File should not exist |
| `assert_dir_exists` | `assert_dir_exists "/path/dir"` | Directory should exist |
| `assert_json_field` | `assert_json_field "file.json" ".field" "expected"` | JSON field equals value |
| `assert_json_field_exists` | `assert_json_field_exists "file.json" ".field"` | JSON field exists |
| `assert_contains` | `assert_contains "$haystack" "needle" "message"` | String contains substring |
| `assert_not_contains` | `assert_not_contains "$haystack" "needle" "message"` | String doesn't contain |
| `assert_true` | `assert_true "$condition" "message"` | Condition is truthy |
| `assert_false` | `assert_false "$condition" "message"` | Condition is falsy |
| `assert_or_skip` | `assert_or_skip "$condition" "pass_msg" "skip_msg"` | Pass or skip (not fail) |

**New helpers to add to harness.sh** (documented in "Harness Updates" section):
- `count_provider_dirs` - Count provider directories in an iteration
- `get_provider_output` / `get_provider_status` - Get provider-specific file paths
- `assert_all_providers_have_output` - Verify all providers created output
- `get_track_dir` / `get_track_state` / `get_track_iteration_count` - Track-specific helpers
- `assert_track_outputs_valid` - Verify outputs.json is valid

---

## Appendix B: State.json Structure for Parallel

**Single-provider state.json (unchanged):**
```json
{
  "session": "my-session",
  "type": "loop",
  "started_at": "2025-01-10T10:00:00Z",
  "status": "running",
  "iteration": 3,
  "iteration_completed": 2,
  "history": [
    {"iteration": 1, "decision": "continue"},
    {"iteration": 2, "decision": "continue"}
  ]
}
```

**Parallel providers state.json:**
```json
{
  "session": "my-session",
  "type": "loop",
  "started_at": "2025-01-10T10:00:00Z",
  "status": "running",
  "providers": ["claude", "codex"],
  "iteration": 3,
  "iteration_completed": 2,
  "history": [
    {"iteration": 1, "providers": {"claude": "continue", "codex": "continue"}},
    {"iteration": 2, "providers": {"claude": "continue", "codex": "continue"}}
  ]
}
```

**Key differences:**
- `providers` field lists active providers
- `history` entries include per-provider decisions
- Iteration is atomic - either ALL providers complete or none do (for crash recovery)

**Tests for state.json:**
```bash
test_parallel_state_has_providers_field()
# Expected: state.json has "providers": ["claude", "codex"]

test_parallel_state_history_per_provider()
# Expected: history entries have providers.claude and providers.codex

test_parallel_state_atomic_iteration()
# On crash mid-iteration: state.iteration > state.iteration_completed
# Resume replays full iteration for ALL providers
```

---

## Appendix C: End-to-End Synthesize Stage Test

This test verifies the full pipeline flow: parallel/tracks stage → synthesize stage using outputs.

**test_pipeline_tracks_synthesize_uses_all_outputs:**
```bash
test_pipeline_tracks_synthesize_uses_all_outputs() {
  local test_dir=$(mktemp -d)

  # Setup with tracks-dual fixture
  setup_tracks_test "$test_dir" "tracks-dual"

  # Run full pipeline (planning → synthesize)
  run_mock_pipeline "$test_dir" ".claude/pipelines/pipeline.yaml" "test-session"
  local exit_code=$?

  # Get run directory
  local run_dir=$(get_run_dir "$test_dir" "test-session")

  # Verify synthesize stage received both track outputs
  local synth_context="$run_dir/stage-01-synthesize/iterations/001/context.json"
  assert_file_exists "$synth_context" "Synthesize context.json exists"

  # Check inputs.tracks contains both providers
  local claude_output=$(jq -r '.inputs.tracks.claude.output' "$synth_context")
  local codex_output=$(jq -r '.inputs.tracks.codex.output' "$synth_context")

  assert_not_empty "$claude_output" "inputs.tracks.claude.output should be set"
  assert_not_empty "$codex_output" "inputs.tracks.codex.output should be set"

  # Verify the output files exist and are readable
  assert_file_exists "$claude_output" "Claude track output file exists"
  assert_file_exists "$codex_output" "Codex track output file exists"

  # Verify iteration counts are passed through
  local claude_iters=$(jq -r '.inputs.tracks.claude.iterations_completed' "$synth_context")
  local codex_iters=$(jq -r '.inputs.tracks.codex.iterations_completed' "$synth_context")

  assert_gt "$claude_iters" "0" "Claude iterations should be recorded"
  assert_gt "$codex_iters" "0" "Codex iterations should be recorded"

  # Engine should succeed
  assert_eq "0" "$exit_code" "Pipeline should complete successfully"

  teardown_integration_test "$test_dir"
}
```

**Helper function needed:**
```bash
assert_not_empty() {
  local value=$1
  local msg=${2:-"Value should not be empty"}

  if [ -n "$value" ] && [ "$value" != "null" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg (got: '$value')"
    return 1
  fi
}
```
