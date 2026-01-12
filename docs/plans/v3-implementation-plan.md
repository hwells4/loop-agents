# Loop Agents v3 Implementation Plan

## Overview

This plan details the implementation of the Loop Agents v3 architecture, transforming the current system from a variable-based template resolution to a unified context manifest approach. The goal is to make the system so standardized that agents can create new pipelines without making mistakes.

**Key Changes:**
1. Context manifest (`context.json`) replacing 9+ template variables
2. Universal status format (`decision: continue|stop|error`)
3. Engine-side output snapshots (remove `output.mode` config)
4. Keep progress file (no changes needed)
5. Explicit input selection (`inputs.from`, `inputs.select`)
6. Fail fast (remove retry logic, write clear failure state)

**Approach:** Test-Driven Development with existing infrastructure

---

## Existing Test Infrastructure

The codebase already has validation tools we can leverage:

| Tool | Command | Purpose |
|------|---------|---------|
| **Lint** | `./scripts/run.sh lint` | Validate all loop/pipeline configs |
| **Lint specific** | `./scripts/run.sh lint loop work` | Validate one loop |
| **Dry-run** | `./scripts/run.sh dry-run loop work auth` | Preview execution without Claude |
| **Status** | `./scripts/run.sh status <session>` | Check session state |

**Validation rules defined in `scripts/lib/validate.sh`:**
- L001-L013: Loop validation rules
- P001-P012: Pipeline validation rules

### TDD Strategy

For each phase:
1. **Update validation rules first** - Add new rules for v3 schema
2. **Write tests that fail** - Dry-run should show new format works
3. **Implement the change** - Make tests pass
4. **Run lint on all stages** - Ensure nothing broke

---

## Current State Analysis

### Files to Modify

| File | Lines | Changes Needed |
|------|-------|----------------|
| `scripts/engine.sh` | 600 | Major rewrite of iteration loop, add context.json generation |
| `scripts/lib/resolve.sh` | 145 | Replace with context.json generator, deprecate old variables |
| `scripts/lib/state.sh` | 197 | Add status.json integration, update state schema |
| `scripts/lib/completions/plateau.sh` | 47 | Read `decision` from status.json instead of parsing output |
| `scripts/lib/completions/beads-empty.sh` | 29 | Minor: integrate with new status format |
| `scripts/lib/completions/fixed-n.sh` | 19 | Minor: integrate with new status format |
| `scripts/lib/progress.sh` | 58 | No changes (kept as-is) |
| `scripts/lib/parse.sh` | 43 | Deprecate in favor of status.json reading |
| `scripts/loops/*/loop.yaml` | 5 files | Update schema (new termination block) |
| `scripts/loops/*/prompt.md` | 4 files | Update to use `${CTX}` and write status.json |
| `scripts/pipelines/*.yaml` | 3 files | Add `inputs` configuration |

### Current Variable Usage (to be replaced)

From `resolve.sh`, the current variables are:
- `${SESSION}` / `${SESSION_NAME}` → `context.session`
- `${ITERATION}` → `context.iteration`
- `${INDEX}` → Not needed (0-indexed iteration)
- `${PROGRESS}` / `${PROGRESS_FILE}` → `context.paths.progress`
- `${OUTPUT}` → `context.paths.output`
- `${OUTPUT_PATH}` → Merge with `context.paths.output`
- `${INPUTS}` / `${INPUTS.stage-name}` → `context.inputs.from_stage.*`

---

## Implementation Phases

### Phase 0: Test Harness Enhancement ✅ COMPLETE

**Goal:** Extend existing validation to support v3 and add mock execution for integration tests.

**Completed 2025-01-11:**
- Created `scripts/lib/test.sh` with 15+ assertion functions
- Created `scripts/lib/mock.sh` for mock Claude execution
- Added `./scripts/run.sh test` command
- Created fixtures for all 5 loops (work, improve-plan, elegance, idea-wizard, refine-beads)
- Created 4 test files with 90 passing tests
- Verified: `./scripts/run.sh test` and `./scripts/run.sh lint` both pass

#### 0.1 Add v3 Validation Rules

**File:** `scripts/lib/validate.sh` (extend)

Add new validation rules for v3 schema:

