#!/bin/bash
# Tests for mock execution library (scripts/lib/mock.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/mock.sh"

#-------------------------------------------------------------------------------
# Mock Mode Control Tests
#-------------------------------------------------------------------------------

test_mock_mode_disabled_by_default() {
  # Mock mode should be disabled by default
  assert_false "$MOCK_MODE" "Mock mode disabled by default"
}

test_enable_mock_mode() {
  # Should enable mock mode with fixtures directory
  local fixtures="$SCRIPT_DIR/loops/work/fixtures"
  enable_mock_mode "$fixtures"

  assert_true "$MOCK_MODE" "Mock mode enabled"
  assert_eq "$fixtures" "$MOCK_FIXTURES_DIR" "Fixtures directory set"

  disable_mock_mode
}

test_disable_mock_mode() {
  # Should disable mock mode
  enable_mock_mode "$SCRIPT_DIR/loops/work/fixtures"
  disable_mock_mode

  assert_false "$MOCK_MODE" "Mock mode disabled"
  assert_eq "" "$MOCK_FIXTURES_DIR" "Fixtures directory cleared"
}

test_is_mock_mode() {
  # is_mock_mode should return correct status
  disable_mock_mode
  is_mock_mode
  local result=$?
  assert_eq "1" "$result" "is_mock_mode returns 1 when disabled"

  enable_mock_mode "$SCRIPT_DIR/loops/work/fixtures"
  is_mock_mode
  result=$?
  assert_eq "0" "$result" "is_mock_mode returns 0 when enabled"

  disable_mock_mode
}

#-------------------------------------------------------------------------------
# Mock Response Tests
#-------------------------------------------------------------------------------

test_get_mock_response_default() {
  # Should return default fixture when no iteration-specific one exists
  enable_mock_mode "$SCRIPT_DIR/loops/work/fixtures"

  local response=$(get_mock_response 99)

  assert_contains "$response" "Mock Work Iteration" "Returns default fixture content"

  disable_mock_mode
}

test_get_mock_response_iteration_specific() {
  # Should return iteration-specific fixture when it exists
  enable_mock_mode "$SCRIPT_DIR/loops/improve-plan/fixtures"

  local response=$(get_mock_response 1)
  assert_contains "$response" "Initial Review" "Returns iteration-1 fixture"

  response=$(get_mock_response 2)
  assert_contains "$response" "Refinement" "Returns iteration-2 fixture"

  response=$(get_mock_response 3)
  assert_contains "$response" "Confirmation" "Returns iteration-3 fixture"

  disable_mock_mode
}

test_get_mock_response_plateau_detection() {
  # Fixtures should contain correct PLATEAU values
  enable_mock_mode "$SCRIPT_DIR/loops/improve-plan/fixtures"

  local response1=$(get_mock_response 1)
  assert_contains "$response1" "PLATEAU: false" "Iteration 1 continues"

  local response2=$(get_mock_response 2)
  assert_contains "$response2" "PLATEAU: true" "Iteration 2 suggests stop"

  local response3=$(get_mock_response 3)
  assert_contains "$response3" "PLATEAU: true" "Iteration 3 confirms stop"

  disable_mock_mode
}

#-------------------------------------------------------------------------------
# v3 Status File Tests
#-------------------------------------------------------------------------------

test_get_mock_status() {
  # Should return status JSON for iteration
  enable_mock_mode "$SCRIPT_DIR/loops/improve-plan/fixtures"

  local status=$(get_mock_status 1)
  local decision=$(echo "$status" | jq -r '.decision')
  assert_eq "continue" "$decision" "Iteration 1 status is continue"

  status=$(get_mock_status 2)
  decision=$(echo "$status" | jq -r '.decision')
  assert_eq "stop" "$decision" "Iteration 2 status is stop"

  disable_mock_mode
}

test_generate_default_status() {
  # Should generate valid status JSON
  local status=$(generate_default_status "continue")
  local decision=$(echo "$status" | jq -r '.decision')
  assert_eq "continue" "$decision" "Generated continue status"

  status=$(generate_default_status "stop")
  decision=$(echo "$status" | jq -r '.decision')
  assert_eq "stop" "$decision" "Generated stop status"

  status=$(generate_default_status "error")
  decision=$(echo "$status" | jq -r '.decision')
  assert_eq "error" "$decision" "Generated error status"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "Mock mode disabled by default" test_mock_mode_disabled_by_default
run_test "Enable mock mode" test_enable_mock_mode
run_test "Disable mock mode" test_disable_mock_mode
run_test "is_mock_mode function" test_is_mock_mode
run_test "Get mock response (default)" test_get_mock_response_default
run_test "Get mock response (iteration-specific)" test_get_mock_response_iteration_specific
run_test "Mock response plateau detection" test_get_mock_response_plateau_detection
run_test "Get mock status" test_get_mock_status
run_test "Generate default status" test_generate_default_status
