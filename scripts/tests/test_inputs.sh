#!/bin/bash
# Tests for input selection (Phase 4)
# Tests build_inputs_json function for explicit input selection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/context.sh"

#-------------------------------------------------------------------------------
# Input Resolution Tests - from previous stage
#-------------------------------------------------------------------------------

test_inputs_from_previous_stage_latest() {
  # Setup: Stage 2 with inputs.from=stage1, inputs.select=latest
  # Stage 1 has iterations 001, 002, 003
  # Expected: inputs.from_stage.stage1 contains only iteration 003 output
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  mkdir -p "$tmp/stage-00-stage1/iterations/002"
  mkdir -p "$tmp/stage-00-stage1/iterations/003"
  echo "output1" > "$tmp/stage-00-stage1/iterations/001/output.md"
  echo "output2" > "$tmp/stage-00-stage1/iterations/002/output.md"
  echo "output3" > "$tmp/stage-00-stage1/iterations/003/output.md"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"latest"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local count=$(echo "$inputs" | jq '.from_stage.stage1 | length')
  local file=$(echo "$inputs" | jq -r '.from_stage.stage1[0]')

  assert_eq "1" "$count" "select=latest returns single file"
  assert_contains "$file" "003/output.md" "select=latest returns latest iteration"

  cleanup_test_dir "$tmp"
}

test_inputs_from_previous_stage_all() {
  # Setup: Stage 2 with inputs.from=stage1, inputs.select=all
  # Stage 1 has iterations 001, 002, 003
  # Expected: inputs.from_stage.stage1 contains all 3 outputs
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  mkdir -p "$tmp/stage-00-stage1/iterations/002"
  mkdir -p "$tmp/stage-00-stage1/iterations/003"
  echo "output1" > "$tmp/stage-00-stage1/iterations/001/output.md"
  echo "output2" > "$tmp/stage-00-stage1/iterations/002/output.md"
  echo "output3" > "$tmp/stage-00-stage1/iterations/003/output.md"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"all"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local count=$(echo "$inputs" | jq '.from_stage.stage1 | length')

  assert_eq "3" "$count" "select=all returns all files"

  cleanup_test_dir "$tmp"
}