```bash
# V3 validation rules (add to KNOWN_VARS)
KNOWN_VARS_V3="CTX PROGRESS OUTPUT STATUS"

# L014: v3 stages should use termination block
# L015: v3 stages should not use output_parse (deprecated)
# L016: prompts should reference ${STATUS} for status output
# L017: prompts should reference ${CTX} for context

validate_loop_v3() {
  # ... check for new termination block
  # ... check for deprecated output_parse
  # ... check prompt uses new variables
}
```

#### 0.2 Add Mock Execution Mode

**File:** `scripts/lib/mock.sh` (new file)

```bash
#!/bin/bash
# Mock execution for testing

MOCK_MODE=false
MOCK_DIR=""

# Enable mock mode with fixture directory
enable_mock() {
  MOCK_MODE=true
  MOCK_DIR=$1
}

# Get mock response for iteration
get_mock_response() {
  local iteration=$1
  local fixture_file="$MOCK_DIR/iteration-${iteration}.txt"

  if [ -f "$fixture_file" ]; then
    cat "$fixture_file"
  elif [ -f "$MOCK_DIR/default.txt" ]; then
    cat "$MOCK_DIR/default.txt"
  else
    # Generate minimal valid response
    echo '{"decision": "continue", "reason": "Mock response"}'
  fi
}
```

#### 0.3 Add Test Command

**File:** `scripts/run.sh` (extend)

```bash
test)
  source "$LIB_DIR/validate.sh"
  source "$LIB_DIR/mock.sh"
  shift
  # ... run with mock responses
  ;;
```

#### 0.4 Create Fixture Templates

**Directory:** `scripts/loops/*/fixtures/`

Create default fixtures for each loop type:

```
scripts/loops/work/fixtures/
├── default.txt          # Default mock response
└── status.json          # Expected status format

scripts/loops/improve-plan/fixtures/
├── iteration-1.txt      # First iteration response
├── iteration-2.txt      # Second iteration (plateau)
└── status.json          # Expected status format
```

#### Success Criteria - Phase 0

- [ ] `./scripts/run.sh lint` passes with all current stages
- [ ] `./scripts/run.sh lint --v3` validates v3 schema rules
- [ ] `./scripts/run.sh test loop work --iterations 2` runs with mock responses
- [ ] Each loop has a `fixtures/` directory with default responses

---

### Phase 1: Context Manifest (`context.json`)

**Goal:** Replace 9+ template variables with a single structured JSON file.

#### 1.1 Create Context Generator

**File:** `scripts/lib/context.sh` (new file)

```bash
#!/bin/bash
# Context Manifest Generator
# Creates context.json for each iteration

# Generate context.json for an iteration
# Usage: generate_context "$session" "$iteration" "$stage_config" "$run_dir"
generate_context() {
  local session=$1
  local iteration=$2
  local stage_config=$3  # JSON object
  local run_dir=$4

  local stage_id=$(echo "$stage_config" | jq -r '.id // .name')
  local stage_idx=$(echo "$stage_config" | jq -r '.index // 0')
  local stage_template=$(echo "$stage_config" | jq -r '.template // .loop // ""')

  # Paths
  local stage_dir="$run_dir/stage-$(printf '%02d' $stage_idx)-$stage_id"
  local iter_dir="$stage_dir/iterations/$(printf '%03d' $iteration)"
  local progress_file="$stage_dir/progress.md"
  local output_file="$stage_dir/output.md"
  local status_file="$iter_dir/status.json"

  mkdir -p "$iter_dir"

  # Build inputs (from previous stage and previous iterations)
  local inputs_json=$(build_inputs_json "$run_dir" "$stage_config" "$iteration")

  # Build limits
  local max_iterations=$(echo "$stage_config" | jq -r '.max_iterations // 50')
  local started_at=$(jq -r '.started_at // ""' "$run_dir/state.json" 2>/dev/null)
  local remaining_seconds=$(calculate_remaining_time "$started_at" "$stage_config")

  # Generate context.json
  jq -n \
    --arg session "$session" \
    --arg pipeline "$(jq -r '.pipeline // ""' "$run_dir/state.json" 2>/dev/null)" \
    --arg stage_id "$stage_id" \
    --argjson stage_idx "$stage_idx" \
    --arg template "$stage_template" \
    --argjson iteration "$iteration" \
    --arg session_dir "$run_dir" \
    --arg stage_dir "$stage_dir" \
    --arg progress "$progress_file" \
    --arg output "$output_file" \
    --arg status "$status_file" \
    --argjson inputs "$inputs_json" \
    --argjson max_iterations "$max_iterations" \
    --argjson remaining "$remaining_seconds" \
    '{
      session: $session,
      pipeline: $pipeline,
      stage: {id: $stage_id, index: $stage_idx, template: $template},
      iteration: $iteration,
      paths: {
        session_dir: $session_dir,
        stage_dir: $stage_dir,
        progress: $progress,
        output: $output,
        status: $status
      },
      inputs: $inputs,
      limits: {
        max_iterations: $max_iterations,
        remaining_seconds: $remaining
      }
    }' > "$iter_dir/context.json"

  echo "$iter_dir/context.json"
}
```

