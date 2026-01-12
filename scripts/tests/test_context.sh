#!/bin/bash
# Context manifest tests - verify v3 context.json generation works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/context.sh"

#-------------------------------------------------------------------------------
# Context Generation Tests
#-------------------------------------------------------------------------------

test_context_file_generated() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  assert_file_exists "$context_file" "context.json is generated"
  assert_contains "$context_file" "context.json" "Path contains context.json"

  rm -rf "$test_dir"
}

test_context_json_structure() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  assert_json_field "$context_file" ".session" "test-session" "session field correct"
  assert_json_field "$context_file" ".iteration" "1" "iteration field correct"
  assert_json_field "$context_file" ".stage.id" "work" "stage.id correct"
  assert_json_field "$context_file" ".stage.index" "0" "stage.index correct"
  assert_json_field "$context_file" ".limits.max_iterations" "25" "limits.max_iterations correct"

  rm -rf "$test_dir"
}

test_context_paths_populated() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  # Check paths contain expected values
  local session_dir=$(jq -r '.paths.session_dir' "$context_file")
  local stage_dir=$(jq -r '.paths.stage_dir' "$context_file")
  local progress=$(jq -r '.paths.progress' "$context_file")
  local status=$(jq -r '.paths.status' "$context_file")

  assert_eq "$test_dir" "$session_dir" "session_dir path correct"
  assert_contains "$stage_dir" "stage-00-work" "stage_dir contains stage name"
  assert_contains "$progress" "progress.md" "progress path ends with progress.md"
  assert_contains "$status" "status.json" "status path ends with status.json"
  assert_contains "$status" "iterations/001" "status path contains iteration directory"

  rm -rf "$test_dir"
}

test_context_iteration_directories_created() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "improve-plan", "name": "improve-plan", "index": 0, "loop": "improve-plan", "max_iterations": 10}'

  # Generate for multiple iterations
  generate_context "test-session" "1" "$stage_config" "$test_dir" > /dev/null
  generate_context "test-session" "2" "$stage_config" "$test_dir" > /dev/null
  generate_context "test-session" "3" "$stage_config" "$test_dir" > /dev/null

  assert_dir_exists "$test_dir/stage-00-improve-plan/iterations/001" "iteration 1 dir created"
  assert_dir_exists "$test_dir/stage-00-improve-plan/iterations/002" "iteration 2 dir created"
  assert_dir_exists "$test_dir/stage-00-improve-plan/iterations/003" "iteration 3 dir created"

  rm -rf "$test_dir"
}

test_context_inputs_empty_for_first_iteration() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  local from_stage=$(jq -c '.inputs.from_stage' "$context_file")
  local from_iterations=$(jq -c '.inputs.from_previous_iterations' "$context_file")

  assert_eq "{}" "$from_stage" "from_stage empty for first iteration"
  assert_eq "[]" "$from_iterations" "from_previous_iterations empty for first iteration"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Resolve Tests (v3 mode)
#-------------------------------------------------------------------------------

test_resolve_v3_variables() {
  source "$SCRIPT_DIR/lib/resolve.sh"

  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  local template='Session: ${SESSION}, Iteration: ${ITERATION}, CTX: ${CTX}'
  # resolve_prompt auto-detects context file and uses v3 mode
  local resolved=$(resolve_prompt "$template" "$context_file")

  assert_contains "$resolved" "Session: test-session" "SESSION resolved"
  assert_contains "$resolved" "Iteration: 1" "ITERATION resolved"
  assert_contains "$resolved" "CTX: $context_file" "CTX resolved to context path"

  rm -rf "$test_dir"
}

test_resolve_auto_detects_context_file() {
  source "$SCRIPT_DIR/lib/resolve.sh"

  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "loop": "work", "max_iterations": 25}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  # Main resolve_prompt should auto-detect context file
  local template='Session: ${SESSION}'
  local resolved=$(resolve_prompt "$template" "$context_file")

  assert_contains "$resolved" "Session: test-session" "Auto-detects context file"

  rm -rf "$test_dir"
}

test_resolve_legacy_json_still_works() {
  source "$SCRIPT_DIR/lib/resolve.sh"

  local template='Session: ${SESSION}, Progress: ${PROGRESS}'
  local vars_json='{"session": "legacy-test", "progress": "/path/to/progress.md"}'
  local resolved=$(resolve_prompt "$template" "$vars_json")

  assert_contains "$resolved" "Session: legacy-test" "Legacy SESSION resolved"
  assert_contains "$resolved" "Progress: /path/to/progress.md" "Legacy PROGRESS resolved"
}

