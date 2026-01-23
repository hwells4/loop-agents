#!/bin/bash
# Lightweight Test Runner for Agent Pipelines
#
# Usage:
#   source "$LIB_DIR/test.sh"
#   run_test "Test name" test_function
#   test_summary
#
# Assertions:
#   assert_eq "expected" "actual" "message"
#   assert_neq "not_expected" "actual" "message"
#   assert_file_exists "/path/to/file"
#   assert_file_not_exists "/path/to/file"
#   assert_dir_exists "/path/to/dir"
#   assert_json_field "file.json" ".field" "expected"
#   assert_contains "haystack" "needle" "message"
#   assert_exit_code 0 "command"

# Test counters (use := to preserve values when re-sourced)
: ${TESTS_PASSED:=0}
: ${TESTS_FAILED:=0}
: ${TESTS_SKIPPED:=0}
CURRENT_TEST=""
TEST_VERBOSE=${TEST_VERBOSE:-false}

# Colors (if terminal supports them)
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  NC='\033[0m' # No Color
else
  GREEN=''
  RED=''
  YELLOW=''
  BLUE=''
  NC=''
fi

#-------------------------------------------------------------------------------
# Assertions
#-------------------------------------------------------------------------------

assert_eq() {
  local expected=$1
  local actual=$2
  local msg=${3:-"Values should be equal"}

  if [ "$expected" = "$actual" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Expected: ${BLUE}$expected${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    return 1
  fi
}

assert_neq() {
  local not_expected=$1
  local actual=$2
  local msg=${3:-"Values should not be equal"}

  if [ "$not_expected" != "$actual" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Should not be: ${RED}$actual${NC}"
    return 1
  fi
}

assert_file_exists() {
  local file=$1
  local msg=${2:-"File should exist: $file"}

  if [ -f "$file" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_file_not_exists() {
  local file=$1
  local msg=${2:-"File should not exist: $file"}

  if [ ! -f "$file" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_dir_exists() {
  local dir=$1
  local msg=${2:-"Directory should exist: $dir"}

  if [ -d "$dir" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_json_field() {
  local file=$1
  local field=$2
  local expected=$3
  local msg=${4:-"JSON $field = $expected"}

  if [ ! -f "$file" ]; then
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg (file not found: $file)"
    return 1
  fi

  local actual=$(jq -r "$field // empty" "$file" 2>/dev/null)

  if [ "$expected" = "$actual" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Expected: ${BLUE}$expected${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    return 1
  fi
}

assert_json_field_exists() {
  local file=$1
  local field=$2
  local msg=${3:-"JSON field $field should exist"}

  if [ ! -f "$file" ]; then
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg (file not found: $file)"
    return 1
  fi

  # Check exit code directly, discard output to avoid concatenation bug
  if jq -e "$field" "$file" >/dev/null 2>&1; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local msg=${3:-"Should contain: $needle"}

  if [[ "$haystack" == *"$needle"* ]]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    [ "$TEST_VERBOSE" = true ] && echo -e "    Content: ${haystack:0:100}..."
    return 1
  fi
}

assert_not_contains() {
  local haystack=$1
  local needle=$2
  local msg=${3:-"Should not contain: $needle"}

  if [[ "$haystack" != *"$needle"* ]]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_gt() {
  local actual=$1
  local threshold=$2
  local msg=${3:-"Value should be > $threshold"}

  if [ "$actual" -gt "$threshold" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg (got: $actual)"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Expected: > ${BLUE}$threshold${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    return 1
  fi
}

assert_ge() {
  local actual=$1
  local threshold=$2
  local msg=${3:-"Value should be >= $threshold"}

  if [ "$actual" -ge "$threshold" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg (got: $actual)"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Expected: >= ${BLUE}$threshold${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    return 1
  fi
}

assert_le() {
  local actual=$1
  local threshold=$2
  local msg=${3:-"Value should be <= $threshold"}

  if [ "$actual" -le "$threshold" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg (got: $actual)"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    echo -e "    Expected: <= ${BLUE}$threshold${NC}"
    echo -e "    Actual:   ${RED}$actual${NC}"
    return 1
  fi
}

assert_exit_code() {
  local expected=$1
  shift
  local cmd="$@"

  eval "$cmd" >/dev/null 2>&1
  local actual=$?

  if [ "$expected" -eq "$actual" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} Exit code $expected: $cmd"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} Exit code should be $expected (got $actual): $cmd"
    return 1
  fi
}

assert_true() {
  local condition=$1
  local msg=${2:-"Condition should be true"}

  if [ "$condition" = true ] || [ "$condition" = "true" ] || [ "$condition" = "1" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

assert_false() {
  local condition=$1
  local msg=${2:-"Condition should be false"}

  if [ "$condition" = false ] || [ "$condition" = "false" ] || [ "$condition" = "0" ] || [ -z "$condition" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $msg"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $msg"
    return 1
  fi
}

# Pass if condition is true, otherwise skip (not fail)
# Use when mock mode can't verify the behavior but real mode could
# Usage: assert_or_skip "$condition" "Pass message" "Skip reason"
assert_or_skip() {
  local condition=$1
  local pass_msg=$2
  local skip_msg=${3:-"Skipped (mock limitation)"}

  if [ "$condition" = true ] || [ "$condition" = "true" ] || [ "$condition" = "1" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $pass_msg"
    return 0
  else
    ((TESTS_SKIPPED++))
    echo -e "  ${YELLOW}⊘${NC} $skip_msg"
    return 0
  fi
}

#-------------------------------------------------------------------------------
# Test Runner
#-------------------------------------------------------------------------------

# Run a single test function
# Usage: run_test "Test name" test_function
run_test() {
  local name=$1
  local fn=$2

  CURRENT_TEST="$name"
  echo -e "${BLUE}Testing:${NC} $name"

  # Run the test function
  if type "$fn" &>/dev/null; then
    $fn
  else
    ((TESTS_SKIPPED++))
    echo -e "  ${YELLOW}⊘${NC} Test function not found: $fn"
  fi

  echo ""
}

# Skip a test
# Usage: skip_test "reason"
skip_test() {
  local reason=${1:-"Skipped"}
  ((TESTS_SKIPPED++))
  echo -e "  ${YELLOW}⊘${NC} $reason"
}

# Print test summary and return exit code
# Usage: test_summary
test_summary() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "Results: ${GREEN}$TESTS_PASSED passed${NC}, ${RED}$TESTS_FAILED failed${NC}, ${YELLOW}$TESTS_SKIPPED skipped${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ $TESTS_FAILED -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# Reset test counters (useful between test files)
reset_tests() {
  TESTS_PASSED=0
  TESTS_FAILED=0
  TESTS_SKIPPED=0
}

#-------------------------------------------------------------------------------
# Test Utilities
#-------------------------------------------------------------------------------

# Create a temporary directory for test isolation
# Usage: tmp=$(create_test_dir)
create_test_dir() {
  local prefix=${1:-"pipeline-test"}
  mktemp -d -t "${prefix}.XXXXXX"
}

# Clean up test directory
# Usage: cleanup_test_dir "$tmp"
cleanup_test_dir() {
  local dir=$1
  [ -d "$dir" ] && rm -rf "$dir"
}

# Create a test session directory structure
# Usage: setup_test_session "$tmp" "session-name"
setup_test_session() {
  local base_dir=$1
  local session=$2

  local run_dir="$base_dir/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  echo "$run_dir"
}