**Functions to add:**
- `generate_context()` - Main context generator
- `build_inputs_json()` - Build inputs object based on `inputs.from` and `inputs.select`
- `calculate_remaining_time()` - Calculate remaining runtime

#### 1.2 Update Prompt Resolution

**File:** `scripts/lib/resolve.sh` (modify)

Replace the existing implementation:

```bash
#!/bin/bash
# Context-Based Variable Resolution (v3)
# Resolves only 4 convenience variables; full context via ${CTX}

resolve_prompt() {
  local template=$1
  local context_file=$2  # Path to context.json

  local resolved="$template"

  # Read context
  local ctx=$(cat "$context_file")

  # Resolve 4 convenience paths
  local progress=$(echo "$ctx" | jq -r '.paths.progress')
  local output=$(echo "$ctx" | jq -r '.paths.output')
  local status=$(echo "$ctx" | jq -r '.paths.status')

  resolved="${resolved//\$\{CTX\}/$context_file}"
  resolved="${resolved//\$\{PROGRESS\}/$progress}"
  resolved="${resolved//\$\{OUTPUT\}/$output}"
  resolved="${resolved//\$\{STATUS\}/$status}"

  # DEPRECATED: Keep old variables working during migration
  local session=$(echo "$ctx" | jq -r '.session')
  local iteration=$(echo "$ctx" | jq -r '.iteration')
  resolved="${resolved//\$\{SESSION\}/$session}"
  resolved="${resolved//\$\{SESSION_NAME\}/$session}"
  resolved="${resolved//\$\{ITERATION\}/$iteration}"
  resolved="${resolved//\$\{PROGRESS_FILE\}/$progress}"

  echo "$resolved"
}
```

#### 1.3 Update Engine to Generate Context

**File:** `scripts/engine.sh` (modify `run_stage` function)

Add context generation before prompt resolution:

```bash
# In run_stage(), before executing Claude:

# Generate context.json for this iteration
local context_file=$(generate_context "$session" "$i" "$stage_config_json" "$run_dir")

# Resolve prompt using context file
local resolved_prompt=$(resolve_prompt "$LOOP_PROMPT" "$context_file")
```

#### Success Criteria - Phase 1

- [ ] `context.json` is generated in `iterations/NNN/` before each iteration
- [ ] Prompts can use `${CTX}` to read the context file
- [ ] Old variables (`${SESSION}`, `${ITERATION}`, etc.) still work (deprecated)
- [ ] Test: Run `./scripts/run.sh work test-session 3` and verify `context.json` files exist

---

### Phase 2: Universal Status Format

**Goal:** Every agent writes the same `status.json` format with `decision: continue|stop|error`.

#### 2.1 Define Status Schema

**File:** `scripts/lib/status.sh` (new file)

```bash
#!/bin/bash
# Status File Management
# Handles the universal status.json format

# Validate status.json
# Usage: validate_status "$status_file"
# Returns: 0 if valid, 1 if invalid
validate_status() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "Error: Status file not found: $status_file" >&2
    return 1
  fi

  local decision=$(jq -r '.decision // "missing"' "$status_file" 2>/dev/null)

  case "$decision" in
    continue|stop|error) return 0 ;;
    missing)
      echo "Error: Status file missing 'decision' field" >&2
      return 1
      ;;
    *)
      echo "Error: Invalid decision value: $decision (must be continue|stop|error)" >&2
      return 1
      ;;
  esac
}

# Read status decision
# Usage: get_status_decision "$status_file"
get_status_decision() {
  local status_file=$1
  jq -r '.decision // "continue"' "$status_file" 2>/dev/null
}

# Read status reason
# Usage: get_status_reason "$status_file"
get_status_reason() {
  local status_file=$1
  jq -r '.reason // ""' "$status_file" 2>/dev/null
}

# Create error status (when agent crashes or times out)
# Usage: create_error_status "$status_file" "$error_message"
create_error_status() {
  local status_file=$1
  local error=$2
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  jq -n \
    --arg error "$error" \
    --arg ts "$timestamp" \
    '{
      decision: "error",
      reason: $error,
      summary: "Iteration failed due to error",
      work: {items_completed: [], files_touched: []},
      errors: [$error],
      timestamp: $ts
    }' > "$status_file"
}
```

