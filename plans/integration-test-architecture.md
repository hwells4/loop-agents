# Integration Test Architecture for Agent Pipelines

## Executive Summary

Design a comprehensive integration test suite that:
- Runs `engine.sh` end-to-end with mocked Claude execution
- Verifies state transitions at each step (not just final state)
- Would have caught all 5 production bugs before deployment
- Is extensible for parallel blocks, hooks, and task generalization

**Key insight**: The 5 bugs all stem from weak state-to-execution coupling. Tests must verify that state.json accurately reflects what actually happened, not just that functions exist.

---

## Test Architecture Overview

```
scripts/tests/
├── integration/
│   ├── harness.sh                    # Shared mock infrastructure
│   ├── test_single_stage.sh          # Single-stage e2e tests
│   ├── test_multi_stage.sh           # Multi-stage pipeline tests
│   ├── test_resume.sh                # Crash recovery tests
│   ├── test_completion_strategies.sh # Termination behavior tests
│   └── test_bug_regression.sh        # 5 specific regression tests
├── fixtures/
│   └── integration/
│       ├── continue-3/               # 3 iterations, all continue
│       ├── plateau-consensus/        # Stop after 2 consecutive stops
│       ├── multi-stage-3/            # 3-stage pipeline fixtures
│       ├── crash-at-2/               # Simulated failure at iteration 2
│       └── mixed-decisions/          # continue→stop→continue→stop
└── future/                           # Extension points for upcoming features
    ├── test_parallel_blocks.sh       # Parallel execution tests
    ├── test_hooks.sh                 # Hook system tests
    └── test_task_sources.sh          # Generalized task sources
```

---

## Test File Organization

### Core Integration Tests (5 files)

| File | Purpose | Bug Coverage |
|------|---------|--------------|
| `harness.sh` | Mock infrastructure, fixtures, state helpers | Foundation |
| `test_single_stage.sh` | End-to-end single-stage execution | Bugs 1, 2, 4 |
| `test_multi_stage.sh` | Multi-stage pipeline orchestration | Bug 3 |
| `test_resume.sh` | Crash recovery and continuation | Bug 5 |
| `test_completion_strategies.sh` | Termination behavior (fixed, plateau, queue) | Bug 2 |
| `test_bug_regression.sh` | Specific tests for each bug | All 5 |

### Test Count Target

| Category | Tests | Time |
|----------|-------|------|
| Single-stage | 12 | ~5s |
| Multi-stage | 10 | ~8s |
| Resume | 8 | ~5s |
| Completion | 6 | ~3s |
| Regression | 5 | ~2s |
| **Total** | **41** | **~23s** |

---

## Fixture Strategy

### Directory Structure Per Fixture Set

```
fixtures/integration/{scenario}/
├── stage.yaml          # Stage configuration for test
├── prompt.md           # Minimal prompt template
├── iteration-1.txt     # Mock agent output for iteration 1
├── iteration-2.txt     # Mock agent output for iteration 2
├── iteration-3.txt     # Mock agent output for iteration 3
├── status-1.json       # Status decision for iteration 1
├── status-2.json       # Status decision for iteration 2
└── status-3.json       # Status decision for iteration 3
```

### Fixture Naming Convention

```
{behavior}-{variation}/
  continue-3/        → 3 iterations, all continue, ends at max
  stop-at-2/         → Stops at iteration 2 (agent decision)
  plateau-2-3/       → Plateau achieved at iterations 2,3
  crash-at-2/        → Simulated failure at iteration 2
  multi-3-stages/    → 3-stage pipeline with mixed outcomes
```

### Status JSON Templates

**Continue:**
```json
{
  "decision": "continue",
  "reason": "More work needed",
  "summary": "Completed iteration ${N}",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**Stop (plateau):**
```json
{
  "decision": "stop",
  "reason": "Work complete, no further improvements identified",
  "summary": "Finalized iteration ${N}",
  "work": {"items_completed": ["item1"], "files_touched": ["file.txt"]},
  "errors": []
}
```

### Multi-Stage Fixture Organization

For multi-stage pipelines, fixtures are nested by stage:

```
fixtures/integration/multi-3-stages/
├── pipeline.yaml                # Pipeline definition
├── stage-00-elegance/
│   ├── iteration-1.txt, status-1.json  (continue)
│   ├── iteration-2.txt, status-2.json  (stop)
├── stage-01-ideation/
│   ├── iteration-1.txt, status-1.json  (continue)
│   ├── iteration-2.txt, status-2.json  (continue)
└── stage-02-elegance/
    ├── iteration-1.txt, status-1.json  (continue)
    └── iteration-2.txt, status-2.json  (stop)