#-------------------------------------------------------------------------------
# Remaining Time Calculation Tests
#-------------------------------------------------------------------------------

test_remaining_time_no_limit_configured() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0}'

  local remaining=$(calculate_remaining_time "$test_dir" "$stage_config")

  assert_eq "-1" "$remaining" "No limit configured returns -1"

  rm -rf "$test_dir"
}

test_remaining_time_with_limit_no_state() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "max_runtime_seconds": 3600}'

  # No state.json exists yet
  local remaining=$(calculate_remaining_time "$test_dir" "$stage_config")

  assert_eq "3600" "$remaining" "Full time returned when no state exists"

  rm -rf "$test_dir"
}

test_remaining_time_calculates_correctly() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "max_runtime_seconds": 3600}'

  # Create state.json with started_at 60 seconds ago
  local started_at=$(date -u -v-60S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '60 seconds ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  echo "{\"started_at\": \"$started_at\"}" > "$test_dir/state.json"

  local remaining=$(calculate_remaining_time "$test_dir" "$stage_config")

  # Should be approximately 3540 (3600 - 60), allow 5 second tolerance
  local expected_min=3535
  local expected_max=3545

  if [ "$remaining" -ge "$expected_min" ] && [ "$remaining" -le "$expected_max" ]; then
    assert_true "true" "Remaining time calculated correctly (~3540s)"
  else
    assert_eq "~3540" "$remaining" "Remaining time calculated correctly"
  fi

  rm -rf "$test_dir"
}

test_remaining_time_returns_zero_when_exceeded() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "max_runtime_seconds": 60}'

  # Create state.json with started_at 120 seconds ago (exceeded)
  local started_at=$(date -u -v-120S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '120 seconds ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  echo "{\"started_at\": \"$started_at\"}" > "$test_dir/state.json"

  local remaining=$(calculate_remaining_time "$test_dir" "$stage_config")

  assert_eq "0" "$remaining" "Returns 0 when time exceeded"

  rm -rf "$test_dir"
}

test_remaining_time_guardrails_block() {
  local test_dir=$(mktemp -d)
  # Test with guardrails.max_runtime_seconds (plan schema)
  local stage_config='{"id": "work", "name": "work", "index": 0, "guardrails": {"max_runtime_seconds": 7200}}'

  local remaining=$(calculate_remaining_time "$test_dir" "$stage_config")

  assert_eq "7200" "$remaining" "Reads from guardrails.max_runtime_seconds"

  rm -rf "$test_dir"
}

test_context_remaining_seconds_populated() {
  local test_dir=$(mktemp -d)
  local stage_config='{"id": "work", "name": "work", "index": 0, "max_runtime_seconds": 3600}'

  local context_file=$(generate_context "test-session" "1" "$stage_config" "$test_dir")

  local remaining=$(jq -r '.limits.remaining_seconds' "$context_file")

  # Should be 3600 since no state.json existed before generate_context created it
  assert_eq "3600" "$remaining" "remaining_seconds populated in context.json"

  rm -rf "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Remaining time: no limit configured" test_remaining_time_no_limit_configured
run_test "Remaining time: with limit, no state" test_remaining_time_with_limit_no_state
run_test "Remaining time: calculates correctly" test_remaining_time_calculates_correctly
run_test "Remaining time: returns 0 when exceeded" test_remaining_time_returns_zero_when_exceeded
run_test "Remaining time: reads guardrails block" test_remaining_time_guardrails_block
run_test "Context remaining_seconds populated" test_context_remaining_seconds_populated
run_test "Context file generated" test_context_file_generated
run_test "Context JSON structure" test_context_json_structure
run_test "Context paths populated" test_context_paths_populated
run_test "Context iteration directories created" test_context_iteration_directories_created
run_test "Context inputs empty for first iteration" test_context_inputs_empty_for_first_iteration
run_test "Resolve v3 variables" test_resolve_v3_variables
run_test "Resolve auto-detects context file" test_resolve_auto_detects_context_file
run_test "Resolve legacy JSON still works" test_resolve_legacy_json_still_works

test_summary
