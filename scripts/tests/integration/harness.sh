#!/bin/bash
# Integration Test Harness for Agent Pipelines
#
# Provides mock infrastructure for end-to-end testing of the pipeline engine
# without making actual Claude API calls.
#
# Usage:
#   source "$SCRIPT_DIR/integration/harness.sh"
#   setup_integration_test "$test_dir" "continue-3"
#   run_mock_engine "$test_dir" "test-session" 3
#   teardown_integration_test "$test_dir"

# Note: Not using set -e so tests continue and report all failures

# Determine paths - handle both bash and zsh
# First, find the project root by looking for CLAUDE.md
_find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/CLAUDE.md" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: assume we're in the project directory
  echo "$PWD"
}

PROJECT_ROOT_DIR="$(_find_project_root)"
HARNESS_DIR="$PROJECT_ROOT_DIR/scripts/tests/integration"
LIB_DIR="$PROJECT_ROOT_DIR/scripts/lib"
ENGINE_SCRIPT="$PROJECT_ROOT_DIR/scripts/engine.sh"
FIXTURES_BASE="$PROJECT_ROOT_DIR/scripts/tests/fixtures/integration"

# Source dependencies
source "$LIB_DIR/test.sh"
source "$LIB_DIR/mock.sh"

#-------------------------------------------------------------------------------
# Test Environment Setup
#-------------------------------------------------------------------------------

# Setup integration test environment
# Usage: setup_integration_test "$test_dir" "fixture_name"
setup_integration_test() {
  local test_dir=$1
  local fixture_name=${2:-"continue-3"}

  # Create directory structure
  mkdir -p "$test_dir/.claude/pipeline-runs"
  mkdir -p "$test_dir/.claude/locks"
  mkdir -p "$test_dir/stages"

  # Set environment variables for test isolation
  export PROJECT_ROOT="$test_dir"
  export STAGES_DIR="$test_dir/stages"

  # Enable mock mode with fixtures
  local fixture_dir="$FIXTURES_BASE/$fixture_name"
  if [ -d "$fixture_dir" ]; then
    enable_mock_mode "$fixture_dir"
  else
    echo "Warning: Fixture directory not found: $fixture_dir" >&2
    enable_mock_mode "$FIXTURES_BASE/continue-3"
  fi

  # Disable delays for faster tests
  export MOCK_DELAY=0

  # Copy stage configuration to test directory
  _copy_test_stage "$test_dir" "$fixture_name"

  echo "$test_dir"
}

# Teardown integration test environment
# Usage: teardown_integration_test "$test_dir"
teardown_integration_test() {
  local test_dir=$1

  # Disable mock mode
  disable_mock_mode

  # Clear environment
  unset PROJECT_ROOT
  unset STAGES_DIR
  unset MOCK_DELAY

  # Cleanup test directory
  [ -d "$test_dir" ] && rm -rf "$test_dir"
}