#### 2.2 Update Completion Strategies

**File:** `scripts/lib/completions/plateau.sh` (rewrite)

```bash
#!/bin/bash
# Completion strategy: judgment (plateau)
# Requires N consecutive agents to write decision: stop

check_completion() {
  local session=$1
  local state_file=$2
  local status_file=$3  # Now receives status file path

  # Get configurable consensus count (default 2)
  local consensus_needed=${CONSENSUS:-2}
  local min_iterations=${MIN_ITERATIONS:-2}

  # Read current iteration
  local iteration=$(get_state "$state_file" "iteration")

  # Must hit minimum iterations first
  if [ "$iteration" -lt "$min_iterations" ]; then
    return 1
  fi

  # Read current decision from status.json
  local decision=$(get_status_decision "$status_file")

  if [ "$decision" = "stop" ]; then
    # Count consecutive "stop" decisions from history
    local history=$(get_history "$state_file")
    local consecutive=1

    # Check previous iterations for consecutive stops
    for ((i = iteration - 1; i >= 1 && consecutive < consensus_needed; i--)); do
      local prev_decision=$(echo "$history" | jq -r ".[$((i-1))].decision // \"continue\"")
      if [ "$prev_decision" = "stop" ]; then
        ((consecutive++))
      else
        break
      fi
    done

    if [ "$consecutive" -ge "$consensus_needed" ]; then
      local reason=$(get_status_reason "$status_file")
      echo "Consensus reached: $consecutive consecutive agents agree to stop"
      echo "  Reason: $reason"
      return 0
    else
      echo "Stop suggested but not confirmed ($consecutive/$consensus_needed needed)"
      return 1
    fi
  fi

  return 1
}
```

**File:** `scripts/lib/completions/beads-empty.sh` (update)

```bash
#!/bin/bash
# Completion strategy: queue (beads-empty)
# Complete when external queue is empty

check_completion() {
  local session=$1
  local state_file=$2
  local status_file=$3

  # Check if agent reported error
  local decision=$(get_status_decision "$status_file" 2>/dev/null)
  if [ "$decision" = "error" ]; then
    return 1  # Don't complete on error
  fi

  local remaining=$(bd ready --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")

  if [ "$remaining" -eq 0 ]; then
    echo "All beads complete"
    return 0
  fi

  return 1
}
```

#### 2.3 Update Stage Schema

**Current format (v2):**
```yaml
name: improve-plan
completion: plateau
min_iterations: 2
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

**New format (v3):**
```yaml
name: improve-plan
description: Iteratively improve a plan document

termination:
  type: judgment          # judgment | queue | fixed
  min_iterations: 2
  consensus: 2            # Consecutive "stop" decisions needed

guardrails:
  max_iterations: 50
  max_runtime_seconds: 7200
```

#### 2.4 Update All Prompt Templates

Each prompt must instruct the agent to write `status.json`:

```markdown
## Status Output

After completing your work, write your status to `${STATUS}`:

\`\`\`json
{
  "decision": "continue",  // or "stop" or "error"
  "reason": "Brief explanation of why",
  "summary": "One paragraph describing what happened this iteration",
  "work": {
    "items_completed": [],
    "files_touched": ["path/to/file.ts"]
  },
  "errors": []
}
\`\`\`

**Decision guide:**
- `"continue"` - More work needed
- `"stop"` - Work is complete, no more improvements possible
- `"error"` - Something went wrong that needs investigation
```

#### Success Criteria - Phase 2

- [ ] All prompts instruct agents to write `status.json`
- [ ] Completion strategies read from `status.json` instead of parsing output
- [ ] Stage configs use new `termination` block
- [ ] Test: Run `./scripts/run.sh improve-plan test 5` and verify `status.json` files are created
- [ ] Test: Verify plateau detection works with new format

---

### Phase 3: Engine-Side Output Snapshots

**Goal:** Engine automatically saves iteration outputs to `iterations/NNN/output.md`.

