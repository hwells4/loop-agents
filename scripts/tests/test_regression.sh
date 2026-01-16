#!/bin/bash
# Regression tests for v3 migration
# Verifies all stages use v3 schema and prompts use new variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"

STAGES_DIR="$SCRIPT_DIR/stages"

#-------------------------------------------------------------------------------
# Stage Definition Tests (v3 schema)
#-------------------------------------------------------------------------------

test_ralph_stage_v3_schema() {
  local config=$(yaml_to_json "$STAGES_DIR/ralph/stage.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  assert_eq "fixed" "$term_type" "ralph stage uses termination.type=fixed"
}

test_improve_plan_stage_v3_schema() {
  local config=$(yaml_to_json "$STAGES_DIR/improve-plan/stage.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "improve-plan uses termination.type=judgment"
  assert_eq "2" "$consensus" "improve-plan requires consensus=2"
}

test_elegance_stage_v3_schema() {
  local config=$(yaml_to_json "$STAGES_DIR/elegance/stage.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "elegance uses termination.type=judgment"
  assert_eq "2" "$consensus" "elegance requires consensus=2"
}

test_idea_wizard_stage_v3_schema() {
  local config=$(yaml_to_json "$STAGES_DIR/idea-wizard/stage.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  assert_eq "fixed" "$term_type" "idea-wizard uses termination.type=fixed"
}

test_refine_beads_stage_v3_schema() {
  local config=$(yaml_to_json "$STAGES_DIR/refine-tasks/stage.yaml")
  local term_type=$(echo "$config" | jq -r '.termination.type // empty')
  local consensus=$(echo "$config" | jq -r '.termination.consensus // empty')
  assert_eq "judgment" "$term_type" "refine-tasks uses termination.type=judgment"
  assert_eq "2" "$consensus" "refine-tasks requires consensus=2"
}

#-------------------------------------------------------------------------------
# Prompt Variable Tests (v3 variables)
#-------------------------------------------------------------------------------

# Helper: get actual prompt file path from stage.yaml
# Handles both default prompt.md and custom prompt paths
get_prompt_path() {
  local loop_dir=$1
  local config_file="$loop_dir/stage.yaml"

  if [ ! -f "$config_file" ]; then
    echo ""
    return
  fi

  local config=$(yaml_to_json "$config_file")
  local prompt_field=$(echo "$config" | jq -r '.prompt // empty')

  if [ -n "$prompt_field" ]; then
    # Custom prompt path specified - check if it's a path or just a name
    if [[ "$prompt_field" == *"/"* ]]; then
      # It's a relative path like "prompts/bead-refiner.md"
      echo "$loop_dir/$prompt_field"
    elif [[ "$prompt_field" == *.md ]]; then
      # It's a filename with extension
      echo "$loop_dir/$prompt_field"
    else
      # It's just a name, check prompts/ directory first
      if [ -f "$loop_dir/prompts/${prompt_field}.md" ]; then
        echo "$loop_dir/prompts/${prompt_field}.md"
      else
        echo "$loop_dir/${prompt_field}.md"
      fi
    fi
  else
    # Default: prompt.md in loop directory
    echo "$loop_dir/prompt.md"
  fi
}

test_prompts_use_ctx_variable() {
  for loop_dir in "$STAGES_DIR"/*/; do
    local loop_name=$(basename "$loop_dir")
    local prompt_file=$(get_prompt_path "$loop_dir")

    if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
      echo "  Warning: No prompt file found for $loop_name"
      continue
    fi

    local content=$(cat "$prompt_file")
    assert_contains "$content" '${CTX}' "$loop_name prompt uses \${CTX}"
  done
}

test_prompts_use_result_variable() {
  for loop_dir in "$STAGES_DIR"/*/; do
    local loop_name=$(basename "$loop_dir")
    local prompt_file=$(get_prompt_path "$loop_dir")

    if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
      echo "  Warning: No prompt file found for $loop_name"
      continue
    fi

    local content=$(cat "$prompt_file")
    assert_contains "$content" '${RESULT}' "$loop_name prompt uses \${RESULT}"
  done
}

test_no_deprecated_output_parse() {
  for loop_dir in "$STAGES_DIR"/*/; do
    local config_file="$loop_dir/stage.yaml"
    [ -f "$config_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local content=$(cat "$config_file")
    assert_not_contains "$content" "output_parse" "$loop_name has no deprecated output_parse"
  done
}

test_no_deprecated_completion_field() {
  for loop_dir in "$STAGES_DIR"/*/; do
    local config_file="$loop_dir/stage.yaml"
    [ -f "$config_file" ] || continue
    local loop_name=$(basename "$loop_dir")
    local config=$(yaml_to_json "$config_file")
    local old_completion=$(echo "$config" | jq -r '.completion // empty')
    # Old completion field should be empty (v3 uses termination block)
    assert_eq "" "$old_completion" "$loop_name has no deprecated completion field"
  done
}

#-------------------------------------------------------------------------------
# Deprecated Code Removal Tests
#-------------------------------------------------------------------------------

test_parse_sh_removed() {
  local parse_file="$SCRIPT_DIR/lib/parse.sh"
  assert_file_not_exists "$parse_file" "parse.sh should be removed (deprecated in v3)"
}

test_all_items_sh_removed() {
  local all_items_file="$SCRIPT_DIR/lib/completions/all-items.sh"
  assert_file_not_exists "$all_items_file" "all-items.sh should be removed (unused in v3)"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "ralph stage v3 schema" test_ralph_stage_v3_schema
run_test "improve-plan stage v3 schema" test_improve_plan_stage_v3_schema
run_test "elegance stage v3 schema" test_elegance_stage_v3_schema
run_test "idea-wizard stage v3 schema" test_idea_wizard_stage_v3_schema
run_test "refine-tasks stage v3 schema" test_refine_beads_stage_v3_schema
run_test "Prompts use CTX variable" test_prompts_use_ctx_variable
run_test "Prompts use RESULT variable" test_prompts_use_result_variable
run_test "No deprecated output_parse" test_no_deprecated_output_parse
run_test "No deprecated completion field" test_no_deprecated_completion_field
run_test "parse.sh removed" test_parse_sh_removed
run_test "all-items.sh removed" test_all_items_sh_removed

test_summary
