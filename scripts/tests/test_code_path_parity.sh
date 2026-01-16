#!/bin/bash
# Contract Tests for Code Path Parity
#
# These tests verify that BOTH run_stage() and run_pipeline() call the same
# required state tracking functions. This catches bugs where a function exists
# and works correctly, but one code path forgets to call it.
#
# Background: Bug 4 (2026-01-12) - run_pipeline() never called mark_iteration_started
# or mark_iteration_completed, but all unit tests passed because the functions
# themselves worked fine.
#
# These tests would have caught that bug.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/mock.sh"
source "$SCRIPT_DIR/lib/spy.sh"

#-------------------------------------------------------------------------------
# Test Helpers
#-------------------------------------------------------------------------------

# Create a minimal stage for testing
_create_test_stage() {
  local test_dir=$1
  local stage_name=${2:-"test-stage"}

  local stage_dir="$test_dir/stages/$stage_name"
  mkdir -p "$stage_dir/fixtures"

  # Minimal stage.yaml - fixed termination, 0 delay
  cat > "$stage_dir/stage.yaml" << 'EOF'
name: test-stage
description: Minimal stage for contract testing
termination:
  type: fixed
delay: 0
EOF

  # Minimal prompt
  cat > "$stage_dir/prompt.md" << 'EOF'
Test iteration ${ITERATION}. Write status to ${STATUS}.
EOF

  # Mock response
  cat > "$stage_dir/fixtures/default.txt" << 'EOF'
Mock response - contract test iteration complete.
EOF

  # Mock status (continue)
  cat > "$stage_dir/fixtures/status.json" << 'EOF'
{"decision": "continue", "reason": "test", "summary": "test iteration"}
EOF

  echo "$stage_dir"
}

# Create a minimal pipeline for testing
_create_test_pipeline() {
  local test_dir=$1
  local pipeline_name=${2:-"test-pipeline"}
  local runs=${3:-2}

  local pipeline_file="$test_dir/${pipeline_name}.yaml"

  cat > "$pipeline_file" << EOF
name: $pipeline_name
stages:
  - name: stage1
    stage: test-stage
    runs: $runs
EOF

  echo "$pipeline_file"
}

# Set up complete mock test environment
_setup_mock_environment() {
  local test_dir=$1
  local session=$2

  # Create directory structure
  mkdir -p "$test_dir/.claude/pipeline-runs/$session"
  mkdir -p "$test_dir/.claude/locks"

  # Create test stage
  _create_test_stage "$test_dir" "test-stage"

  # Enable mock mode with the stage's fixtures
  enable_mock_mode "$test_dir/stages/test-stage/fixtures"

  # Export for engine (STAGES_DIR override required for test stages)
  export MOCK_MODE=true
  export PROJECT_ROOT="$test_dir"
  export STAGES_DIR="$test_dir/stages"
}

_sync_state_with_events() {
  local run_dir=$1
  local session=$2
  local session_type=$3
  local state_file="$run_dir/state.json"
  local events_file="$run_dir/events.jsonl"

  if [ -f "$events_file" ]; then
    reconcile_with_events "$state_file" "$events_file" "$session" "$session_type"
  fi
}

#-------------------------------------------------------------------------------
# Contract Tests: State Tracking via State File Verification
#
# These tests run the actual engine and verify state.json shows correct
# iteration tracking. If mark_iteration_started/completed weren't called,
# the state file would have wrong values.
#-------------------------------------------------------------------------------

test_run_stage_tracks_iteration_in_state() {
  local test_dir=$(create_test_dir "parity-stage")
  local session="test-stage-tracking"

  _setup_mock_environment "$test_dir" "$session"

  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local state_file="$run_dir/state.json"

  # Run engine.sh in single-stage mode with 2 iterations
  # Using subshell to isolate environment
  (
    cd "$test_dir"
    export MOCK_MODE=true
    export MOCK_ITERATION=1

    # Run engine (mock mode should complete quickly)
    "$SCRIPT_DIR/engine.sh" pipeline --single-stage test-stage "$session" 2 2>/dev/null || true
  )

  _sync_state_with_events "$run_dir" "$session" "loop"

  # Verify state file exists and has iteration tracking
  assert_file_exists "$state_file" "State file should exist after run_stage"

  # Check iteration was tracked
  local iteration=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
  local iteration_completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)

  # With iterations, we expect iteration and iteration_completed > 0
  assert_gt "$iteration" 0 "run_stage updates iteration in state"
  assert_gt "$iteration_completed" 0 "run_stage updates iteration_completed in state"

  # Cleanup
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

