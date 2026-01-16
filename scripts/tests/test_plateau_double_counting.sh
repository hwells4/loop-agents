#!/bin/bash
# Tests for plateau double-counting bug
#
# Bug: The current iteration's decision is counted TWICE:
#   1. Once from reading status_file directly (consecutive=1)
#   2. Again from history (which already includes current iteration)
#
# This causes premature termination when:
#   - consensus=2 required
#   - Only 1 actual "stop" decision exists
#   - But it's counted twice, reaching false consensus
#
# These tests simulate the ACTUAL engine flow where update_iteration
# is called BEFORE check_completion, so history already contains
# the current iteration's decision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/status.sh"

#-------------------------------------------------------------------------------
# Test: Single stop at iteration 1 should NOT terminate (min_iterations=2)
#-------------------------------------------------------------------------------
# This is the EXACT bug scenario reported:
# - iteration 1 says "stop"
# - min_iterations=2, consensus=2
# - Should continue because iteration < min_iterations
# - Bug: double-counting causes early termination
test_single_stop_iteration_1_respects_min_iterations() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # REALISTIC STATE: After engine calls update_iteration for iteration 1
  # The history ALREADY contains iteration 1's "stop" decision
  # (This is what the engine does BEFORE calling check_completion)
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "loop",
  "status": "running",
  "iteration": 1,
  "iteration_completed": 1,
  "history": [
    {"iteration": 1, "stage": "", "decision": "stop", "reason": "Agent says done"}
  ]
}
EOF

  # Status file also has iteration 1's decision (same as in history)
  echo '{"decision": "stop", "reason": "Agent says done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # With the bug: consecutive starts at 1 (status_file) + 1 (history) = 2 >= consensus
  # Correct: iteration 1 < min_iterations 2, should return 1 (continue)
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "1" "$result" "Single stop at iteration 1 should NOT trigger completion (min_iterations=2)"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Single stop should NOT be counted twice
#-------------------------------------------------------------------------------
# Even when min_iterations is satisfied, a single stop shouldn't reach consensus=2
test_single_stop_not_double_counted() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # State at iteration 2 (past min_iterations)
  # History has: iteration 1 = continue, iteration 2 = stop
  # Current status_file has iteration 2's stop
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "loop",
  "status": "running",
  "iteration": 2,
  "iteration_completed": 2,
  "history": [
    {"iteration": 1, "stage": "", "decision": "continue"},
    {"iteration": 2, "stage": "", "decision": "stop"}
  ]
}
EOF

  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # With the bug: consecutive = 1 (status) + 1 (history[1]) = 2 >= consensus
  # Correct: Only 1 actual stop (iteration 2), need 2 consecutive, should continue
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "1" "$result" "Single stop should NOT be double-counted to reach consensus=2"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Two consecutive stops SHOULD trigger completion
#-------------------------------------------------------------------------------
# Verify the fix doesn't break the happy path
test_two_consecutive_stops_triggers_completion() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # State at iteration 3
  # History has: iter 1 = continue, iter 2 = stop, iter 3 = stop
  # TWO consecutive stops (iterations 2 and 3)
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

  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Two actual consecutive stops should trigger completion
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "0" "$result" "Two consecutive stops should trigger completion"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Multi-stage - single stop in current stage not double-counted
#-------------------------------------------------------------------------------
test_multi_stage_single_stop_not_double_counted() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Multi-stage pipeline: stage-a complete, stage-b at iteration 1
  # Stage-a had 2 stops (should be ignored for stage-b consensus)
  # Stage-b has only 1 stop (current iteration)
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "pipeline",
  "status": "running",
  "current_stage": 1,
  "iteration": 1,
  "iteration_completed": 1,
  "stages": [
    {"index": 0, "name": "stage-a", "status": "complete"},
    {"index": 1, "name": "stage-b", "status": "running"}
  ],
  "history": [
    {"iteration": 1, "stage": "stage-a", "decision": "stop"},
    {"iteration": 2, "stage": "stage-a", "decision": "stop"},
    {"iteration": 1, "stage": "stage-b", "decision": "stop"}
  ]
}
EOF

  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # Bug: counts stage-b's stop twice (status + history) = 2 >= consensus
  # Correct: iteration 1 < min_iterations 2 for stage-b, should continue
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "1" "$result" "Multi-stage: single stop in current stage should not be double-counted"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Verify consecutive count accuracy
#-------------------------------------------------------------------------------
# This test explicitly verifies the count is correct
test_consecutive_count_accuracy() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Setup: 3 iterations, pattern is [continue, stop, stop]
  # Current is iteration 3 with "stop"
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

  echo '{"decision": "stop"}' > "$status_file"

  # Test with consensus=3 - should NOT complete (only 2 actual stops)
  export MIN_ITERATIONS=1
  export CONSENSUS=3
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  # With buggy code: 1 (status) + 2 (history stops) = 3 >= consensus -> completes (wrong!)
  # Correct: only 2 actual consecutive stops, need 3, should continue
  assert_eq "1" "$result" "With consensus=3 and only 2 actual stops, should NOT complete"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Consensus=1 should work correctly
#-------------------------------------------------------------------------------
test_consensus_one_works() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Single stop at iteration 2 (past min_iterations)
  cat > "$state_file" << 'EOF'
{
  "session": "test-session",
  "type": "loop",
  "status": "running",
  "iteration": 2,
  "iteration_completed": 2,
  "history": [
    {"iteration": 1, "stage": "", "decision": "continue"},
    {"iteration": 2, "stage": "", "decision": "stop"}
  ]
}
EOF

  echo '{"decision": "stop"}' > "$status_file"

  export MIN_ITERATIONS=1
  export CONSENSUS=1
  export PLATEAU_TEST_MODE=1  # Bypass judge for unit tests

  # With consensus=1, a single stop should complete
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  unset PLATEAU_TEST_MODE
  assert_eq "0" "$result" "With consensus=1, single stop should trigger completion"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Run All Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Plateau Double-Counting Bug Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "These tests verify the fix for the double-counting bug where"
echo "a single 'stop' decision was counted twice (once from status.json"
echo "and once from history), causing premature termination."
echo ""

run_test "Single stop at iteration 1 respects min_iterations" test_single_stop_iteration_1_respects_min_iterations
run_test "Single stop not double-counted" test_single_stop_not_double_counted
run_test "Two consecutive stops triggers completion" test_two_consecutive_stops_triggers_completion
run_test "Multi-stage: single stop not double-counted" test_multi_stage_single_stop_not_double_counted
run_test "Consecutive count accuracy" test_consecutive_count_accuracy
run_test "Consensus=1 works correctly" test_consensus_one_works

test_summary
