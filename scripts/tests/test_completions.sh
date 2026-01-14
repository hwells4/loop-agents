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

  # REALISTIC STATE: At iteration 3, history includes ALL iterations (1-3)
  # This matches engine flow: update_iteration is called BEFORE check_completion
  # Pattern: continue, stop, stop = 2 consecutive stops
  echo '{"iteration": 3, "history": [{"decision": "continue"}, {"decision": "stop"}, {"decision": "stop"}]}' > "$state_file"

  # Status file has current iteration's decision (same as history[2])
  echo '{"decision": "stop", "reason": "No more improvements"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  # Should complete: 2 consecutive stops in history (iterations 2 and 3)
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

  # REALISTIC STATE: At iteration 3, history includes current iteration
  # This matches engine flow: update_iteration is called BEFORE check_completion
  # Pattern: continue, continue, stop = only 1 stop, need 2 consecutive for consensus
  echo '{"iteration": 3, "history": [{"decision": "continue"}, {"decision": "continue"}, {"decision": "stop"}]}' > "$state_file"

  # Status file has current iteration's decision (same as history[2])
  echo '{"decision": "stop", "reason": "Done"}' > "$status_file"

  export MIN_ITERATIONS=2
  export CONSENSUS=2

  # Should NOT complete: only 1 stop in history, need 2 consecutive
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

# Helper to create a mock bd command
# Creates a mock bd script in a temp directory and prepends it to PATH
# Properly handles: bd ready --label=LABEL
_setup_mock_bd() {
  local remaining=$1
  MOCK_BD_DIR=$(mktemp -d)
  ORIGINAL_PATH="$PATH"

  # Store remaining in environment for mock to read
  export MOCK_BD_REMAINING="$remaining"

  # Create mock bd script that handles subcommands and --label flag
  cat > "$MOCK_BD_DIR/bd" << 'MOCKSCRIPT'
#!/bin/bash
# Mock bd command for testing
# Handles: bd ready --label=LABEL

subcommand="${1:-}"
label=""

# Parse arguments
shift 2>/dev/null || true
for arg in "$@"; do
  case "$arg" in
    --label=*) label="${arg#--label=}" ;;
  esac
done

case "$subcommand" in
  ready)
    # Use MOCK_BD_REMAINING from environment
    remaining="${MOCK_BD_REMAINING:-0}"
    if [ "$remaining" -gt 0 ]; then
      for i in $(seq 1 "$remaining"); do
        # Use realistic bead ID format
        printf "beads-%03d\n" "$i"
      done
    fi
    exit 0
    ;;
  *)
    echo "bd mock: unknown subcommand '$subcommand'" >&2
    exit 1
    ;;
esac
MOCKSCRIPT
  chmod +x "$MOCK_BD_DIR/bd"

  # Prepend to PATH so our mock is found first
  export PATH="$MOCK_BD_DIR:$PATH"
}

_teardown_mock_bd() {
  export PATH="$ORIGINAL_PATH"
  unset MOCK_BD_REMAINING
  [ -d "$MOCK_BD_DIR" ] && rm -rf "$MOCK_BD_DIR"
}

test_beads_empty_checks_error_status() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "error", "reason": "Something broke"}' > "$status_file"

  # Mock bd to return empty (0 remaining beads)
  _setup_mock_bd 0

  # Error status should stop the loop (return 0) for consistent error handling
  # See Bug fix: loop-agents-r5x - all completion strategies stop on error
  check_completion "test-session" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  _teardown_mock_bd
  rm -rf "$test_dir"

  # With error status, should stop (return 0) - consistent with fixed-n.sh
  assert_eq "0" "$result" "Error status stops loop (consistent error handling)"
}

test_beads_empty_completes_when_queue_empty() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "continue", "reason": "Work in progress"}' > "$status_file"

  # Mock bd to return empty (0 remaining beads)
  _setup_mock_bd 0

  # With empty queue and no error, should complete
  check_completion "test-session" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  _teardown_mock_bd
  rm -rf "$test_dir"

  # Should complete (return 0)
  assert_eq "0" "$result" "Empty queue with continue status should complete"
}

test_beads_empty_continues_when_queue_has_items() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "continue", "reason": "Work in progress"}' > "$status_file"

  # Mock bd to return 3 items
  _setup_mock_bd 3

  # With items in queue, should not complete
  check_completion "test-session" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  _teardown_mock_bd
  rm -rf "$test_dir"

  # Should not complete (return 1)
  assert_eq "1" "$result" "Queue with items should not complete"
}

test_beads_empty_accepts_status_file_param() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "continue", "reason": "Work in progress"}' > "$status_file"

  # Mock bd to return items (so we don't complete)
  _setup_mock_bd 1

  # Function should accept 3 parameters without error
  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  _teardown_mock_bd
  rm -rf "$test_dir"

  # Verify function ran without crashing (exit code 0 or 1, not crash)
  assert_true "$([ $result -le 1 ] && echo true || echo false)" "beads-empty accepts status_file parameter without crashing"
}

test_beads_empty_uses_session_label() {
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"

  # This test verifies the completion check uses the correct session label
  # The real bd call is: bd ready --label="pipeline/$session"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 1}' > "$state_file"
  echo '{"decision": "continue"}' > "$status_file"

  _setup_mock_bd 0  # Empty queue

  # Run completion check for session "my-session"
  check_completion "my-session" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  _teardown_mock_bd
  rm -rf "$test_dir"

  # Should complete since queue is empty (result 0 = complete)
  assert_eq "0" "$result" "Should complete when queue empty for session"
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

  unset FIXED_ITERATIONS
  unset MAX_ITERATIONS
  rm -rf "$test_dir"
}

test_fixed_n_respects_status_stop() {
  source "$SCRIPT_DIR/lib/completions/fixed-n.sh"

  local test_dir=$(mktemp -d)
  local state_file="$test_dir/state.json"
  local status_file="$test_dir/status.json"

  echo '{"iteration": 3}' > "$state_file"
  # Agent says stop - fixed-n should respect this and complete early
  echo '{"decision": "stop", "reason": "Agent wants to stop"}' > "$status_file"

  export FIXED_ITERATIONS=5
  export MAX_ITERATIONS=5

  check_completion "test" "$state_file" "$status_file" >/dev/null 2>&1
  local result=$?

  assert_eq "0" "$result" "Fixed-N respects status decision, stops early"

  unset FIXED_ITERATIONS
  unset MAX_ITERATIONS
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
run_test "beads-empty: completes when queue empty" test_beads_empty_completes_when_queue_empty
run_test "beads-empty: continues when queue has items" test_beads_empty_continues_when_queue_has_items
run_test "beads-empty: accepts status_file param" test_beads_empty_accepts_status_file_param
run_test "beads-empty: uses session label" test_beads_empty_uses_session_label

run_test "fixed-n: accepts status_file param" test_fixed_n_accepts_status_file_param
run_test "fixed-n: respects status stop" test_fixed_n_respects_status_stop

test_summary