#### 3.1 Update Engine Iteration Loop

**File:** `scripts/engine.sh` (modify `run_stage` function)

After Claude execution, copy output to iteration directory:

```bash
# In run_stage(), after execute_claude:

# Save output snapshot to iteration directory
local iter_dir="$stage_dir/iterations/$(printf '%03d' $i)"
if [ -f "$output_file" ]; then
  cp "$output_file" "$iter_dir/output.md"
fi

# Save status.json to iteration (agent writes to ${STATUS})
# Engine validates it exists and is well-formed
local status_file="$iter_dir/status.json"
if [ ! -f "$status_file" ]; then
  # Agent didn't write status - create error status
  create_error_status "$status_file" "Agent did not write status.json"
fi
```

#### 3.2 Remove `output.mode` from Schema

**Files to update:**
- `scripts/loops/*/loop.yaml` - Remove any `output:` blocks with `mode:`
- `scripts/engine.sh` - Remove mode-based output handling

**New simplified schema:**
```yaml
# Stage only specifies WHERE, not HOW
output: docs/plan-${SESSION}.md   # Tracked in repo
# or
output: .claude                    # Internal only (default)
```

#### Success Criteria - Phase 3

- [ ] Every iteration has `iterations/NNN/output.md` snapshot
- [ ] `output.mode` config removed from all stages
- [ ] Stage config only specifies output location, not versioning
- [ ] Test: Run multiple iterations and verify output history is preserved

---

### Phase 4: Explicit Input Selection

**Goal:** Stages explicitly declare what inputs they want from previous stages.

#### 4.1 Add Input Resolution to Context Generator

**File:** `scripts/lib/context.sh` (add function)

```bash
# Build inputs JSON based on pipeline config
# Usage: build_inputs_json "$run_dir" "$stage_config" "$iteration"
build_inputs_json() {
  local run_dir=$1
  local stage_config=$2
  local iteration=$3

  local inputs_from=$(echo "$stage_config" | jq -r '.inputs.from // ""')
  local inputs_select=$(echo "$stage_config" | jq -r '.inputs.select // "latest"')

  local from_stage="{}"
  local from_iterations="[]"

  # Collect from previous stage
  if [ -n "$inputs_from" ]; then
    local source_dir=$(find "$run_dir" -maxdepth 1 -type d -name "stage-*-$inputs_from" | head -1)

    if [ -d "$source_dir" ]; then
      case "$inputs_select" in
        all)
          # Get all iteration outputs
          from_stage=$(jq -n --arg name "$inputs_from" --arg dir "$source_dir" \
            '{($name): [($dir + "/iterations/*/output.md") | @sh]}')
          ;;
        latest)
          # Get only the latest output
          local latest=$(ls -1 "$source_dir/iterations" 2>/dev/null | sort -n | tail -1)
          if [ -n "$latest" ]; then
            from_stage=$(jq -n --arg name "$inputs_from" \
              --arg file "$source_dir/iterations/$latest/output.md" \
              '{($name): [$file]}')
          fi
          ;;
      esac
    fi
  fi

  # Collect from previous iterations of current stage
  local stage_idx=$(echo "$stage_config" | jq -r '.index // 0')
  local stage_id=$(echo "$stage_config" | jq -r '.id // .name')
  local current_stage_dir="$run_dir/stage-$(printf '%02d' $stage_idx)-$stage_id"

  if [ "$iteration" -gt 1 ] && [ -d "$current_stage_dir/iterations" ]; then
    from_iterations=$(find "$current_stage_dir/iterations" -name "output.md" -type f | \
      sort | head -$((iteration - 1)) | jq -R . | jq -s .)
  fi

  jq -n \
    --argjson from_stage "$from_stage" \
    --argjson from_iterations "$from_iterations" \
    '{from_stage: $from_stage, from_previous_iterations: $from_iterations}'
}
```

#### 4.2 Update Pipeline Schema

**Current format (v2):**
```yaml
stages:
  - name: ideas
    loop: idea-generator
    runs: 5
  - name: synthesize
    loop: synthesizer
    runs: 1
```

**New format (v3):**
```yaml
stages:
  - id: ideas
    template: idea-generator
    max_iterations: 5

  - id: synthesize
    template: synthesizer
    max_iterations: 1
    inputs:
      from: ideas
      select: all         # Get all 5 idea files

  - id: refine
    template: refiner
    max_iterations: 10
    inputs:
      from: synthesize
      select: latest      # Only need the most recent output
```

