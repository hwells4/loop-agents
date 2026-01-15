#!/bin/bash
# Tests for plateau stage isolation in multi-stage pipelines
#
# These tests verify that:
# 1. History entries include stage field
# 2. Plateau checks filter by current stage
# 3. Previous stage decisions don't contaminate current stage plateau
# 4. Pipeline path correctly records history
#
# Bug context: Before fix, plateau.sh would count ALL history entries
# regardless of stage, causing premature termination in multi-stage pipelines.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/status.sh"

#-------------------------------------------------------------------------------
# Test: History entries include stage field
#-------------------------------------------------------------------------------
test_history_entries_include_stage() {
  local test_dir=$(mktemp -d)

  # Initialize state (returns state file path)
  local state_file=$(init_state "test-session" "loop" "$test_dir")

  # Update iteration with stage name
  local history_json='{"decision": "continue"}'
  update_iteration "$state_file" 1 "$history_json" "improve-plan"

  # Verify history entry has stage field
  local stage_in_history=$(jq -r '.history[0].stage' "$state_file")

  assert_eq "improve-plan" "$stage_in_history" "History entry should include stage field"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: History entries work without stage (backward compatibility)
#-------------------------------------------------------------------------------
test_history_entries_without_stage() {
  local test_dir=$(mktemp -d)

  # Initialize state (returns state file path)
  local state_file=$(init_state "test-session" "loop" "$test_dir")

  # Update iteration WITHOUT stage name (single-stage loop compatibility)
  local history_json='{"decision": "stop"}'
  update_iteration "$state_file" 1 "$history_json" ""

  # Verify history entry exists with empty stage
  local stage_in_history=$(jq -r '.history[0].stage' "$state_file")
  local decision=$(jq -r '.history[0].decision' "$state_file")

  assert_eq "" "$stage_in_history" "Stage should be empty string when not provided"
  assert_eq "stop" "$decision" "Decision should still be recorded"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Plateau ignores previous stage history (CORE BUG FIX)
#-------------------------------------------------------------------------------
test_plateau_ignores_previous_stage_history() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Create state with:
  # - Stage 0 (improve-plan): 2 consecutive stops (would trigger plateau if not filtered)
  # - Stage 1 (refine-tasks): current stage, just started
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "pipeline",
  "status": "running",
  "current_stage": 1,
  "iteration": 1,
  "iteration_completed": 0,
  "stages": [
    {"index": 0, "name": "improve-plan", "status": "complete"},
    {"index": 1, "name": "refine-tasks", "status": "running"}
  ],
  "history": [
    {"iteration": 1, "stage": "improve-plan", "decision": "continue"},
    {"iteration": 2, "stage": "improve-plan", "decision": "stop"},
    {"iteration": 3, "stage": "improve-plan", "decision": "stop"}
  ]
}
EOF

  # Current iteration says stop
  echo '{"decision": "stop", "reason": "Looks good"}' > "$status_file"

  export MIN_ITERATIONS=1
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Should NOT complete: only 1 stop for refine-tasks (current), need 2
  # The 2 stops from improve-plan should be ignored
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "1" "$result" "Plateau should NOT trigger - previous stage stops should be ignored"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Plateau works when same stage has consecutive stops
#-------------------------------------------------------------------------------
test_plateau_triggers_for_same_stage() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # REALISTIC STATE: At iteration 2 for refine-tasks, history includes current iteration
  # This matches engine flow: update_iteration is called BEFORE check_completion
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "pipeline",
  "status": "running",
  "current_stage": 1,
  "iteration": 2,
  "iteration_completed": 2,
  "stages": [
    {"index": 0, "name": "improve-plan", "status": "complete"},
    {"index": 1, "name": "refine-tasks", "status": "running"}
  ],
  "history": [
    {"iteration": 1, "stage": "improve-plan", "decision": "continue"},
    {"iteration": 2, "stage": "improve-plan", "decision": "stop"},
    {"iteration": 1, "stage": "refine-tasks", "decision": "stop"},
    {"iteration": 2, "stage": "refine-tasks", "decision": "stop"}
  ]
}
EOF

  # Status file has current iteration's decision (same as last history entry for this stage)
  echo '{"decision": "stop", "reason": "All beads refined"}' > "$status_file"

  export MIN_ITERATIONS=1
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Should complete: 2 consecutive stops for refine-tasks in history (iterations 1 and 2)
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "0" "$result" "Plateau should trigger when same stage has consecutive stops"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Plateau handles mixed stage history correctly
#-------------------------------------------------------------------------------
test_plateau_handles_interleaved_stages() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # REALISTIC STATE: At iteration 3 for stage-b, history includes current iteration
  # This matches engine flow: update_iteration is called BEFORE check_completion
  # Interleaved history (unlikely but possible edge case)
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "pipeline",
  "status": "running",
  "current_stage": 1,
  "iteration": 3,
  "iteration_completed": 3,
  "stages": [
    {"index": 0, "name": "stage-a", "status": "complete"},
    {"index": 1, "name": "stage-b", "status": "running"}
  ],
  "history": [
    {"iteration": 1, "stage": "stage-a", "decision": "stop"},
    {"iteration": 1, "stage": "stage-b", "decision": "continue"},
    {"iteration": 2, "stage": "stage-a", "decision": "stop"},
    {"iteration": 2, "stage": "stage-b", "decision": "stop"},
    {"iteration": 3, "stage": "stage-b", "decision": "stop"}
  ]
}
EOF

  # Status file has current iteration's decision (same as last history entry for stage-b)
  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=1
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Should complete: stage-b has 2 consecutive stops in history (iterations 2 and 3)
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "0" "$result" "Plateau should work with interleaved stage history"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Single-stage loops still work (no stage in history)
#-------------------------------------------------------------------------------
test_plateau_works_for_single_stage_loops() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # REALISTIC STATE: At iteration 3, history includes ALL iterations (1-3)
  # This matches engine flow: update_iteration is called BEFORE check_completion
  # Single-stage loop: no stages array, empty stage field in history
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "loop",
  "status": "running",
  "iteration": 3,
  "iteration_completed": 3,
  "history": [
    {"iteration": 1, "stage": "", "decision": "continue"},
    {"iteration": 2, "stage": "", "decision": "stop"},
    {"iteration": 3, "stage": "", "decision": "stop"}
  ]
}
EOF

  # Status file has current iteration's decision (same as history[2])
  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Should complete: 2 consecutive stops in history (iterations 2 and 3)
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "0" "$result" "Plateau should work for single-stage loops with empty stage field"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Plateau respects min_iterations per stage
#-------------------------------------------------------------------------------
test_plateau_respects_min_iterations() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Stage 1 just started (iteration 1), even with stop shouldn't trigger
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "pipeline",
  "status": "running",
  "current_stage": 1,
  "iteration": 1,
  "iteration_completed": 0,
  "stages": [
    {"index": 0, "name": "stage-a", "status": "complete"},
    {"index": 1, "name": "stage-b", "status": "running"}
  ],
  "history": [
    {"iteration": 1, "stage": "stage-a", "decision": "stop"},
    {"iteration": 2, "stage": "stage-a", "decision": "stop"}
  ]
}
EOF

  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=1
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Should NOT complete: iteration 1 < min_iterations 2
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "1" "$result" "Plateau should respect min_iterations"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Run All Tests
#-------------------------------------------------------------------------------

run_test "History entries include stage field" test_history_entries_include_stage
run_test "History entries work without stage" test_history_entries_without_stage
run_test "Plateau ignores previous stage history" test_plateau_ignores_previous_stage_history
run_test "Plateau triggers for same stage" test_plateau_triggers_for_same_stage
run_test "Plateau handles interleaved stages" test_plateau_handles_interleaved_stages
run_test "Plateau works for single-stage loops" test_plateau_works_for_single_stage_loops
run_test "Plateau respects min_iterations" test_plateau_respects_min_iterations

test_summary