test_run_pipeline_tracks_iteration_in_state() {
  local test_dir=$(create_test_dir "parity-pipeline")
  local session="test-pipeline-tracking"

  _setup_mock_environment "$test_dir" "$session"

  # Create pipeline
  local pipeline_file=$(_create_test_pipeline "$test_dir" "test-pipeline" 2)

  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local state_file="$run_dir/state.json"

  # Run engine.sh in pipeline mode
  (
    cd "$test_dir"
    export MOCK_MODE=true
    export MOCK_ITERATION=1

    $SCRIPT_DIR/engine.sh pipeline "$pipeline_file" "$session" 2>/dev/null
  )

  _sync_state_with_events "$run_dir" "$session" "pipeline"

  # Verify state file exists and has iteration tracking
  assert_file_exists "$state_file" "State file should exist after run_pipeline"

  # Check iteration was tracked
  local iteration=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
  local iteration_completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)

  # run_pipeline should also update iteration tracking
  assert_gt "$iteration" 0 "run_pipeline updates iteration in state"
  assert_gt "$iteration_completed" 0 "run_pipeline updates iteration_completed in state"

  # Cleanup
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

test_both_paths_produce_equivalent_state_tracking() {
  # Run both paths with same iteration count and verify they produce
  # equivalent state tracking results

  local test_dir_stage=$(create_test_dir "parity-compare-stage")
  local test_dir_pipeline=$(create_test_dir "parity-compare-pipeline")
  local iterations=2

  # Run single-stage path
  _setup_mock_environment "$test_dir_stage" "stage-session"
  (
    cd "$test_dir_stage"
    export MOCK_MODE=true
    $SCRIPT_DIR/engine.sh pipeline --single-stage test-stage "stage-session" $iterations 2>/dev/null
  )
  local stage_state="$test_dir_stage/.claude/pipeline-runs/stage-session/state.json"
  local stage_run_dir="$test_dir_stage/.claude/pipeline-runs/stage-session"
  _sync_state_with_events "$stage_run_dir" "stage-session" "loop"

  # Run pipeline path
  _setup_mock_environment "$test_dir_pipeline" "pipeline-session"
  _create_test_pipeline "$test_dir_pipeline" "test-pipeline" $iterations >/dev/null
  (
    cd "$test_dir_pipeline"
    export MOCK_MODE=true
    $SCRIPT_DIR/engine.sh pipeline "$test_dir_pipeline/test-pipeline.yaml" "pipeline-session" 2>/dev/null
  )
  local pipeline_state="$test_dir_pipeline/.claude/pipeline-runs/pipeline-session/state.json"
  local pipeline_run_dir="$test_dir_pipeline/.claude/pipeline-runs/pipeline-session"
  _sync_state_with_events "$pipeline_run_dir" "pipeline-session" "pipeline"

  # Both should have updated iteration tracking
  local stage_iter=$(jq -r '.iteration_completed // 0' "$stage_state" 2>/dev/null)
  local pipeline_iter=$(jq -r '.iteration_completed // 0' "$pipeline_state" 2>/dev/null)

  # Both paths should track iterations (the key contract)
  assert_gt "$stage_iter" 0 "run_stage path tracks iterations"
  assert_gt "$pipeline_iter" 0 "run_pipeline path tracks iterations"

  # Both should track the same number of iterations
  assert_eq "$stage_iter" "$pipeline_iter" "Both paths should track same iteration count"

  # Cleanup
  disable_mock_mode
  cleanup_test_dir "$test_dir_stage"
  cleanup_test_dir "$test_dir_pipeline"
}

#-------------------------------------------------------------------------------
# Contract Tests: Function Call Verification via Spy Framework
#
# These tests use the spy framework to directly verify the functions are called.
# They source the libraries and test the state tracking functions in isolation.
#-------------------------------------------------------------------------------