```

---

## State Verification Patterns

### Pattern 1: Step-by-Step State Tracking

```bash
# Instead of just checking final state, verify each transition
test_state_updates_each_iteration() {
  local test_dir=$(create_test_dir "state-tracking")
  setup_mock_pipeline "$test_dir" "continue-3"

  # Inject state checkpoint function
  _checkpoint_state() {
    cp "$state_file" "$test_dir/checkpoints/state-after-iter-$1.json"
  }

  # Run with checkpointing enabled
  MOCK_AFTER_ITERATION_CALLBACK="_checkpoint_state" \
    run_mock_pipeline "$test_dir" "test-session" 3

  # Verify state at each checkpoint
  assert_json_field "checkpoints/state-after-iter-1.json" ".iteration_completed" "1"
  assert_json_field "checkpoints/state-after-iter-2.json" ".iteration_completed" "2"
  assert_json_field "checkpoints/state-after-iter-3.json" ".iteration_completed" "3"
}
```

### Pattern 2: History Array Verification

```bash
# Verify history grows correctly (catches Bug 4)
test_history_accumulates_correctly() {
  run_mock_pipeline "$test_dir" "test-session" 3

  local history_len=$(jq '.history | length' "$state_file")
  assert_eq "$history_len" "3" "History should have 3 entries after 3 iterations"

  # Verify each entry has required fields
  for i in 0 1 2; do
    assert_json_field_exists "$state_file" ".history[$i].decision"
    assert_json_field_exists "$state_file" ".history[$i].iteration"
  done
}
```

### Pattern 3: State-Artifact Consistency

```bash
# Verify state matches filesystem artifacts
test_state_matches_artifacts() {
  run_mock_pipeline "$test_dir" "test-session" 3

  # State says 3 iterations completed
  local completed=$(jq -r '.iteration_completed' "$state_file")

  # Filesystem should have 3 iteration directories
  local dirs=$(ls -d "$run_dir/iterations/"* 2>/dev/null | wc -l | tr -d ' ')

  assert_eq "$completed" "$dirs" "State iteration_completed should match iteration directories"
}
```

---

## Per-Bug Regression Tests

### Bug 1: Default Model Inconsistency

```bash
test_bug1_default_model_consistency() {
  # Test 1: Single-stage path defaults to opus
  local model_single=$(run_single_stage_get_model "test-stage" "session1")
  assert_eq "$model_single" "opus" "Single-stage should default to opus"

  # Test 2: Multi-stage path defaults to opus
  local model_multi=$(run_multi_stage_get_model "test-pipeline" "session2")
  assert_eq "$model_multi" "opus" "Multi-stage should default to opus"

  # Test 3: Stage-level model overrides pipeline default
  setup_stage_with_model "test-stage" "haiku"
  local model_override=$(run_single_stage_get_model "test-stage" "session3")
  assert_eq "$model_override" "haiku" "Stage model should override default"
}
```

### Bug 2: Empty Variable Handling

```bash
test_bug2_empty_variable_handling() {
  # Test with completely empty state
  echo '{}' > "$state_file"

  # Should not throw "integer expression expected"
  local output=$(check_completion "test" "$state_file" "$status_file" 2>&1)
  assert_not_contains "$output" "integer expression expected" \
    "Completion check should handle empty state gracefully"

  # Test with missing MAX_ITERATIONS
  unset MAX_ITERATIONS
  output=$(check_completion "test" "$state_file" "$status_file" 2>&1)
  assert_not_contains "$output" "integer expression expected" \
    "Completion check should handle missing MAX_ITERATIONS"
}
```

### Bug 3: Silent Stage Failure Detection

```bash
test_bug3_zero_iterations_detected() {
  setup_pipeline_with_broken_stage "$test_dir"

  # Stage configured but will complete zero iterations
  local result
  result=$(run_mock_pipeline "$test_dir" "test-session" 2>&1) || true

  # Should fail explicitly, not silently succeed
  local status=$(jq -r '.status' "$state_file")
  assert_eq "$status" "failed" "Zero-iteration stage should fail"

  # Error should be recorded
  local error=$(jq -r '.error.message' "$state_file")
  assert_contains "$error" "zero iterations" "Error should mention zero iterations"
}
```

### Bug 4: State Updates During Execution

```bash
test_bug4_state_updates_during_execution() {
  # Use spy to verify mark_iteration_* functions are called
  init_spies
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  run_mock_pipeline "$test_dir" "test-session" 3

  # Both functions should be called 3 times each
  assert_spy_call_count "mark_iteration_started" 3 \
    "mark_iteration_started should be called for each iteration"
  assert_spy_call_count "mark_iteration_completed" 3 \
    "mark_iteration_completed should be called for each iteration"

  # Verify state file actually updated
  local completed=$(jq -r '.iteration_completed' "$state_file")
  assert_eq "$completed" "3" "iteration_completed should be 3"

  reset_spies
}
```

### Bug 5: Multi-Stage Resume Respects current_stage

```bash
test_bug5_resume_respects_current_stage() {
  # Setup: 3-stage pipeline, stages 0-1 complete, stage 2 at iteration 2
  create_partial_pipeline_state "$test_dir" "test-session" \
    --stage 0 complete \
    --stage 1 complete \
    --stage 2 running --iteration 2

  # Resume the pipeline
  run_mock_pipeline_resume "$test_dir" "test-session"

  # Verify: Should resume from stage 2, iteration 3
  assert_log_contains "Resuming from stage 2" \
    "Should identify stage 2 as resume point"
  assert_log_not_contains "Loop 1/3" \
    "Should not restart from stage 0"

  # Verify stage 0 and 1 were not re-executed
  local stage0_runs=$(count_iterations "$run_dir/stage-00-elegance/iterations")
  assert_eq "$stage0_runs" "0" "Stage 0 should not have new iterations after resume"
}
```

---

## 12 User Flows to Test

| # | Flow | Test File | Key Assertions |
|---|------|-----------|----------------|
| 1 | Single-stage runs to max iterations | test_single_stage.sh | iteration_completed == max |
| 2 | Single-stage stops on agent decision | test_single_stage.sh | decision=="stop", status=="complete" |
| 3 | Single-stage handles agent crash | test_single_stage.sh | status=="failed", error recorded |
| 4 | Multi-stage executes all stages | test_multi_stage.sh | stages[].status all "complete" |
| 5 | Multi-stage tracks current_stage | test_multi_stage.sh | current_stage increments correctly |
| 6 | Multi-stage detects zero iterations | test_multi_stage.sh | Explicit failure, not silent |
| 7 | Resume single-stage from checkpoint | test_resume.sh | Starts at iteration_completed + 1 |
| 8 | Resume multi-stage skips complete stages | test_resume.sh | Skips stages with status=="complete" |
| 9 | Resume multi-stage uses current_stage | test_resume.sh | Starts at current_stage, not 0 |
| 10 | Plateau requires consensus | test_completion.sh | Need N consecutive stops |
| 11 | Fixed-n respects max | test_completion.sh | Stops at exactly N |
| 12 | State persists after crash | test_resume.sh | Can resume without data loss |

---

## Extension Points for Upcoming Features

### 1. Parallel Processing (Blocks)

**New Test File:** `tests/future/test_parallel_blocks.sh`

**Fixture Extension:**
```
fixtures/integration/parallel-3-agents/
├── agent-0/
│   └── iteration-1.txt, status-1.json
├── agent-1/
│   └── iteration-1.txt, status-1.json
└── agent-2/
    └── iteration-1.txt, status-1.json
