#!/bin/bash
# Tests for loop fixtures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGES_DIR="$SCRIPT_DIR/stages"

#-------------------------------------------------------------------------------
# Fixture Directory Tests
#-------------------------------------------------------------------------------

test_work_fixtures_exist() {
  assert_dir_exists "$STAGES_DIR/work/fixtures" "work fixtures directory exists"
  assert_file_exists "$STAGES_DIR/work/fixtures/default.txt" "work default fixture exists"
  assert_file_exists "$STAGES_DIR/work/fixtures/status.json" "work status template exists"
}

test_improve_plan_fixtures_exist() {
  assert_dir_exists "$STAGES_DIR/improve-plan/fixtures" "improve-plan fixtures directory exists"
  assert_file_exists "$STAGES_DIR/improve-plan/fixtures/default.txt" "improve-plan default fixture"
  assert_file_exists "$STAGES_DIR/improve-plan/fixtures/iteration-1.txt" "improve-plan iteration 1"
  assert_file_exists "$STAGES_DIR/improve-plan/fixtures/iteration-2.txt" "improve-plan iteration 2"
  assert_file_exists "$STAGES_DIR/improve-plan/fixtures/iteration-3.txt" "improve-plan iteration 3"
}

test_elegance_fixtures_exist() {
  assert_dir_exists "$STAGES_DIR/elegance/fixtures" "elegance fixtures directory exists"
  assert_file_exists "$STAGES_DIR/elegance/fixtures/default.txt" "elegance default fixture"
  assert_file_exists "$STAGES_DIR/elegance/fixtures/status.json" "elegance status template"
}

test_idea_wizard_fixtures_exist() {
  assert_dir_exists "$STAGES_DIR/idea-wizard/fixtures" "idea-wizard fixtures directory exists"
  assert_file_exists "$STAGES_DIR/idea-wizard/fixtures/default.txt" "idea-wizard default fixture"
  assert_file_exists "$STAGES_DIR/idea-wizard/fixtures/status.json" "idea-wizard status template"
}

test_refine_beads_fixtures_exist() {
  assert_dir_exists "$STAGES_DIR/refine-beads/fixtures" "refine-beads fixtures directory exists"
  assert_file_exists "$STAGES_DIR/refine-beads/fixtures/default.txt" "refine-beads default fixture"
  assert_file_exists "$STAGES_DIR/refine-beads/fixtures/status.json" "refine-beads status template"
}

#-------------------------------------------------------------------------------
# Status JSON Validity Tests
#-------------------------------------------------------------------------------

test_status_json_valid_schema() {
  # All status.json files should have valid decision field
  for loop_dir in "$STAGES_DIR"/*/; do
    local loop_name=$(basename "$loop_dir")
    local status_file="$loop_dir/fixtures/status.json"

    if [ -f "$status_file" ]; then
      local decision=$(jq -r '.decision // empty' "$status_file" 2>/dev/null)

      case "$decision" in
        continue|stop|error)
          assert_true "true" "$loop_name status.json has valid decision: $decision"
          ;;
        *)
          assert_true "false" "$loop_name status.json has invalid decision: $decision"
          ;;
      esac
    fi
  done
}

test_improve_plan_status_sequence() {
  # Verify improve-plan status files have correct sequence for plateau
  local fixtures="$STAGES_DIR/improve-plan/fixtures"

  # Status 1 should be continue
  assert_json_field "$fixtures/status-1.json" ".decision" "continue" "Status 1 is continue"

  # Status 2 should be stop
  assert_json_field "$fixtures/status-2.json" ".decision" "stop" "Status 2 is stop"

  # Status 3 should be stop (confirming plateau)
  assert_json_field "$fixtures/status-3.json" ".decision" "stop" "Status 3 is stop"
}

#-------------------------------------------------------------------------------
# Fixture Content Tests
#-------------------------------------------------------------------------------

test_plateau_fixtures_have_required_fields() {
  # Plateau loops should have PLATEAU: and REASONING: in fixtures
  for loop_dir in "$STAGES_DIR"/*/; do
    local loop_name=$(basename "$loop_dir")
    local config_file="$loop_dir/loop.yaml"

    if [ -f "$config_file" ]; then
      local completion=$(grep "^completion:" "$config_file" | cut -d: -f2 | tr -d ' ')

      if [ "$completion" = "plateau" ]; then
        local default_fixture="$loop_dir/fixtures/default.txt"
        if [ -f "$default_fixture" ]; then
          local content=$(cat "$default_fixture")
          assert_contains "$content" "PLATEAU:" "$loop_name default fixture has PLATEAU field"
          assert_contains "$content" "REASONING:" "$loop_name default fixture has REASONING field"
        fi
      fi
    fi
  done
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Work fixtures exist" test_work_fixtures_exist
run_test "Improve-plan fixtures exist" test_improve_plan_fixtures_exist
run_test "Elegance fixtures exist" test_elegance_fixtures_exist
run_test "Idea-wizard fixtures exist" test_idea_wizard_fixtures_exist
run_test "Refine-beads fixtures exist" test_refine_beads_fixtures_exist
run_test "Status JSON valid schema" test_status_json_valid_schema
run_test "Improve-plan status sequence" test_improve_plan_status_sequence
run_test "Plateau fixtures have required fields" test_plateau_fixtures_have_required_fields
