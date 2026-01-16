#!/bin/bash
# Tests for validation library (scripts/lib/validate.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/validate.sh"

#-------------------------------------------------------------------------------
# Loop Validation Tests
#-------------------------------------------------------------------------------

test_validate_ralph_loop() {
  # Ralph loop should pass validation
  validate_loop "ralph" "--quiet"
  local result=$?
  assert_eq "0" "$result" "ralph loop passes validation"
}

test_validate_improve_plan_loop() {
  # Improve-plan loop should pass validation
  validate_loop "improve-plan" "--quiet"
  local result=$?
  assert_eq "0" "$result" "improve-plan loop passes validation"
}

test_validate_elegance_loop() {
  # Elegance loop should pass validation
  validate_loop "elegance" "--quiet"
  local result=$?
  assert_eq "0" "$result" "elegance loop passes validation"
}

test_validate_idea_wizard_loop() {
  # Idea-wizard loop should pass validation
  validate_loop "idea-wizard" "--quiet"
  local result=$?
  assert_eq "0" "$result" "idea-wizard loop passes validation"
}

test_validate_nonexistent_loop() {
  # Non-existent loop should fail validation
  validate_loop "nonexistent-loop-xyz" "--quiet" 2>/dev/null
  local result=$?
  assert_eq "1" "$result" "nonexistent loop fails validation"
}

#-------------------------------------------------------------------------------
# Pipeline Validation Tests
#-------------------------------------------------------------------------------

test_validate_refine_pipeline() {
  # Refine pipeline should pass validation
  validate_pipeline "refine" "--quiet"
  local result=$?
  assert_eq "0" "$result" "refine pipeline passes validation"
}

test_validate_bug_hunt_pipeline() {
  # Bug-hunt pipeline should pass validation
  validate_pipeline "bug-hunt" "--quiet"
  local result=$?
  assert_eq "0" "$result" "bug-hunt pipeline passes validation"
}

test_validate_dual_analyze_pipeline() {
  # Dual-analyze pipeline should pass validation
  validate_pipeline "dual-analyze" "--quiet"
  local result=$?
  assert_eq "0" "$result" "dual-analyze pipeline passes validation"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Validate ralph loop" test_validate_ralph_loop
run_test "Validate improve-plan loop" test_validate_improve_plan_loop
run_test "Validate elegance loop" test_validate_elegance_loop
run_test "Validate idea-wizard loop" test_validate_idea_wizard_loop
run_test "Validate nonexistent loop fails" test_validate_nonexistent_loop
run_test "Validate refine pipeline" test_validate_refine_pipeline
run_test "Validate bug-hunt pipeline" test_validate_bug_hunt_pipeline
run_test "Validate dual-analyze pipeline" test_validate_dual_analyze_pipeline

test_summary