```

**New Tests:**
```bash
# State isolation between parallel agents
test_parallel_agents_have_isolated_state() {
  # Each agent should write to separate state sub-paths
  # Verify no cross-contamination
}

# Merge strategies
test_parallel_merge_consensus() {
  # 2/3 agents say stop → merged decision is stop
}

test_parallel_merge_first() {
  # First agent to complete wins
}

test_parallel_merge_all() {
  # All must complete before merge
}

# Race condition detection
test_parallel_state_no_race_condition() {
  # Run multiple times, verify deterministic results
}
```

**Harness Extension:**
```bash
# New mock mode for parallel execution
enable_parallel_mock_mode() {
  local agent_count=$1
  export MOCK_PARALLEL_AGENTS="$agent_count"
  # Each agent gets its own fixture namespace
}

get_parallel_mock_response() {
  local agent_id=$1
  local iteration=$2
  cat "$MOCK_FIXTURES_DIR/agent-$agent_id/iteration-$iteration.txt"
}
```

### 2. Hooks System

**New Test File:** `tests/future/test_hooks.sh`

**Fixture Extension:**
```
fixtures/integration/with-hooks/
├── hooks/
│   ├── pre_iteration.sh    # Exit 0 = proceed, exit 1 = abort
│   ├── post_iteration.sh   # Receives iteration results
│   ├── between_stages.sh   # Can pause for approval
│   └── on_error.sh         # Receives error context
├── iteration-1.txt
└── status-1.json
```

**New Tests:**
```bash
# Hook execution order
test_hook_execution_order() {
  init_spies
  spy_function "hook_pre_iteration"
  spy_function "hook_post_iteration"

  run_mock_pipeline_with_hooks "$test_dir" "test-session" 2

  # Verify order: pre1 → post1 → pre2 → post2
  assert_spy_call_sequence "hook_pre_iteration" "hook_post_iteration" \
    "hook_pre_iteration" "hook_post_iteration"
}

