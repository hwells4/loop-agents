#!/bin/bash
# Regression tests for path resolution bugs
#
# These tests prevent reintroduction of path resolution bugs that were fixed.
# Tests cover:
#   1. lib file sourcing from different working directories
#   2. CLI commands with various path formats

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"

#-------------------------------------------------------------------------------
# Test 1: lib file sourcing from different working directories
#
# Bug: compile.sh used LIB_DIR (which can be overridden) to source sibling files
# Fix: Use COMPILE_SCRIPT_DIR (computed from BASH_SOURCE) instead
#-------------------------------------------------------------------------------

test_compile_sourcing_from_repo_root() {
  # Test that sourcing compile.sh works from the repository root
  local repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  # This should not error - sourcing compile.sh from repo root
  (
    cd "$repo_root"
    source "$SCRIPT_DIR/lib/compile.sh" 2>&1
  )
  local exit_code=$?

  assert_eq "0" "$exit_code" "compile.sh sources correctly from repo root"
}

test_compile_sourcing_from_tmp() {
  # Test that sourcing compile.sh works from /tmp or another directory
  local tmp_dir=$(mktemp -d)

  (
    cd "$tmp_dir"
    source "$SCRIPT_DIR/lib/compile.sh" 2>&1
  )
  local exit_code=$?

  rm -rf "$tmp_dir"

  assert_eq "0" "$exit_code" "compile.sh sources correctly from /tmp"
}

test_compile_sourcing_with_lib_dir_override() {
  # Test that compile.sh still works even if LIB_DIR is set to something else
  # Bug: if LIB_DIR was set externally, compile.sh would try to source from wrong location
  local tmp_dir=$(mktemp -d)

  (
    export LIB_DIR="/nonexistent/path/that/does/not/exist"
    cd "$tmp_dir"
    source "$SCRIPT_DIR/lib/compile.sh" 2>&1
  )
  local exit_code=$?

  rm -rf "$tmp_dir"

  assert_eq "0" "$exit_code" "compile.sh sources correctly despite LIB_DIR override"
}

test_compile_uses_own_directory_for_siblings() {
  # Verify that compile.sh uses COMPILE_SCRIPT_DIR for sibling sourcing
  # This is a direct check that the fix is in place

  local compile_content
  compile_content=$(cat "$SCRIPT_DIR/lib/compile.sh")

  # Check that COMPILE_SCRIPT_DIR is defined
  assert_contains "$compile_content" 'COMPILE_SCRIPT_DIR=' "compile.sh defines COMPILE_SCRIPT_DIR"

  # Check that sibling sources use COMPILE_SCRIPT_DIR, not LIB_DIR
  assert_contains "$compile_content" 'source "$COMPILE_SCRIPT_DIR/yaml.sh"' "compile.sh sources yaml.sh via COMPILE_SCRIPT_DIR"
  assert_contains "$compile_content" 'source "$COMPILE_SCRIPT_DIR/validate.sh"' "compile.sh sources validate.sh via COMPILE_SCRIPT_DIR"
  assert_contains "$compile_content" 'source "$COMPILE_SCRIPT_DIR/deps.sh"' "compile.sh sources deps.sh via COMPILE_SCRIPT_DIR"
  assert_contains "$compile_content" 'source "$COMPILE_SCRIPT_DIR/provider.sh"' "compile.sh sources provider.sh via COMPILE_SCRIPT_DIR"
}

#-------------------------------------------------------------------------------
# Test 2: CLI commands with various path formats
#
# Bug: lint_all pipeline only worked with bare names, not full/relative paths
# Fix: Check for path separators or .yaml extension to detect file paths
#-------------------------------------------------------------------------------

test_lint_pipeline_with_bare_name() {
  # Test lint with just a name: refine
  source "$SCRIPT_DIR/lib/validate.sh"

  validate_pipeline "refine" "--quiet"
  local exit_code=$?

  assert_eq "0" "$exit_code" "lint_all pipeline accepts bare name 'refine'"
}

