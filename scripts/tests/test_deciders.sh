#!/bin/bash
# Tests for termination deciders (scripts/lib/deciders.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/events.sh"
source "$SCRIPT_DIR/lib/deciders.sh"

_reset_project_root() {
  local previous_root=$1

  if [ -n "$previous_root" ]; then
    export PROJECT_ROOT="$previous_root"
  else
    unset PROJECT_ROOT
  fi
}

#-------------------------------------------------------------------------------
# Fixed decider tests
#-------------------------------------------------------------------------------

test_decider_fixed_stops_at_max() {
  local result
  result=$(decider_fixed 3 3)
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  assert_eq "stop" "$decision" "fixed decider stops at max"

  result=$(decider_fixed 2 3)
  decision=$(echo "$result" | jq -r '.decision')
  assert_eq "continue" "$decision" "fixed decider continues under max"
}

#-------------------------------------------------------------------------------
# Queue decider tests
#-------------------------------------------------------------------------------

test_decider_queue_empty_output_stops() {
  local result
  result=$(decider_queue "printf ''")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  assert_eq "stop" "$decision" "queue decider stops when command output is empty"
}

test_decider_queue_nonempty_continues() {
  local result
  result=$(decider_queue "printf 'item\n'")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  assert_eq "continue" "$decision" "queue decider continues when output has items"
}

test_decider_queue_handles_failure() {
  local result
  result=$(decider_queue "exit 1")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  local reason
  reason=$(echo "$result" | jq -r '.reason')
  assert_eq "continue" "$decision" "queue decider continues on command failure"
  assert_eq "queue_command_failed" "$reason" "queue decider records failure reason"
}

#-------------------------------------------------------------------------------
# Judgment decider tests
#-------------------------------------------------------------------------------

test_decider_judgment_respects_min_iterations() {
  local tmp
  tmp=$(create_test_dir "deciders")
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="judgment-min"

  judge_decision() {
    echo '{"stop": true, "reason": "done", "confidence": 0.9}'
  }

  local result
  result=$(decider_judgment "$session" "0" 1 1 2 2 "/tmp/result.json" "/tmp/progress.md" "node" "stage" "{}")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  local reason
  reason=$(echo "$result" | jq -r '.reason')
  assert_eq "continue" "$decision" "judgment decider waits for min iterations"
  assert_eq "min_iterations" "$reason" "judgment decider reports min_iterations"

  unset -f judge_decision
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_decider_judgment_consecutive_stops_required() {
  local tmp
  tmp=$(create_test_dir "deciders")
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="judgment-consensus"

  local cursor
  cursor=$(jq -n --arg path "0" --argjson run 1 --argjson iter 1 \
    '{node_path: $path, node_run: $run, iteration: $iter}')
  append_event "decision" "$session" "$cursor" \
    '{"decision":"stop","reason":"prior","termination_type":"judgment"}'

  judge_decision() {
    echo '{"stop": true, "reason": "done", "confidence": 0.9}'
  }

  local result
  result=$(decider_judgment "$session" "0" 1 2 1 2 "/tmp/result.json" "/tmp/progress.md" "node" "stage" "{}")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  assert_eq "stop" "$decision" "judgment decider stops after consecutive stops"

  unset -f judge_decision
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_decider_judgment_waits_for_consensus() {
  local tmp
  tmp=$(create_test_dir "deciders")
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="judgment-wait"

  local cursor
  cursor=$(jq -n --arg path "0" --argjson run 1 --argjson iter 1 \
    '{node_path: $path, node_run: $run, iteration: $iter}')
  append_event "decision" "$session" "$cursor" \
    '{"decision":"continue","reason":"prior","termination_type":"judgment"}'

  judge_decision() {
    echo '{"stop": true, "reason": "done", "confidence": 0.9}'
  }

  local result
  result=$(decider_judgment "$session" "0" 1 2 1 2 "/tmp/result.json" "/tmp/progress.md" "node" "stage" "{}")
  local decision
  decision=$(echo "$result" | jq -r '.decision')
  local reason
  reason=$(echo "$result" | jq -r '.reason')
  assert_eq "continue" "$decision" "judgment decider waits for consensus"
  assert_eq "judgment_waiting" "$reason" "judgment decider reports waiting state"

  unset -f judge_decision
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Termination Deciders"
echo "==============================================================="

run_test "fixed decider stops at max" test_decider_fixed_stops_at_max
run_test "queue decider stops on empty output" test_decider_queue_empty_output_stops
run_test "queue decider continues on nonempty output" test_decider_queue_nonempty_continues
run_test "queue decider handles command failure" test_decider_queue_handles_failure
run_test "judgment decider respects min_iterations" test_decider_judgment_respects_min_iterations
run_test "judgment decider requires consecutive stops" test_decider_judgment_consecutive_stops_required
run_test "judgment decider waits for consensus" test_decider_judgment_waits_for_consensus

test_summary