# Hook failure handling
test_pre_iteration_hook_abort() {
  setup_hook "pre_iteration" "exit 1"  # Abort on pre-iteration

  run_mock_pipeline_with_hooks "$test_dir" "test-session" 3

  assert_json_field "$state_file" ".status" "failed"
  assert_json_field "$state_file" ".error.type" "hook_abort"
}

# Human-in-the-loop simulation
test_between_stages_hook_pause() {
  setup_hook "between_stages" "read -p 'Continue?' response"
  export MOCK_STDIN="y"  # Simulate user input

  run_mock_pipeline_with_hooks "$test_dir" "test-session" 3

  # Verify pause was logged
  assert_log_contains "Waiting for approval"
}
```

**Harness Extension:**
```bash
setup_hook() {
  local hook_name=$1
  local script=$2
  mkdir -p "$test_dir/hooks"
  echo "#!/bin/bash"$'\n'"$script" > "$test_dir/hooks/${hook_name}.sh"
  chmod +x "$test_dir/hooks/${hook_name}.sh"
}

# Mock stdin for interactive hooks
run_with_mocked_stdin() {
  local input=$1
  shift
  echo "$input" | "$@"
}
```

### 3. Task Generalization (Beyond Beads)

**New Test File:** `tests/future/test_task_sources.sh`

**Fixture Extension:**
```
fixtures/integration/json-task-source/
├── tasks.json
│   {"tasks": [
│     {"id": 1, "title": "Task 1", "done": false},
│     {"id": 2, "title": "Task 2", "done": false}
│   ]}
├── iteration-1.txt  # Completes task 1
├── status-1.json    # items_completed: ["task-1"]
├── iteration-2.txt  # Completes task 2
└── status-2.json    # items_completed: ["task-2"]
```

**New Tests:**
```bash
# JSON file as task source
test_json_task_source() {
  setup_json_tasks "$test_dir" '[{"id":1,"done":false},{"id":2,"done":false}]'

  run_mock_pipeline_with_task_source "$test_dir" "json_file" "test-session"

  # Verify queue depletes correctly
  local tasks=$(jq '[.tasks[] | select(.done == false)] | length' "$task_file")
  assert_eq "$tasks" "0" "All tasks should be marked done"
}

# Markdown todo list as task source
test_markdown_todo_source() {
  setup_markdown_todos "$test_dir" "- [ ] Task 1\n- [ ] Task 2"

  run_mock_pipeline_with_task_source "$test_dir" "todo_list" "test-session"

  # Verify todos checked off
  local unchecked=$(grep -c '\- \[ \]' "$todo_file")
  assert_eq "$unchecked" "0" "All todos should be checked"
}