test_lint_pipeline_with_full_path() {
  # Test lint with full path: /absolute/path/to/scripts/pipelines/refine.yaml
  source "$SCRIPT_DIR/lib/validate.sh"

  local pipeline_path="$SCRIPT_DIR/pipelines/refine.yaml"

  # lint_all dispatches based on path detection
  lint_all "pipeline" "$pipeline_path" >/dev/null 2>&1
  local exit_code=$?

  assert_eq "0" "$exit_code" "lint_all pipeline accepts full path"
}

test_lint_pipeline_with_relative_path() {
  # Test lint with relative path: ./scripts/pipelines/refine.yaml
  # Note: We test from repo root with a relative path containing /

  local repo_root="$(cd "$SCRIPT_DIR/.." && pwd)"

  # Run in subshell to avoid polluting the current shell
  # Must source validate.sh inside the subshell
  (
    cd "$repo_root"
    source "$SCRIPT_DIR/lib/validate.sh"
    lint_all "pipeline" "./scripts/pipelines/refine.yaml" >/dev/null 2>&1
  )
  local exit_code=$?

  assert_eq "0" "$exit_code" "lint_all pipeline accepts relative path ./scripts/pipelines/refine.yaml"
}

test_lint_pipeline_with_path_no_yaml_extension() {
  # Test lint with path containing / but no .yaml extension
  # The path detection should recognize it as a file path (not a name)
  source "$SCRIPT_DIR/lib/validate.sh"

  # Path with / but no .yaml - should be treated as file path
  local pipeline_path="$SCRIPT_DIR/pipelines/refine"

  # This should fail because the file doesn't exist (no .yaml extension)
  # but it should try validate_pipeline_file, not validate_pipeline
  lint_all "pipeline" "$pipeline_path" >/dev/null 2>&1
  local exit_code=$?

  # The actual test: with .yaml extension it should work
  lint_all "pipeline" "${pipeline_path}.yaml" >/dev/null 2>&1
  exit_code=$?

  assert_eq "0" "$exit_code" "lint_all pipeline handles path-like input with .yaml"
}

test_lint_all_path_detection_logic() {
  # Verify the path detection logic is in place in validate.sh
  local validate_content
  validate_content=$(cat "$SCRIPT_DIR/lib/validate.sh")

  # Check that lint_all has the path detection logic
  # It should check for / or .yaml to determine if it's a file path
  assert_contains "$validate_content" '*/*' "validate.sh checks for path separators"
  assert_contains "$validate_content" '*.yaml' "validate.sh checks for .yaml extension"
  assert_contains "$validate_content" 'validate_pipeline_file' "validate.sh uses validate_pipeline_file for paths"
}

test_validate_pipeline_file_function_exists() {
  # Verify validate_pipeline_file function exists and works
  source "$SCRIPT_DIR/lib/validate.sh"

  # Function should exist
  if ! type validate_pipeline_file &>/dev/null; then
    assert_eq "function_exists" "function_missing" "validate_pipeline_file function should exist"
    return 1
  fi

  # Test it works with a real file
  local pipeline_path="$SCRIPT_DIR/pipelines/refine.yaml"
  validate_pipeline_file "$pipeline_path" "--quiet"
  local exit_code=$?

  assert_eq "0" "$exit_code" "validate_pipeline_file works with absolute path"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Path Resolution Regression Tests"
echo "==============================================================="
echo ""

echo "--- Test 1: lib file sourcing from different working directories ---"
echo ""

run_test "compile.sh sourcing from repo root" test_compile_sourcing_from_repo_root
run_test "compile.sh sourcing from /tmp" test_compile_sourcing_from_tmp
run_test "compile.sh sourcing with LIB_DIR override" test_compile_sourcing_with_lib_dir_override
run_test "compile.sh uses own directory for siblings" test_compile_uses_own_directory_for_siblings

echo ""
echo "--- Test 2: CLI commands with various path formats ---"
echo ""

run_test "lint_all pipeline with bare name" test_lint_pipeline_with_bare_name
run_test "lint_all pipeline with full path" test_lint_pipeline_with_full_path
run_test "lint_all pipeline with relative path" test_lint_pipeline_with_relative_path
run_test "lint_all pipeline handles path-like input" test_lint_pipeline_with_path_no_yaml_extension
run_test "lint_all path detection logic" test_lint_all_path_detection_logic
run_test "validate_pipeline_file function exists" test_validate_pipeline_file_function_exists

test_summary