test_inputs_default_is_latest() {
  # Setup: Stage 2 with inputs.from=stage1, NO select specified
  # Expected: Defaults to select=latest behavior
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  mkdir -p "$tmp/stage-00-stage1/iterations/002"
  echo "output1" > "$tmp/stage-00-stage1/iterations/001/output.md"
  echo "output2" > "$tmp/stage-00-stage1/iterations/002/output.md"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local count=$(echo "$inputs" | jq '.from_stage.stage1 | length')

  assert_eq "1" "$count" "default select is latest (single file)"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Input Resolution Tests - from previous iterations
#-------------------------------------------------------------------------------

test_inputs_from_previous_iterations() {
  # Setup: Stage at iteration 3
  # Expected: from_previous_iterations contains iterations 1 and 2
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-current/iterations/001"
  mkdir -p "$tmp/stage-00-current/iterations/002"
  echo "iter1" > "$tmp/stage-00-current/iterations/001/output.md"
  echo "iter2" > "$tmp/stage-00-current/iterations/002/output.md"

  local config='{"id":"current","index":0}'
  local inputs=$(build_inputs_json "$tmp" "$config" 3)
  local count=$(echo "$inputs" | jq '.from_previous_iterations | length')

  assert_eq "2" "$count" "iteration 3 sees 2 previous iterations"

  cleanup_test_dir "$tmp"
}

test_inputs_first_iteration_empty_previous() {
  # Setup: Stage at iteration 1
  # Expected: from_previous_iterations is empty
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-current/iterations"

  local config='{"id":"current","index":0}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local count=$(echo "$inputs" | jq '.from_previous_iterations | length')

  assert_eq "0" "$count" "iteration 1 has no previous iterations"

  cleanup_test_dir "$tmp"
}

test_inputs_iteration_ordering() {
  # Setup: Stage at iteration 4 with outputs for 1, 2, 3
  # Expected: from_previous_iterations in correct order
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-work/iterations/001"
  mkdir -p "$tmp/stage-00-work/iterations/002"
  mkdir -p "$tmp/stage-00-work/iterations/003"
  echo "first" > "$tmp/stage-00-work/iterations/001/output.md"
  echo "second" > "$tmp/stage-00-work/iterations/002/output.md"
  echo "third" > "$tmp/stage-00-work/iterations/003/output.md"

  local config='{"id":"work","index":0}'
  local inputs=$(build_inputs_json "$tmp" "$config" 4)

  local first=$(echo "$inputs" | jq -r '.from_previous_iterations[0]')
  local second=$(echo "$inputs" | jq -r '.from_previous_iterations[1]')
  local third=$(echo "$inputs" | jq -r '.from_previous_iterations[2]')

  assert_contains "$first" "001/output.md" "First iteration output is first"
  assert_contains "$second" "002/output.md" "Second iteration output is second"
  assert_contains "$third" "003/output.md" "Third iteration output is third"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Edge Cases
#-------------------------------------------------------------------------------

test_inputs_nonexistent_stage() {
  # Setup: inputs.from references a stage that doesn't exist
  # Expected: from_stage is empty object, no error
  local tmp=$(create_test_dir)
  local config='{"id":"stage2","index":1,"inputs":{"from":"nonexistent"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local from_stage=$(echo "$inputs" | jq -c '.from_stage')

  assert_eq "{}" "$from_stage" "nonexistent stage returns empty object"

  cleanup_test_dir "$tmp"
}

test_inputs_stage_with_no_outputs() {
  # Setup: Stage exists but has no iteration outputs
  # Expected: from_stage has empty array for that stage
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"latest"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local files=$(echo "$inputs" | jq -c '.from_stage.stage1 // []')

  assert_eq "[]" "$files" "stage with no outputs returns empty array"

  cleanup_test_dir "$tmp"
}

test_inputs_no_from_configured() {
  # Setup: Stage config has no inputs.from
  # Expected: from_stage is empty object
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-work/iterations/001"
  echo "output" > "$tmp/stage-00-work/iterations/001/output.md"

  local config='{"id":"work","index":0}'
  local inputs=$(build_inputs_json "$tmp" "$config" 2)
  local from_stage=$(echo "$inputs" | jq -c '.from_stage')

  assert_eq "{}" "$from_stage" "no inputs.from results in empty from_stage"

  cleanup_test_dir "$tmp"
}

test_inputs_all_select_with_partial_iterations() {
  # Setup: Stage with 5 iterations, but only some have output.md
  # Expected: Only iterations with output.md are included
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  mkdir -p "$tmp/stage-00-stage1/iterations/002"
  mkdir -p "$tmp/stage-00-stage1/iterations/003"  # No output.md here
  mkdir -p "$tmp/stage-00-stage1/iterations/004"
  echo "output1" > "$tmp/stage-00-stage1/iterations/001/output.md"
  echo "output2" > "$tmp/stage-00-stage1/iterations/002/output.md"
  # Skip 003
  echo "output4" > "$tmp/stage-00-stage1/iterations/004/output.md"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"all"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 1)
  local count=$(echo "$inputs" | jq '.from_stage.stage1 | length')

  assert_eq "3" "$count" "select=all only includes iterations with output.md"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Context Integration Tests
#-------------------------------------------------------------------------------

test_inputs_in_context_json() {
  # Setup: Generate context for stage 2 with inputs.from=stage1
  # Expected: context.json includes resolved inputs
  local tmp=$(create_test_dir)
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  echo "prev output" > "$tmp/stage-00-stage1/iterations/001/output.md"

  local stage_config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"latest"}}'
  local context_file=$(generate_context "test-session" "1" "$stage_config" "$tmp")

  local from_stage=$(jq -c '.inputs.from_stage' "$context_file")
  assert_neq "{}" "$from_stage" "context.json includes inputs.from_stage"

  local stage1_files=$(jq '.inputs.from_stage.stage1 | length' "$context_file")
  assert_eq "1" "$stage1_files" "context.json has stage1 input file"

  cleanup_test_dir "$tmp"
}

