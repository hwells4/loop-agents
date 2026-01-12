#!/bin/bash
# Infrastructure tests - verify the test harness and core dependencies work

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#-------------------------------------------------------------------------------
# Dependency Tests
#-------------------------------------------------------------------------------

test_jq_available() {
  command -v jq &>/dev/null
  local result=$?
  assert_eq "0" "$result" "jq is installed"
}

test_bash_version() {
  # Need bash 3.2+ (macOS default), 4+ preferred
  local version="${BASH_VERSION%%.*}"
  local is_sufficient=$( [ "$version" -ge 3 ] && echo "true" || echo "false" )
  assert_true "$is_sufficient" "Bash version is 3+ (got: $BASH_VERSION)"
}

#-------------------------------------------------------------------------------
# Directory Structure Tests
#-------------------------------------------------------------------------------

test_scripts_directory_structure() {
  assert_dir_exists "$SCRIPT_DIR" "scripts directory exists"
  assert_dir_exists "$SCRIPT_DIR/lib" "lib directory exists"
  assert_dir_exists "$SCRIPT_DIR/loops" "loops directory exists"
  assert_dir_exists "$SCRIPT_DIR/pipelines" "pipelines directory exists"
  assert_dir_exists "$SCRIPT_DIR/tests" "tests directory exists"
}

test_lib_files_exist() {
  assert_file_exists "$SCRIPT_DIR/lib/test.sh" "test.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/mock.sh" "mock.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/validate.sh" "validate.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/state.sh" "state.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/progress.sh" "progress.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/resolve.sh" "resolve.sh exists"
  assert_file_exists "$SCRIPT_DIR/lib/lock.sh" "lock.sh exists"
}

test_core_scripts_exist() {
  assert_file_exists "$SCRIPT_DIR/run.sh" "run.sh exists"
  assert_file_exists "$SCRIPT_DIR/engine.sh" "engine.sh exists"
}

#-------------------------------------------------------------------------------
# Loop Directory Structure Tests
#-------------------------------------------------------------------------------

test_loops_have_required_files() {
  for loop_dir in "$SCRIPT_DIR/loops"/*/; do
    [ -d "$loop_dir" ] || continue
    local loop_name=$(basename "$loop_dir")

    assert_file_exists "$loop_dir/stage.yaml" "$loop_name has stage.yaml"

    # Check for prompt file (either prompt.md or in prompts/)
    if [ -f "$loop_dir/prompt.md" ]; then
      assert_file_exists "$loop_dir/prompt.md" "$loop_name has prompt.md"
    elif [ -d "$loop_dir/prompts" ]; then
      local has_prompt=$(ls "$loop_dir/prompts"/*.md 2>/dev/null | head -1)
      assert_true "$([ -n \"$has_prompt\" ] && echo true || echo false)" "$loop_name has prompt in prompts/"
    fi
  done
}

#-------------------------------------------------------------------------------
# Test Library Self-Tests
#-------------------------------------------------------------------------------

test_assert_eq_works() {
  # Meta-test: verify assert_eq works correctly
  local old_passed=$TESTS_PASSED
  local old_failed=$TESTS_FAILED

  # This should pass
  assert_eq "hello" "hello" "String equality" >/dev/null

  # Verify counter incremented
  assert_true "$( [ $TESTS_PASSED -gt $old_passed ] && echo true )" "assert_eq increments passed counter"
}

test_assert_contains_works() {
  local haystack="The quick brown fox"

  # Reset to avoid double-counting
  local old_passed=$TESTS_PASSED

  assert_contains "$haystack" "quick" "Contains quick" >/dev/null
  assert_contains "$haystack" "fox" "Contains fox" >/dev/null

  assert_true "$( [ $TESTS_PASSED -ge $((old_passed + 2)) ] && echo true )" "assert_contains works"
}

test_assert_json_field_works() {
  # Create temp JSON file
  local tmp_file=$(mktemp)
  echo '{"name": "test", "value": 42}' > "$tmp_file"

  assert_json_field "$tmp_file" ".name" "test" "JSON field extraction works"
  assert_json_field "$tmp_file" ".value" "42" "JSON numeric field works"

  rm -f "$tmp_file"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

run_test "jq available" test_jq_available
run_test "Bash version sufficient" test_bash_version
run_test "Scripts directory structure" test_scripts_directory_structure
run_test "Lib files exist" test_lib_files_exist
run_test "Core scripts exist" test_core_scripts_exist
run_test "Loops have required files" test_loops_have_required_files
run_test "assert_eq works" test_assert_eq_works
run_test "assert_contains works" test_assert_contains_works
run_test "assert_json_field works" test_assert_json_field_works