#### Success Criteria - Phase 4

- [ ] Pipelines support `inputs.from` and `inputs.select`
- [ ] Default is `select: latest`
- [ ] `context.json` correctly populates `inputs.from_stage`
- [ ] Test: Create a 3-stage pipeline where stage 2 uses `select: all` and stage 3 uses `select: latest`

---

### Phase 5: Fail Fast

**Goal:** Remove retry logic, fail immediately with clear error state.

#### 5.1 Remove Retry Logic from Engine

**File:** `scripts/engine.sh` (modify)

Remove any retry counting or failure recovery loops. Replace with immediate failure:

```bash
# When Claude exits with error:
if [ $exit_code -ne 0 ]; then
  local error_msg="Claude process exited with code $exit_code"

  # Write error status
  create_error_status "$status_file" "$error_msg"

  # Update state with failure
  mark_failed "$state_file" "$error_msg"

  echo ""
  echo "Session failed at iteration $i"
  echo "Error: $error_msg"
  echo ""
  echo "To resume: ./scripts/run.sh loop $stage_type $session $max --resume"

  return 1
fi
```

#### 5.2 Update Stage Schema - Guardrails Only

**Remove from schema:**
- `max_failures`
- Any retry-related config

**Keep in schema:**
```yaml
guardrails:
  max_iterations: 50           # Hard stop
  max_runtime_seconds: 7200    # 2 hour timeout
```

#### 5.3 Improve Failure State

**File:** `scripts/lib/state.sh` (update `mark_failed`)

```bash
# Mark session as failed with detailed error
mark_failed() {
  local state_file=$1
  local error=$2
  local error_type=${3:-"unknown"}

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local iteration=$(jq -r '.iteration // 0' "$state_file")
  local iteration_completed=$(jq -r '.iteration_completed // 0' "$state_file")

  jq --arg error "$error" \
     --arg type "$error_type" \
     --arg ts "$timestamp" \
     --argjson resume "$((iteration_completed + 1))" \
     '.status = "failed" |
      .failed_at = $ts |
      .error = {
        type: $type,
        message: $error,
        timestamp: $ts
      } |
      .resume_from = $resume' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}
```

#### Success Criteria - Phase 5

- [ ] No retry logic in engine
- [ ] Failures write clear error state with `resume_from`
- [ ] `--resume` correctly reads `resume_from` and continues
- [ ] Test: Kill Claude mid-iteration, verify clean failure state
- [ ] Test: Resume after failure works correctly

---

### Phase 6: Migration & Cleanup

**Goal:** Remove deprecated code, update all stages, refresh documentation.

#### 6.1 Update All Stage Definitions

| Stage | Current | New |
|-------|---------|-----|
| `work` | `completion: beads-empty` | `termination: {type: queue}` |
| `improve-plan` | `completion: plateau` | `termination: {type: judgment, consensus: 2}` |
| `refine-beads` | `completion: plateau` | `termination: {type: judgment, consensus: 2}` |
| `idea-wizard` | `completion: fixed-n` | `termination: {type: fixed}` |
| `elegance` | `completion: plateau` | `termination: {type: judgment, consensus: 2}` |

#### 6.2 Update All Prompts

For each prompt in `scripts/loops/*/prompt.md`:

1. Replace variable references:
   ```markdown
   # Before
   Session: ${SESSION_NAME}
   Progress file: ${PROGRESS_FILE}

   # After
   Read context from: ${CTX}
   Progress file: ${PROGRESS}
   Write status to: ${STATUS}
   ```

2. Add status output section (see Phase 2.4)

#### 6.3 Remove Deprecated Code

**Files to modify:**
- `scripts/lib/resolve.sh` - Remove old variable resolution
- `scripts/lib/parse.sh` - Deprecate (keep for reference, mark as unused)
- `scripts/engine.sh` - Remove `LOOP_OUTPUT_PARSE` handling

#### 6.4 Update Documentation

**Files to update:**
- `CLAUDE.md` - Update architecture section, variable list, schema examples
- `skills/*/SKILL.md` - Update any references to old variables
- `README.md` - If exists, update examples

#### Success Criteria - Phase 6