test_inputs_combined_from_stage_and_iterations() {
  # Setup: Stage 2 iteration 3 with inputs from stage1 AND previous iterations
  # Expected: Both from_stage and from_previous_iterations populated
  local tmp=$(create_test_dir)

  # Previous stage outputs
  mkdir -p "$tmp/stage-00-stage1/iterations/001"
  echo "stage1 output" > "$tmp/stage-00-stage1/iterations/001/output.md"

  # Current stage previous iterations
  mkdir -p "$tmp/stage-01-stage2/iterations/001"
  mkdir -p "$tmp/stage-01-stage2/iterations/002"
  echo "stage2 iter1" > "$tmp/stage-01-stage2/iterations/001/output.md"
  echo "stage2 iter2" > "$tmp/stage-01-stage2/iterations/002/output.md"

  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"latest"}}'
  local inputs=$(build_inputs_json "$tmp" "$config" 3)

  local stage_files=$(echo "$inputs" | jq '.from_stage.stage1 | length')
  local iter_files=$(echo "$inputs" | jq '.from_previous_iterations | length')

  assert_eq "1" "$stage_files" "Has input from previous stage"
  assert_eq "2" "$iter_files" "Has inputs from previous iterations"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Inputs from previous stage (latest)" test_inputs_from_previous_stage_latest
run_test "Inputs from previous stage (all)" test_inputs_from_previous_stage_all
run_test "Inputs default is latest" test_inputs_default_is_latest
run_test "Inputs from previous iterations" test_inputs_from_previous_iterations
run_test "Inputs first iteration empty" test_inputs_first_iteration_empty_previous
run_test "Inputs iteration ordering" test_inputs_iteration_ordering
run_test "Inputs nonexistent stage" test_inputs_nonexistent_stage
run_test "Inputs stage with no outputs" test_inputs_stage_with_no_outputs
run_test "Inputs no from configured" test_inputs_no_from_configured
run_test "Inputs all select with partial iterations" test_inputs_all_select_with_partial_iterations
run_test "Inputs in context.json" test_inputs_in_context_json
run_test "Inputs combined from stage and iterations" test_inputs_combined_from_stage_and_iterations

#-------------------------------------------------------------------------------
# Pipeline Stage Config Tests
#-------------------------------------------------------------------------------

test_inputs_config_parsing() {
  # Verify inputs config is correctly extracted from stage config
  local config='{"id":"stage2","index":1,"inputs":{"from":"stage1","select":"all"}}'
  local inputs_from=$(echo "$config" | jq -r '.inputs.from // ""')
  local inputs_select=$(echo "$config" | jq -r '.inputs.select // "latest"')

  assert_eq "stage1" "$inputs_from" "inputs.from is parsed correctly"
  assert_eq "all" "$inputs_select" "inputs.select is parsed correctly"
}

test_inputs_config_defaults() {
  # Verify default values when inputs config is missing
  local config='{"id":"stage2","index":1}'
  local inputs_from=$(echo "$config" | jq -r '.inputs.from // ""')
  local inputs_select=$(echo "$config" | jq -r '.inputs.select // "latest"')

  assert_eq "" "$inputs_from" "inputs.from defaults to empty"
  assert_eq "latest" "$inputs_select" "inputs.select defaults to latest"
}

run_test "Inputs config parsing" test_inputs_config_parsing
run_test "Inputs config defaults" test_inputs_config_defaults

test_summary
