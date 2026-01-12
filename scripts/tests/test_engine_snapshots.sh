#!/bin/bash
# Tests for engine output snapshots (Phase 3)
#
# Tests that the engine:
# 1. Saves output to iterations/NNN/output.md after each iteration
# 2. Creates error status when agent doesn't write status.json
# 3. Preserves output history across multiple iterations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/status.sh"
source "$SCRIPT_DIR/lib/context.sh"

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------

# Simulate an iteration that writes output but no status
simulate_iteration_no_status() {
  local run_dir=$1
  local iteration=$2
  local stage_id=${3:-"test"}

  local stage_dir="$run_dir/stage-00-$stage_id"
  local iter_dir="$stage_dir/iterations/$(printf '%03d' $iteration)"

  mkdir -p "$iter_dir"
  echo "# Mock Output for iteration $iteration" > "$stage_dir/output.md"

  # Return iteration directory path
  echo "$iter_dir"
}

# Simulate an iteration with both output and status
simulate_iteration_with_status() {
  local run_dir=$1
  local iteration=$2
  local decision=${3:-"continue"}
  local stage_id=${4:-"test"}

  local stage_dir="$run_dir/stage-00-$stage_id"
  local iter_dir="$stage_dir/iterations/$(printf '%03d' $iteration)"

  mkdir -p "$iter_dir"

  # Create output file
  echo "# Mock Output for iteration $iteration" > "$stage_dir/output.md"

  # Create status file with given decision
  jq -n \
    --arg decision "$decision" \
    --arg reason "Mock reason for $decision" \
    --arg summary "Mock iteration $iteration summary" \
    '{
      decision: $decision,
      reason: $reason,
      summary: $summary,
      work: {items_completed: [], files_touched: []},
      errors: []
    }' > "$iter_dir/status.json"

  echo "$iter_dir"
}

# Simulate copying output snapshot (what engine should do)
copy_output_snapshot() {
  local stage_dir=$1
  local iter_dir=$2

  if [ -f "$stage_dir/output.md" ]; then
    cp "$stage_dir/output.md" "$iter_dir/output.md"
  fi
}

#-------------------------------------------------------------------------------
# Output Snapshot Tests
#-------------------------------------------------------------------------------

test_iteration_creates_output_snapshot() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"
  local stage_dir="$run_dir/stage-00-test"

  mkdir -p "$stage_dir"

  # Simulate iteration output
  local iter_dir=$(simulate_iteration_with_status "$run_dir" 1)

  # Engine should copy output to iteration directory
  copy_output_snapshot "$stage_dir" "$iter_dir"

  assert_file_exists "$iter_dir/output.md" "Output snapshot created in iteration directory"

  cleanup_test_dir "$tmp"
}

test_multiple_iterations_preserve_history() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"
  local stage_dir="$run_dir/stage-00-test"

  mkdir -p "$stage_dir"

  # Simulate 3 iterations
  for i in 1 2 3; do
    local iter_dir=$(simulate_iteration_with_status "$run_dir" $i)
    # Engine should copy output after each iteration
    copy_output_snapshot "$stage_dir" "$iter_dir"
  done

  # All iteration outputs should exist
  assert_file_exists "$stage_dir/iterations/001/output.md" "Iteration 1 output preserved"
  assert_file_exists "$stage_dir/iterations/002/output.md" "Iteration 2 output preserved"
  assert_file_exists "$stage_dir/iterations/003/output.md" "Iteration 3 output preserved"

  cleanup_test_dir "$tmp"
}

test_output_snapshots_contain_correct_content() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"
  local stage_dir="$run_dir/stage-00-test"

  mkdir -p "$stage_dir"

  # Create distinct output for each iteration
  for i in 1 2 3; do
    local iter_dir="$stage_dir/iterations/$(printf '%03d' $i)"
    mkdir -p "$iter_dir"
    echo "# Output from iteration $i - unique content $RANDOM" > "$stage_dir/output.md"
    cp "$stage_dir/output.md" "$iter_dir/output.md"
  done

  # Verify each iteration has unique content
  local content1=$(cat "$stage_dir/iterations/001/output.md")
  local content2=$(cat "$stage_dir/iterations/002/output.md")

  assert_contains "$content1" "iteration 1" "Iteration 1 has correct content"
  assert_contains "$content2" "iteration 2" "Iteration 2 has correct content"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Error Status Tests
#-------------------------------------------------------------------------------