# Copy test stage to isolated test directory
_copy_test_stage() {
  local test_dir=$1
  local fixture_name=$2
  local fixture_dir="$FIXTURES_BASE/$fixture_name"

  if [ -f "$fixture_dir/stage.yaml" ]; then
    local stage_name="test-$fixture_name"
    mkdir -p "$test_dir/stages/$stage_name"
    cp "$fixture_dir/stage.yaml" "$test_dir/stages/$stage_name/"
    cp "$fixture_dir/prompt.md" "$test_dir/stages/$stage_name/" 2>/dev/null || true

    # Copy fixtures into stage
    mkdir -p "$test_dir/stages/$stage_name/fixtures"
    cp "$fixture_dir"/*.txt "$test_dir/stages/$stage_name/fixtures/" 2>/dev/null || true
    cp "$fixture_dir"/*.json "$test_dir/stages/$stage_name/fixtures/" 2>/dev/null || true
  fi
}

#-------------------------------------------------------------------------------
# Mock Engine Execution
#-------------------------------------------------------------------------------

# Run engine with mocked execution
# Usage: run_mock_engine "$test_dir" "$session" "$max_iterations" ["$stage_type"]
# Returns: exit code from engine
run_mock_engine() {
  local test_dir=$1
  local session=$2
  local max_iterations=${3:-3}
  local stage_type=${4:-"test-continue-3"}

  # Ensure mock mode is enabled
  export MOCK_MODE=true

  # Create a simple status writer for the mock
  _setup_status_writer "$test_dir"

  # Run the engine
  (
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline --single-stage "$stage_type" "$session" "$max_iterations" 2>&1
  )
  return $?
}

# Run multi-stage pipeline with mocked execution
# Usage: run_mock_pipeline "$test_dir" "$pipeline_file" "$session"
run_mock_pipeline() {
  local test_dir=$1
  local pipeline_file=$2
  local session=$3

  export MOCK_MODE=true

  (
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline "$pipeline_file" "$session" 2>&1
  )
  return $?
}

# Run multi-stage pipeline with resume flag
# Usage: run_mock_pipeline_resume "$test_dir" "$pipeline_file" "$session"
run_mock_pipeline_resume() {
  local test_dir=$1
  local pipeline_file=$2
  local session=$3

  export MOCK_MODE=true

  (
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline "$pipeline_file" "$session" --resume 2>&1
  )
  return $?
}

# Run engine with resume flag
# Usage: run_mock_engine_resume "$test_dir" "$session" "$max_iterations" ["$stage_type"]
run_mock_engine_resume() {
  local test_dir=$1
  local session=$2
  local max_iterations=${3:-3}
  local stage_type=${4:-"test-continue-3"}

  export MOCK_MODE=true

  (
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline --single-stage "$stage_type" "$session" "$max_iterations" --resume 2>&1
  )
  return $?
}

# Setup status writer that creates status.json from fixtures
_setup_status_writer() {
  local test_dir=$1

  # The status writing is handled by the mock fixtures
  # The engine will read status from the file the mock writes
  :
}

#-------------------------------------------------------------------------------
# State Helpers
#-------------------------------------------------------------------------------

# Get state file path for a session
# Usage: get_state_file "$test_dir" "$session"
get_state_file() {
  local test_dir=$1
  local session=$2
  echo "$test_dir/.claude/pipeline-runs/$session/state.json"
}

# Get run directory for a session
# Usage: get_run_dir "$test_dir" "$session"
get_run_dir() {
  local test_dir=$1
  local session=$2
  echo "$test_dir/.claude/pipeline-runs/$session"
}

# Create partial state for resume testing
# Usage: create_partial_state "$state_file" "$completed_iterations" ["$status"]
create_partial_state() {
  local state_file=$1
  local completed=$2
  local status=${3:-"failed"}
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$(dirname "$state_file")"

  # Build history array
  local history="[]"
  for i in $(seq 1 $completed); do
    history=$(echo "$history" | jq ". + [{\"iteration\": $i, \"decision\": \"continue\", \"reason\": \"mock\"}]")
  done

  cat > "$state_file" << EOF
{
  "session": "$(basename "$(dirname "$state_file")")",
  "type": "loop",
  "started_at": "$timestamp",
  "status": "$status",
  "iteration": $completed,
  "iteration_completed": $completed,
  "iteration_started": null,
  "history": $history
}
EOF
}

# Create multi-stage partial state for resume testing
# Usage: create_multi_stage_state "$state_file" "$current_stage" "$completed_iters"
create_multi_stage_state() {
  local state_file=$1
  local current_stage=$2
  local completed_iters=$3
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$(dirname "$state_file")"

  # Build stages array
  local stages="["
  for i in $(seq 0 $((current_stage - 1))); do
    [ "$i" -gt 0 ] && stages="$stages,"
    stages="$stages{\"name\": \"stage-$i\", \"status\": \"complete\", \"iteration_completed\": 2}"
  done
  stages="$stages,{\"name\": \"stage-$current_stage\", \"status\": \"running\", \"iteration_completed\": $completed_iters}"
  stages="$stages]"

  cat > "$state_file" << EOF
{
  "session": "$(basename "$(dirname "$state_file")")",
  "type": "pipeline",
  "started_at": "$timestamp",
  "status": "failed",
  "current_stage": $current_stage,
  "iteration": $completed_iters,
  "iteration_completed": $completed_iters,
  "iteration_started": null,
  "stages": $stages,
  "history": []
}
EOF
}

#-------------------------------------------------------------------------------
# Iteration Tracking
#-------------------------------------------------------------------------------

# Count iteration directories
# Usage: count_iterations "$run_dir"
count_iterations() {
  local run_dir=$1

  # Engine nests iterations under stage directories: stage-NN-{name}/iterations/
  # Find any iterations directory and count its contents
  local iter_dir=""
  for stage_dir in "$run_dir"/stage-*/iterations "$run_dir/iterations"; do
    if [ -d "$stage_dir" ]; then
      iter_dir="$stage_dir"
      break
    fi
  done

  if [ -n "$iter_dir" ] && [ -d "$iter_dir" ]; then
    ls -1 "$iter_dir" 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

# Check if specific iteration exists
# Usage: iteration_exists "$run_dir" "$iteration"
# Bug fix: loop-agents-o5t - engine uses stage-NN-name/iterations/ structure
iteration_exists() {
  local run_dir=$1
  local iteration=$2
  local iter_formatted=$(printf "%03d" "$iteration")

  # Engine nests iterations under stage directories: stage-NN-{name}/iterations/
  # Check all possible stage directories for this iteration
  for stage_dir in "$run_dir"/stage-*/iterations; do
    if [ -d "$stage_dir/$iter_formatted" ]; then
      return 0
    fi
  done

  # Fallback: check legacy flat structure
  [ -d "$run_dir/iterations/$iter_formatted" ]
}

#-------------------------------------------------------------------------------
# Log Capture
#-------------------------------------------------------------------------------

# Capture log output for assertions
INTEGRATION_LOG=""

# Run engine and capture output
# Usage: output=$(run_and_capture_log "$test_dir" "$session" "$max")
run_and_capture_log() {
  local test_dir=$1
  local session=$2
  local max_iterations=${3:-3}
  local stage_type=${4:-"test-continue-3"}

  export MOCK_MODE=true

  INTEGRATION_LOG=$(
    cd "$test_dir"
    "$ENGINE_SCRIPT" pipeline --single-stage "$stage_type" "$session" "$max_iterations" 2>&1
  )
  local exit_code=$?

  echo "$INTEGRATION_LOG"
  return $exit_code
}

# Assert log contains text
# Usage: assert_log_contains "Expected text"
assert_log_contains() {
  local expected=$1
  local msg=${2:-"Log should contain: $expected"}

  assert_contains "$INTEGRATION_LOG" "$expected" "$msg"
}

# Assert log does not contain text
# Usage: assert_log_not_contains "Unexpected text"
assert_log_not_contains() {
  local unexpected=$1
  local msg=${2:-"Log should not contain: $unexpected"}

  assert_not_contains "$INTEGRATION_LOG" "$unexpected" "$msg"
}

#-------------------------------------------------------------------------------
# Model Tracking
#-------------------------------------------------------------------------------

# Track which model was used (requires spy on execute_agent)
LAST_MODEL_USED=""

# Get the model that was used in execution
# This is set by the harness when spying on execute_agent
get_last_model_used() {
  echo "$LAST_MODEL_USED"
}

#-------------------------------------------------------------------------------
# Multi-Stage Helpers
#-------------------------------------------------------------------------------

# Setup multi-stage test environment
# Usage: setup_multi_stage_test "$test_dir" "multi-stage-3"
setup_multi_stage_test() {
  local test_dir=$1
  local fixture_name=${2:-"multi-stage-3"}

  # Basic setup
  setup_integration_test "$test_dir" "$fixture_name"

  local fixture_dir="$FIXTURES_BASE/$fixture_name"

  # Copy pipeline.yaml
  if [ -f "$fixture_dir/pipeline.yaml" ]; then
    mkdir -p "$test_dir/.claude/pipelines"
    cp "$fixture_dir/pipeline.yaml" "$test_dir/.claude/pipelines/"
  fi

  # Copy stage directories
  for stage_dir in "$fixture_dir"/stage-*; do
    if [ -d "$stage_dir" ]; then
      local stage_name=$(basename "$stage_dir")
      # Extract stage type from directory name (e.g., stage-00-plan -> test-plan)
      local stage_type="test-$(echo "$stage_name" | sed 's/stage-[0-9]*-//')"

      mkdir -p "$test_dir/stages/$stage_type/fixtures"
      cp "$stage_dir/stage.yaml" "$test_dir/stages/$stage_type/" 2>/dev/null || true
      cp "$stage_dir/prompt.md" "$test_dir/stages/$stage_type/" 2>/dev/null || true
      cp "$stage_dir"/*.txt "$test_dir/stages/$stage_type/fixtures/" 2>/dev/null || true
      cp "$stage_dir"/*.json "$test_dir/stages/$stage_type/fixtures/" 2>/dev/null || true
    fi
  done
}

#-------------------------------------------------------------------------------
# Fixture Switching
#-------------------------------------------------------------------------------

# Switch fixture set during test (for multi-stage or conditional behavior)
# Usage: switch_fixtures "plateau-consensus"
switch_fixtures() {
  local fixture_name=$1
  local fixture_dir="$FIXTURES_BASE/$fixture_name"

  if [ -d "$fixture_dir" ]; then
    enable_mock_mode "$fixture_dir"
  else
    echo "Warning: Fixture not found: $fixture_name" >&2
  fi
}

# Set specific iteration to use
# Usage: set_mock_iteration 2
set_mock_iteration() {
  local iteration=$1
  export MOCK_ITERATION=$iteration
}

#-------------------------------------------------------------------------------
# Crash Simulation
#-------------------------------------------------------------------------------

# Configure mock to fail at specific iteration
# Usage: set_crash_at_iteration 2
MOCK_CRASH_AT=""
set_crash_at_iteration() {
  export MOCK_CRASH_AT=$1
}

# Check if crash should be simulated (call from mock)
should_crash() {
  local iteration=${1:-$MOCK_ITERATION}
  [ -n "$MOCK_CRASH_AT" ] && [ "$iteration" -eq "$MOCK_CRASH_AT" ]
}

#-------------------------------------------------------------------------------
# Exports
#-------------------------------------------------------------------------------

export -f setup_integration_test
export -f teardown_integration_test
export -f run_mock_engine
export -f run_mock_pipeline
export -f run_mock_engine_resume
export -f get_state_file
export -f get_run_dir
export -f create_partial_state
export -f create_multi_stage_state
export -f count_iterations
export -f iteration_exists
export -f run_and_capture_log
export -f assert_log_contains
export -f assert_log_not_contains
export -f setup_multi_stage_test
export -f switch_fixtures
export -f set_mock_iteration
export -f set_crash_at_iteration
export -f should_crash