# Custom task source adapter
test_custom_task_source() {
  setup_custom_task_adapter "$test_dir" "my_adapter.sh"

  run_mock_pipeline_with_task_source "$test_dir" "custom" "test-session"

  # Adapter should have been called
  assert_spy_called "my_adapter.sh"
}
```

**Harness Extension:**
```bash
# Task source abstraction for testing
setup_task_source() {
  local test_dir=$1
  local source_type=$2

  case "$source_type" in
    json_file)
      # Configure for JSON file source
      export TASK_SOURCE_TYPE="json_file"
      export TASK_SOURCE_CONFIG_PATH="$test_dir/tasks.json"
      export TASK_SOURCE_CONFIG_COMPLETED_FIELD=".done"
      ;;
    todo_list)
      export TASK_SOURCE_TYPE="todo_list"
      export TASK_SOURCE_CONFIG_PATH="$test_dir/TODO.md"
      ;;
    beads)
      export TASK_SOURCE_TYPE="beads"
      # Mock bd CLI
      setup_mock_bd "$test_dir"
      ;;
  esac
}

# Mock bd CLI for testing without real beads
setup_mock_bd() {
  local test_dir=$1
  mkdir -p "$test_dir/bin"
  cat > "$test_dir/bin/bd" << 'EOF'
#!/bin/bash
case "$1" in
  ready) cat "$BD_MOCK_TASKS" ;;
  close) echo "Closed: $2" ;;
esac
EOF
  chmod +x "$test_dir/bin/bd"
  export PATH="$test_dir/bin:$PATH"
}
```

---

## TDD Workflow for New Features

### Phase 1: Write Failing Test First

```bash
# Example: Adding parallel block support
test_parallel_blocks_basic() {
  # This test will fail until feature is implemented
  setup_parallel_stage "$test_dir" "test-stage" --agents 3

  run_mock_pipeline "$test_dir" "test-session"

  # Verify all 3 agents ran
  assert_eq "$(count_agent_outputs)" "3" "Should run 3 parallel agents"
}
```

### Phase 2: Run Test (Expect Failure)

```bash
./scripts/tests/run_tests.sh tests/future/test_parallel_blocks.sh

# Output:
# ✗ test_parallel_blocks_basic
#   Expected: 3 parallel agents
#   Actual: 1 (parallel not implemented)
#
# 1 failed, 0 passed
```

### Phase 3: Implement Feature

Implement the feature in `engine.sh` and related files.

### Phase 4: Run Test (Expect Pass)

```bash
./scripts/tests/run_tests.sh tests/future/test_parallel_blocks.sh

# Output:
# ✓ test_parallel_blocks_basic
#
# 0 failed, 1 passed
```

### Phase 5: Add Edge Case Tests

```bash
test_parallel_handles_agent_crash() { ... }
test_parallel_merge_with_conflicts() { ... }
test_parallel_state_isolation() { ... }
```

---

## Answers to Design Questions

### 1. How do we structure fixtures for multi-stage pipelines with different outcomes per stage?

**Answer:** Nested fixture directories per stage with independent iteration files:

```
multi-stage-fixture/
├── pipeline.yaml
├── stage-00-name/
│   ├── iteration-1.txt, status-1.json
│   └── iteration-2.txt, status-2.json (decision: stop)
├── stage-01-name/
│   └── iteration-1.txt, status-1.json (decision: stop)
└── stage-02-name/
    ├── iteration-1.txt, status-1.json
    ├── iteration-2.txt, status-2.json
    └── iteration-3.txt, status-3.json (decision: stop)
```

The harness switches fixture directories when `current_stage` changes.

### 2. How do we test state consistency during parallel execution?

**Answer:** Use file-based locking assertions and state snapshots:

```bash
test_parallel_state_consistency() {
  # Take snapshots before and after each parallel agent completes
  # Verify no overwrites or lost updates
  # Use test-specific state sub-paths: state.json.agent-{id}
  # Final merge step combines sub-states
}
```

### 3. How do we mock hooks that require human input?

**Answer:** Mock stdin and use timeout with defaults:

```bash
# Hook script with mocked input
setup_approval_hook() {
  cat > "$hook_path" << 'EOF'
read -t 1 -p "Approve? " response || response="$MOCK_APPROVAL_DEFAULT"
[ "$response" = "y" ] && exit 0 || exit 1
EOF
}