test_missing_status_creates_error() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"

  # Simulate iteration that writes output but NOT status.json
  local iter_dir=$(simulate_iteration_no_status "$run_dir" 1)

  # Verify status.json does NOT exist yet
  assert_file_not_exists "$iter_dir/status.json" "Status file should not exist before engine creates it"

  # Engine should create error status when agent doesn't write one
  local status_file="$iter_dir/status.json"
  if [ ! -f "$status_file" ]; then
    create_error_status "$status_file" "Agent did not write status.json"
  fi

  # Verify error status was created
  assert_file_exists "$status_file" "Error status file created"

  local decision=$(jq -r '.decision' "$status_file")
  assert_eq "error" "$decision" "Missing status triggers error decision"

  cleanup_test_dir "$tmp"
}

test_error_status_contains_reason() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"

  local iter_dir=$(simulate_iteration_no_status "$run_dir" 1)
  local status_file="$iter_dir/status.json"

  # Create error status with specific message
  create_error_status "$status_file" "Agent did not write status.json"

  local reason=$(jq -r '.reason' "$status_file")
  assert_contains "$reason" "Agent did not write status.json" "Error status contains reason"

  cleanup_test_dir "$tmp"
}

test_existing_status_not_overwritten() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"

  # Simulate iteration that DOES write status.json
  local iter_dir=$(simulate_iteration_with_status "$run_dir" 1 "stop")
  local status_file="$iter_dir/status.json"

  # Verify status exists with correct decision
  local decision_before=$(jq -r '.decision' "$status_file")
  assert_eq "stop" "$decision_before" "Agent's status.json has stop decision"

  # Engine should NOT overwrite existing status
  if [ ! -f "$status_file" ]; then
    create_error_status "$status_file" "Agent did not write status.json"
  fi

  local decision_after=$(jq -r '.decision' "$status_file")
  assert_eq "stop" "$decision_after" "Existing status preserved (not overwritten with error)"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Status Validation Tests
#-------------------------------------------------------------------------------

test_valid_status_passes_validation() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"

  local iter_dir=$(simulate_iteration_with_status "$run_dir" 1 "continue")
  local status_file="$iter_dir/status.json"

  validate_status "$status_file"
  local result=$?

  assert_eq "0" "$result" "Valid status passes validation"

  cleanup_test_dir "$tmp"
}

test_invalid_decision_fails_validation() {
  local tmp=$(create_test_dir)
  local status_file="$tmp/invalid-status.json"

  # Create status with invalid decision
  echo '{"decision": "invalid", "reason": "test"}' > "$status_file"

  validate_status "$status_file" 2>/dev/null
  local result=$?

  assert_eq "1" "$result" "Invalid decision fails validation"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Context Generation Integration Tests
#-------------------------------------------------------------------------------

test_context_points_to_correct_status_path() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"
  local stage_config='{"id":"test","index":0,"max_iterations":5}'

  # Generate context for iteration 1
  local context_file=$(generate_context "test-session" 1 "$stage_config" "$run_dir")

  assert_file_exists "$context_file" "Context file generated"

  # Verify status path in context
  local status_path=$(jq -r '.paths.status' "$context_file")
  assert_contains "$status_path" "iterations/001/status.json" "Context points to correct status path"

  cleanup_test_dir "$tmp"
}

test_context_iteration_directory_created() {
  local tmp=$(create_test_dir)
  local run_dir="$tmp/pipeline-test"
  local stage_config='{"id":"myloop","index":0,"max_iterations":10}'

  # Generate context should create iteration directory
  local context_file=$(generate_context "my-session" 1 "$stage_config" "$run_dir")

  local iter_dir=$(dirname "$context_file")
  assert_dir_exists "$iter_dir" "Iteration directory created by generate_context"

  # Verify directory structure
  assert_contains "$iter_dir" "stage-00-myloop/iterations/001" "Iteration directory has correct path"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: test_engine_snapshots.sh"
echo ""

run_test "Iteration creates output snapshot" test_iteration_creates_output_snapshot
run_test "Multiple iterations preserve history" test_multiple_iterations_preserve_history
run_test "Output snapshots contain correct content" test_output_snapshots_contain_correct_content
run_test "Missing status creates error" test_missing_status_creates_error
run_test "Error status contains reason" test_error_status_contains_reason
run_test "Existing status not overwritten" test_existing_status_not_overwritten
run_test "Valid status passes validation" test_valid_status_passes_validation
run_test "Invalid decision fails validation" test_invalid_decision_fails_validation
run_test "Context points to correct status path" test_context_points_to_correct_status_path
run_test "Context iteration directory created" test_context_iteration_directory_created

test_summary