test_mark_iteration_functions_are_called_correctly() {
  # This test verifies the spy framework works and can detect function calls
  local test_dir=$(create_test_dir "spy-verify")
  local state_file="$test_dir/state.json"

  # Create initial state
  echo '{"session":"test","iteration":0,"iteration_completed":0}' > "$state_file"

  # Initialize spies
  init_spies
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  # Simulate what the engine does for one iteration
  mark_iteration_started "$state_file" 1
  mark_iteration_completed "$state_file" 1

  # Verify spies recorded the calls
  assert_spy_called "mark_iteration_started" "mark_iteration_started should be called"
  assert_spy_called "mark_iteration_completed" "mark_iteration_completed should be called"
  assert_spy_call_count "mark_iteration_started" 1 "Should be called exactly once"
  assert_spy_call_count "mark_iteration_completed" 1 "Should be called exactly once"

  # Cleanup
  reset_spies
  cleanup_test_dir "$test_dir"
}

test_spy_detects_missing_calls() {
  # Verify spies correctly detect when functions are NOT called
  local test_dir=$(create_test_dir "spy-missing")

  init_spies
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  # Don't call the functions - simulate the bug

  # Verify spies detect the missing calls
  local started_count=$(get_spy_call_count "mark_iteration_started")
  local completed_count=$(get_spy_call_count "mark_iteration_completed")

  assert_eq "0" "$started_count" "Spy should detect mark_iteration_started was not called"
  assert_eq "0" "$completed_count" "Spy should detect mark_iteration_completed was not called"

  # Cleanup
  reset_spies
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Regression Guard: These tests should fail if the bug is reintroduced
#-------------------------------------------------------------------------------

test_regression_guard_iteration_tracking() {
  # This test documents the exact contract that was broken in Bug 4
  # If this test fails, someone has removed iteration tracking from a code path

  local test_dir=$(create_test_dir "regression-guard")
  local session="regression-test"

  _setup_mock_environment "$test_dir" "$session"
  _create_test_pipeline "$test_dir" "test-pipeline" 1 >/dev/null

  local state_file="$test_dir/.claude/pipeline-runs/$session/state.json"

  # Run pipeline (the code path that had the bug)
  (
    cd "$test_dir"
    export MOCK_MODE=true
    $SCRIPT_DIR/engine.sh pipeline "$test_dir/test-pipeline.yaml" "$session" 2>/dev/null
  )

  _sync_state_with_events "$test_dir/.claude/pipeline-runs/$session" "$session" "pipeline"

  # THE CONTRACT: After running, state.json MUST have:
  # - iteration > 0 (mark_iteration_started was called)
  # - iteration_completed > 0 (mark_iteration_completed was called)
  # - iteration_started should be null (iteration finished cleanly)

  local iteration=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
  local iteration_completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
  local iteration_started=$(jq -r '.iteration_started // "null"' "$state_file" 2>/dev/null)

  assert_gt "$iteration" 0 "REGRESSION GUARD: run_pipeline calls mark_iteration_started"
  assert_gt "$iteration_completed" 0 "REGRESSION GUARD: run_pipeline calls mark_iteration_completed"

  # iteration_started should be null after clean completion
  assert_eq "null" "$iteration_started" \
    "REGRESSION GUARD: iteration_started should be null after completion (was: $iteration_started)"

  # Cleanup
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Code Path Parity Tests"
echo "  Verifies both run_stage and run_pipeline call state tracking"
echo "═══════════════════════════════════════════════════════════════"
echo ""

echo "--- Spy Framework Verification ---"
run_test "spy detects function calls" test_mark_iteration_functions_are_called_correctly
run_test "spy detects missing calls" test_spy_detects_missing_calls

echo ""
echo "--- State Tracking Contract Tests ---"
run_test "run_stage tracks iteration in state" test_run_stage_tracks_iteration_in_state
run_test "run_pipeline tracks iteration in state" test_run_pipeline_tracks_iteration_in_state
run_test "both paths produce equivalent state tracking" test_both_paths_produce_equivalent_state_tracking

echo ""
echo "--- Regression Guards ---"
run_test "regression guard: iteration tracking" test_regression_guard_iteration_tracking

echo ""
test_summary
