#!/bin/bash
# Test Runner for Agent Pipelines
#
# Runs all tests or specific test categories.
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh --ci         # Run all tests (CI alias)
#   ./run_tests.sh unit         # Run unit tests only
#   ./run_tests.sh integration  # Run integration tests only
#   ./run_tests.sh contract     # Run contract tests only
#   ./run_tests.sh bug          # Run bug regression tests only

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
if [ -t 1 ]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  GREEN=''
  RED=''
  BLUE=''
  NC=''
fi

# Counters
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Category to run
CATEGORY=${1:-"all"}

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   Agent Pipelines Test Runner${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#-------------------------------------------------------------------------------
# Run Unit Tests
#-------------------------------------------------------------------------------
run_unit_tests() {
  echo -e "${BLUE}Running Unit Tests...${NC}"
  echo ""

  local count=0
  for test_file in "$SCRIPT_DIR"/test_*.sh; do
    # Skip integration and contract tests
    if [[ "$test_file" == *"integration"* ]] || [[ "$test_file" == *"contract"* ]]; then
      continue
    fi

    if [ -f "$test_file" ]; then
      echo -e "${BLUE}  Running: $(basename "$test_file")${NC}"
      if bash "$test_file"; then
        count=$((count + 1))
      fi
      echo ""
    fi
  done

  echo -e "Unit tests run: $count files"
  echo ""
}

#-------------------------------------------------------------------------------
# Run Contract Tests
#-------------------------------------------------------------------------------
run_contract_tests() {
  echo -e "${BLUE}Running Contract Tests...${NC}"
  echo ""

  local count=0
  for test_file in "$SCRIPT_DIR"/test_*contract*.sh "$SCRIPT_DIR"/test_*parity*.sh; do
    if [ -f "$test_file" ]; then
      echo -e "${BLUE}  Running: $(basename "$test_file")${NC}"
      if bash "$test_file"; then
        count=$((count + 1))
      fi
      echo ""
    fi
  done

  echo -e "Contract tests run: $count files"
  echo ""
}

#-------------------------------------------------------------------------------
# Run Integration Tests
#-------------------------------------------------------------------------------
run_integration_tests() {
  echo -e "${BLUE}Running Integration Tests...${NC}"
  echo ""

  local integration_dir="$SCRIPT_DIR/integration"
  if [ ! -d "$integration_dir" ]; then
    echo "  No integration tests directory found"
    return
  fi

  local count=0
  for test_file in "$integration_dir"/test_*.sh; do
    if [ -f "$test_file" ]; then
      echo -e "${BLUE}  Running: $(basename "$test_file")${NC}"
      if bash "$test_file"; then
        count=$((count + 1))
      fi
      echo ""
    fi
  done

  echo -e "Integration tests run: $count files"
  echo ""
}

#-------------------------------------------------------------------------------
# Run Bug Regression Tests Only
#-------------------------------------------------------------------------------
run_bug_tests() {
  echo -e "${BLUE}Running Bug Regression Tests...${NC}"
  echo ""

  local test_file="$SCRIPT_DIR/integration/test_bug_regression.sh"
  if [ -f "$test_file" ]; then
    bash "$test_file"
  else
    echo "  Bug regression test file not found"
  fi
  echo ""
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

case "$CATEGORY" in
  --ci|ci)
    run_unit_tests
    run_contract_tests
    run_integration_tests
    ;;
  all)
    run_unit_tests
    run_contract_tests
    run_integration_tests
    ;;
  unit)
    run_unit_tests
    ;;
  contract)
    run_contract_tests
    ;;
  integration)
    run_integration_tests
    ;;
  bug|bugs|regression)
    run_bug_tests
    ;;
  *)
    echo "Unknown category: $CATEGORY"
    echo "Usage: $0 [all|unit|contract|integration|bug]"
    exit 1
    ;;
esac

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   Test Run Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