- [ ] All 5 stage definitions use new schema
- [ ] All 4 prompts use `${CTX}`, `${PROGRESS}`, `${STATUS}`
- [ ] Old variables work but log deprecation warning
- [ ] CLAUDE.md reflects v3 architecture
- [ ] Full test: Run each stage type successfully with new format

---

## Risk Analysis

### High Risk

| Risk | Mitigation |
|------|------------|
| Breaking existing sessions | Keep deprecated variables working during migration |
| Agents not writing status.json | Engine creates error status if missing |
| Prompt changes break agent behavior | Test each prompt update individually |

### Medium Risk

| Risk | Mitigation |
|------|------------|
| Pipeline input resolution bugs | Comprehensive tests for `select: all` vs `select: latest` |
| Context.json schema changes | Version the schema, validate on read |
| Crash recovery regression | Test resume after each phase |

### Low Risk

| Risk | Mitigation |
|------|------------|
| Documentation drift | Update docs as part of each phase |
| Old code paths remaining | Lint for deprecated patterns |

---

## Testing Strategy

### Test-Driven Development Workflow

For each phase, follow this pattern:

```
1. WRITE FAILING TESTS
   └── Add validation rules for new schema
   └── Create fixtures for expected behavior
   └── Run: ./scripts/run.sh lint --v3 (should fail)

2. IMPLEMENT CHANGES
   └── Make code changes
   └── Update affected files

3. VERIFY TESTS PASS
   └── Run: ./scripts/run.sh lint (all rules pass)
   └── Run: ./scripts/run.sh test loop <name> --iterations 2
   └── Run: ./scripts/run.sh dry-run loop <name> test

4. REGRESSION CHECK
   └── Run: ./scripts/run.sh lint (all loops/pipelines pass)
   └── Test: existing sessions still work
```

### Unit Tests (per phase)

| Phase | Test Command | What It Validates |
|-------|--------------|-------------------|
| 0 | `./scripts/run.sh test loop work --mock` | Mock execution works |
| 1 | `./scripts/run.sh dry-run loop work test \| grep context.json` | Context file generated |
| 2 | `cat fixtures/status.json \| jq '.decision'` | Status schema valid |
| 3 | `ls .claude/pipeline-runs/test/iterations/` | Output snapshots exist |
| 4 | `./scripts/run.sh dry-run pipeline test-inputs` | Input resolution works |
| 5 | `./scripts/run.sh status crashed-session` | Failure state readable |

### Integration Tests (Mock Mode)

```bash
# Test single-stage loop with mock Claude
./scripts/run.sh test loop work --iterations 3

# Test plateau detection with mock responses
./scripts/run.sh test loop improve-plan --iterations 5

# Test pipeline with mock execution
./scripts/run.sh test pipeline full-refine.yaml --mock

# Verify context.json generated correctly
./scripts/run.sh test loop work --iterations 1 && \
  cat .claude/pipeline-runs/test/stage-00-work/iterations/001/context.json | jq .
```

### Integration Tests (Live Mode)

```bash
# Test single-stage loop (requires beads)
./scripts/run.sh work test-v3 3

# Test multi-stage pipeline
./scripts/run.sh pipeline full-refine.yaml test-v3

# Test crash recovery
./scripts/run.sh work test-crash 5
# Kill mid-iteration (Ctrl+C or kill)
./scripts/run.sh work test-crash 5 --resume

# Test input selection
./scripts/run.sh pipeline test-inputs.yaml test-inputs
```

### Smoke Test Checklist

After each phase, verify:

- [ ] `./scripts/run.sh lint` passes (0 errors)
- [ ] `./scripts/run.sh dry-run loop work test` shows expected output
- [ ] Existing sessions (`./scripts/run.sh status <name>`) still readable
- [ ] New files created in expected locations

### Regression Test Checklist (End of Phase 6)

- [ ] `work` stage: beads claimed, implemented, closed
- [ ] `improve-plan` stage: plan improved, plateau reached
- [ ] `elegance` stage: exploration runs, consensus reached
- [ ] `idea-wizard` stage: ideas generated, fixed-n terminates
- [ ] Pipeline: multiple stages chain correctly
- [ ] Resume: crashed session continues cleanly
- [ ] Context: `context.json` readable by agent
- [ ] Status: `status.json` written by agent, parsed by engine

---

## Implementation Order

