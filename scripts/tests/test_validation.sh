#!/bin/bash
# Tests for validation library (scripts/lib/validate.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/validate.sh"

#-------------------------------------------------------------------------------
# Loop Validation Tests
#-------------------------------------------------------------------------------

test_validate_work_loop() {
  # Work loop should pass validation
  validate_loop "work" "--quiet"
  local result=$?
  assert_eq "0" "$result" "work loop passes validation"
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

test_validate_full_refine_pipeline() {
  # Full-refine pipeline should pass validation
  validate_pipeline "full-refine" "--quiet"
  local result=$?
  assert_eq "0" "$result" "full-refine pipeline passes validation"
}

test_validate_quick_refine_pipeline() {
  # Quick-refine pipeline should pass validation
  validate_pipeline "quick-refine" "--quiet"
  local result=$?
  assert_eq "0" "$result" "quick-refine pipeline passes validation"
}

test_validate_deep_refine_pipeline() {
  # Deep-refine pipeline should pass validation
  validate_pipeline "deep-refine" "--quiet"
  local result=$?
  assert_eq "0" "$result" "deep-refine pipeline passes validation"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Validate work loop" test_validate_work_loop
run_test "Validate improve-plan loop" test_validate_improve_plan_loop
run_test "Validate elegance loop" test_validate_elegance_loop
run_test "Validate idea-wizard loop" test_validate_idea_wizard_loop
run_test "Validate nonexistent loop fails" test_validate_nonexistent_loop
run_test "Validate full-refine pipeline" test_validate_full_refine_pipeline
run_test "Validate quick-refine pipeline" test_validate_quick_refine_pipeline
run_test "Validate deep-refine pipeline" test_validate_deep_refine_pipeline
