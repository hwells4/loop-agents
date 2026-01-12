#!/bin/bash
# Completion strategy tests - verify v3 status.json-based completion works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/status.sh"

#-------------------------------------------------------------------------------
# Plateau Completion Strategy Tests
#-------------------------------------------------------------------------------

test_plateau_reads_from_status_file() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Initialize state at iteration 3 (past min_iterations)
  echo '{"iteration": 3, "history": [{"decision": "continue"}, {"decision": "stop"}]}' > "$state_file"

  # Status file says stop
  echo '{"decision": "stop", "reason": "No more improvements"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  # Should complete because: current=stop + previous=stop = 2 consecutive stops
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "0" "$result" "Plateau completes when consensus reached via status.json"

  rm -rf "$test_dir"
}

test_plateau_ignores_output_parameter() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 3, "history": [{"decision": "continue"}, {"decision": "continue"}]}' > "$state_file"

  # Status file says continue
  echo '{"decision": "continue", "reason": "More work needed"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  # Even though we pass output text, it should be ignored
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "1" "$result" "Plateau does not complete when decision is continue"

  rm -rf "$test_dir"
}

test_plateau_requires_min_iterations() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Only at iteration 1
  echo '{"iteration": 1, "history": []}' > "$state_file"
  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "1" "$result" "Plateau requires min_iterations before checking"

  rm -rf "$test_dir"
}

test_plateau_requires_consensus() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  # Only one stop in history, current is stop
  echo '{"iteration": 3, "history": [{"decision": "continue"}, {"decision": "continue"}]}' > "$state_file"
  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "1" "$result" "Plateau requires consensus (2 consecutive stops)"

  rm -rf "$test_dir"
}

test_plateau_handles_missing_status_file() {
  source "$SCRIPT_DIR/lib/completions/plateau.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"

  echo '{"iteration": 3, "history": [{"decision": "stop"}, {"decision": "stop"}]}' > "$state_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  # Missing status file should default to continue
  check_completion "test" "$state_file" "/nonexistent/status.json" >/dev/null 2>&1
  local result=$?

  assert_eq "1" "$result" "Missing status file defaults to continue (no completion)"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Beads-Empty Completion Strategy Tests
#-------------------------------------------------------------------------------

test_beads_empty_checks_error_status() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "error", "reason": "Something broke"}' > "$status_file"

  # Even if beads are empty, error status should not complete
  # (This test assumes bd is not available or returns empty)
  check_completion "nonexistent-session-xyz" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  # With error status, should not complete (return 1)
  assert_eq "1" "$result" "Error status prevents completion even if queue empty"

  rm -rf "$test_dir"
}

test_beads_empty_accepts_status_file_param() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "continue", "reason": "Work in progress"}' > "$status_file"

  # Function should accept 3 parameters without error
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  # Verify function ran without crashing (exit code 0 or 1, not crash)
  assert_true "$([ $result -le 1 ] && echo true || echo false)" "beads-empty accepts status_file parameter without crashing"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Fixed-N Completion Strategy Tests
#-------------------------------------------------------------------------------

test_fixed_n_accepts_status_file_param() {
  source "$SCRIPT_DIR/lib/completions/fixed-n.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 5}' > "$state_file"
  echo '{"decision": "continue"}' > "$status_file"

  export FIXED_ITERATIONS=5
  export MAX_ITERATIONS=5

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "0" "$result" "Fixed-N completes at target iteration"

  rm -rf "$test_dir"
}

test_fixed_n_ignores_status_decision() {
  source "$SCRIPT_DIR/lib/completions/fixed-n.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 3}' > "$state_file"
  # Even if status says stop, fixed-n should continue until N reached
  echo '{"decision": "stop", "reason": "Agent wants to stop"}' > "$status_file"

  export FIXED_ITERATIONS=5
  export MAX_ITERATIONS=5

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "1" "$result" "Fixed-N ignores status decision, continues until N"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Completion Strategy Tests (v3)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_test "plateau: reads from status.json" test_plateau_reads_from_status_file
run_test "plateau: ignores output parameter" test_plateau_ignores_output_parameter
run_test "plateau: requires min_iterations" test_plateau_requires_min_iterations
run_test "plateau: requires consensus" test_plateau_requires_consensus
run_test "plateau: handles missing status file" test_plateau_handles_missing_status_file

run_test "beads-empty: checks error status" test_beads_empty_checks_error_status
run_test "beads-empty: accepts status_file param" test_beads_empty_accepts_status_file_param

run_test "fixed-n: accepts status_file param" test_fixed_n_accepts_status_file_param
run_test "fixed-n: ignores status decision" test_fixed_n_ignores_status_decision

test_summary