```
Phase 0: Test Harness (TDD Foundation)
  ├── 0.1 Add v3 validation rules to scripts/lib/validate.sh
  ├── 0.2 Create scripts/lib/mock.sh for mock execution
  ├── 0.3 Add test command to scripts/run.sh
  └── 0.4 Create fixtures/ directories for each loop
  └── CHECKPOINT: ./scripts/run.sh lint && ./scripts/run.sh test loop work --mock

Phase 1: Context Manifest
  ├── 1.1 Create scripts/lib/context.sh
  ├── 1.2 Update scripts/lib/resolve.sh
  └── 1.3 Update scripts/engine.sh (context generation)
  └── CHECKPOINT: ./scripts/run.sh dry-run loop work test | grep context.json

Phase 2: Universal Status
  ├── 2.1 Create scripts/lib/status.sh
  ├── 2.2 Update completion strategies
  ├── 2.3 Update stage schemas (one loop as pilot)
  └── 2.4 Update prompt template (pilot loop only)
  └── CHECKPOINT: ./scripts/run.sh test loop improve-plan --mock --iterations 3

Phase 3: Engine-Side Snapshots
  ├── 3.1 Update engine iteration loop
  └── 3.2 Remove output.mode handling
  └── CHECKPOINT: ls .claude/pipeline-runs/test/*/iterations/*/output.md

Phase 4: Explicit Inputs
  ├── 4.1 Add input resolution to context.sh
  └── 4.2 Update pipeline schema
  └── CHECKPOINT: ./scripts/run.sh dry-run pipeline full-refine.yaml test

Phase 5: Fail Fast
  ├── 5.1 Remove retry logic
  ├── 5.2 Update guardrails schema
  └── 5.3 Improve failure state
  └── CHECKPOINT: ./scripts/run.sh status test-crash (after simulated failure)

Phase 6: Cleanup & Migration
  ├── 6.1 Update all stage definitions to v3 schema
  ├── 6.2 Update all prompts to use ${CTX}, ${STATUS}
  ├── 6.3 Remove deprecated code paths
  └── 6.4 Update CLAUDE.md documentation
  └── CHECKPOINT: ./scripts/run.sh lint && full regression test
```

### Recommended Order Within Each Phase

1. **Write tests first** (validation rules, fixtures)
2. **Verify tests fail** (expected behavior not yet implemented)
3. **Implement smallest change** that makes test pass
4. **Run checkpoint** to verify phase complete
5. **Run full lint** to catch regressions

---

## File Change Summary

### New Files (Phase 0)
- `scripts/lib/mock.sh` - Mock execution for testing
- `scripts/loops/work/fixtures/default.txt` - Mock response fixture
- `scripts/loops/work/fixtures/status.json` - Expected status schema
- `scripts/loops/improve-plan/fixtures/` - Plateau mock fixtures
- `scripts/loops/elegance/fixtures/` - Elegance mock fixtures
- `scripts/loops/idea-wizard/fixtures/` - Idea wizard mock fixtures

### New Files (Phases 1-5)
- `scripts/lib/context.sh` - Context manifest generator
- `scripts/lib/status.sh` - Status file management

### Major Modifications
- `scripts/engine.sh` - Context generation, status reading, snapshot saving
- `scripts/lib/resolve.sh` - Simplified to 4 variables
- `scripts/lib/validate.sh` - Add v3 validation rules (L014-L017)
- `scripts/lib/completions/plateau.sh` - Read from status.json
- `scripts/run.sh` - Add `test` command

### Minor Modifications
- `scripts/lib/state.sh` - Enhanced failure state
- `scripts/lib/completions/beads-empty.sh` - Status integration
- `scripts/lib/completions/fixed-n.sh` - Status integration
- All `scripts/loops/*/loop.yaml` - New schema
- All `scripts/loops/*/prompt.md` - New variables, status output
- All `scripts/pipelines/*.yaml` - Input selection

### Deprecated (keep for reference)
- `scripts/lib/parse.sh` - No longer needed with status.json

---

## Success Criteria (Overall)

1. **One context interface** - Agents read `context.json` via `${CTX}`
2. **One status format** - Every agent writes identical `status.json`
3. **Automatic history** - Engine saves iteration outputs without config
4. **Preserved learning** - Progress file unchanged
5. **Explicit inputs** - Stages declare `inputs.from` and `inputs.select`
6. **Fail fast** - Failures stop immediately with clear state
7. **Schema = documentation** - No implicit behaviors

When all phases complete: agents can create new pipelines by copying existing stage definitions and modifying only the prompt.