# In test
export MOCK_APPROVAL_DEFAULT="y"
run_mock_pipeline_with_hooks ...
```

### 4. How do we test queue depletion for different task sources?

**Answer:** Abstract task source behind interface, mock each implementation:

```bash
# Generic queue check
check_queue_empty() {
  case "$TASK_SOURCE_TYPE" in
    beads)     [ -z "$(bd ready)" ] ;;
    json_file) [ "$(jq '.tasks | map(select(.done == false)) | length' "$TASK_FILE")" = "0" ] ;;
    todo_list) ! grep -q '\- \[ \]' "$TODO_FILE" ;;
  esac
}
```

### 5. What's the right granularity - one big integration test or many small ones?

**Answer:** Many small, focused tests with shared setup functions.

**Rationale:**
- Each test should verify ONE behavior
- Failures are easier to diagnose
- Can run specific tests during development
- Parallel test execution possible

**Structure:**
- ~5-10 tests per flow (single-stage, multi-stage, resume, etc.)
- Each test < 2 seconds
- Total suite < 30 seconds

---

## Migration Path from Current Tests

### Phase 1: Keep Existing Tests (No Changes)
- All 353 unit/contract tests continue to run
- Integration tests are additive, not replacement

### Phase 2: Add Integration Harness
- Create `scripts/tests/integration/harness.sh`
- Add fixture directories
- Write first integration test (single-stage basic)

### Phase 3: Bug Regression Tests
- Add `test_bug_regression.sh` with 5 specific tests
- Verify they pass with current code
- Optional: Verify they fail with pre-fix code (TDD proof)

### Phase 4: Flow Coverage
- Add remaining integration tests for 12 user flows
- Integrate into CI pipeline

### Phase 5: Future Extension Stubs
- Create `tests/future/` directory
- Add stub test files with `skip` annotations
- Document expected behavior for upcoming features

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `scripts/tests/integration/harness.sh` | **NEW** - Mock infrastructure |
| `scripts/tests/integration/test_single_stage.sh` | **NEW** - 12 tests |
| `scripts/tests/integration/test_multi_stage.sh` | **NEW** - 10 tests |
| `scripts/tests/integration/test_resume.sh` | **NEW** - 8 tests |
| `scripts/tests/integration/test_completion_strategies.sh` | **NEW** - 6 tests |
| `scripts/tests/integration/test_bug_regression.sh` | **NEW** - 5 tests |
| `scripts/tests/fixtures/integration/` | **NEW** - Fixture directories |
| `scripts/tests/run_tests.sh` | **MODIFY** - Add integration test discovery |

---

## Verification Strategy

### How to Know Tests Would Have Caught Bugs

```bash
# 1. Create branch with bugs reintroduced
git checkout -b verify-tests-catch-bugs
# Manually revert bug fixes in engine.sh, state.sh, fixed-n.sh

# 2. Run integration tests
./scripts/tests/run_tests.sh integration

# 3. Verify specific failures
# Bug 1: test_bug1_default_model_consistency → FAIL
# Bug 2: test_bug2_empty_variable_handling → FAIL
# Bug 3: test_bug3_zero_iterations_detected → FAIL
# Bug 4: test_bug4_state_updates_during_execution → FAIL
# Bug 5: test_bug5_resume_respects_current_stage → FAIL

# 4. Return to main
git checkout main
```

### End-to-End Test Verification

After implementation, run full suite:

```bash
# Run all tests
./scripts/tests/run_tests.sh

# Expected output:
# Unit tests: 353 passed, 0 failed
# Contract tests: 12 passed, 0 failed
# Integration tests: 41 passed, 0 failed
# Total: 406 passed, 0 failed
# Time: 28 seconds
```

---

## Success Criteria

- [ ] All 5 bug regression tests pass with current code
- [ ] All 5 bug regression tests would fail with pre-fix code
- [ ] 12 user flows have integration test coverage
- [ ] Tests run without Claude API calls (MOCK_MODE)
- [ ] Full suite completes in < 30 seconds
- [ ] Tests are isolated (no shared state)
- [ ] Extension points documented for parallel, hooks, task sources
- [ ] TDD workflow documented and demonstrated
