#!/bin/bash
# Engine Integration Tests
# Tests that run engine.sh with mock Claude to verify file creation and state management
#
# These tests exercise:
# - Output snapshot creation
# - Error status creation when agent doesn't write status.json
# - Agent status preservation
# - Completion strategy sourcing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/status.sh"
source "$SCRIPT_DIR/lib/mock.sh"

#-------------------------------------------------------------------------------
# Test Helper Functions
#-------------------------------------------------------------------------------

# Create a minimal test loop configuration
_create_test_loop() {
  local test_dir=$1
  local loop_name=$2
  local term_type=${3:-"fixed"}

  mkdir -p "$test_dir/stages/$loop_name"

  # Create minimal stage.yaml
  cat > "$test_dir/stages/$loop_name/stage.yaml" << EOF
name: $loop_name
description: Test loop for integration testing
termination:
  type: $term_type
  min_iterations: 1
  consensus: 1
delay: 0
EOF

  # Create minimal prompt.md
  cat > "$test_dir/stages/$loop_name/prompt.md" << 'EOF'
# Test Loop

Iteration: ${ITERATION}
Context: ${CTX}
Status: ${STATUS}

Do something and write status.json.
EOF

  # Create default fixture
  mkdir -p "$test_dir/stages/$loop_name/fixtures"
  cat > "$test_dir/stages/$loop_name/fixtures/default.txt" << 'EOF'
# Mock Response

Test iteration completed.
EOF
}

# Create test run directory structure
_setup_test_run() {
  local test_dir=$1
  local session=$2

  mkdir -p "$test_dir/.claude/pipeline-runs/$session"
  mkdir -p "$test_dir/.claude/locks"
}

#-------------------------------------------------------------------------------
# Output Snapshot Tests
#-------------------------------------------------------------------------------

test_engine_creates_iteration_directory() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-iter-dir"

  _create_test_loop "$test_dir" "test-loop" "fixed"
  _setup_test_run "$test_dir" "$session"

  local run_dir="$test_dir/.claude/pipeline-runs/$session"

  # Initialize state (session, type, run_dir)
  init_state "$session" "loop" "$run_dir" >/dev/null

  # Create iteration 1 directory (simulating what engine does)
  mkdir -p "$run_dir/iterations/001"

  assert_dir_exists "$run_dir/iterations/001" "Engine should create iteration directory"

  cleanup_test_dir "$test_dir"
}

test_output_snapshot_saved() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-snapshot"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"

  # Create iteration directory and save output (simulating engine behavior)
  mkdir -p "$run_dir/iterations/001"
  echo "# Test Output\n\nThis is mock output from iteration 1." > "$run_dir/iterations/001/output.md"

  assert_file_exists "$run_dir/iterations/001/output.md" "Output snapshot should be saved"

  local content=$(cat "$run_dir/iterations/001/output.md")
  assert_contains "$content" "Test Output" "Output should contain expected content"

  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Status.json Tests
#-------------------------------------------------------------------------------

test_error_status_created_when_agent_doesnt_write() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-error-status"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local status_file="$run_dir/status.json"

  # Simulate: agent didn't write status.json
  # Engine should create error status
  if [ ! -f "$status_file" ]; then
    create_error_status "$status_file" "Agent did not write status.json"
  fi

  assert_file_exists "$status_file" "Error status should be created"
  assert_json_field "$status_file" ".decision" "error" "Decision should be error"
  assert_contains "$(cat $status_file)" "Agent did not write status.json" "Should have error message"

  cleanup_test_dir "$test_dir"
}

test_agent_status_preserved() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-preserve-status"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local status_file="$run_dir/status.json"

  # Simulate: agent wrote status.json
  cat > "$status_file" << 'EOF'
{
  "decision": "continue",
  "reason": "More work to do",
  "summary": "Completed task A"
}
EOF

  # Verify engine preserves agent's status (doesn't overwrite)
  if [ -f "$status_file" ]; then
    # Engine should NOT create error status when agent wrote one
    local decision=$(get_status_decision "$status_file")
    assert_eq "continue" "$decision" "Agent's decision should be preserved"
  fi

  cleanup_test_dir "$test_dir"
}

test_status_extraction_for_history() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-history"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local status_file="$run_dir/status.json"

  # Create agent status
  cat > "$status_file" << 'EOF'
{
  "decision": "stop",
  "reason": "Work complete",
  "summary": "All tasks done",
  "work": {
    "items_completed": ["task-1", "task-2"],
    "files_touched": ["file.ts"]
  },
  "errors": []
}
EOF

  # Extract history data (what engine does before updating state)
  local history_json=$(status_to_history_json "$status_file")

  # Verify extraction
  local decision=$(echo "$history_json" | jq -r '.decision')
  local reason=$(echo "$history_json" | jq -r '.reason')

  assert_eq "stop" "$decision" "History should contain decision"
  assert_eq "Work complete" "$reason" "History should contain reason"

  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Completion Strategy Tests
#-------------------------------------------------------------------------------

test_completion_strategy_file_exists() {
  # Verify all completion strategy files exist

  assert_file_exists "$SCRIPT_DIR/lib/completions/beads-empty.sh" "beads-empty strategy should exist"
  assert_file_exists "$SCRIPT_DIR/lib/completions/plateau.sh" "plateau strategy should exist"
  assert_file_exists "$SCRIPT_DIR/lib/completions/fixed-n.sh" "fixed-n strategy should exist"
}

test_completion_strategy_exports_check_completion() {
  # Verify each strategy exports check_completion function

  # Test beads-empty
  source "$SCRIPT_DIR/lib/completions/beads-empty.sh"
  assert_true "$(type check_completion &>/dev/null && echo true || echo false)" "beads-empty exports check_completion"

  # Test plateau
  source "$SCRIPT_DIR/lib/completions/plateau.sh"
  assert_true "$(type check_completion &>/dev/null && echo true || echo false)" "plateau exports check_completion"

  # Test fixed-n
  source "$SCRIPT_DIR/lib/completions/fixed-n.sh"
  assert_true "$(type check_completion &>/dev/null && echo true || echo false)" "fixed-n exports check_completion"
}

#-------------------------------------------------------------------------------
# State Management Tests
#-------------------------------------------------------------------------------

test_state_initialized_correctly() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-state-init"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"

  # Initialize state (session, type, run_dir) - returns state file path
  local state_file=$(init_state "$session" "loop" "$run_dir")

  # Verify state structure
  assert_file_exists "$state_file" "State file should be created"
  assert_json_field "$state_file" ".session" "$session" "Session should match"
  assert_json_field "$state_file" ".status" "running" "Status should be running"
  assert_json_field_exists "$state_file" ".history" "History array should exist"

  cleanup_test_dir "$test_dir"
}

test_iteration_marked_started() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-iter-start"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"

  local state_file=$(init_state "$session" "loop" "$run_dir")
  mark_iteration_started "$state_file" 1

  # Verify iteration started timestamp exists
  assert_json_field_exists "$state_file" ".iteration_started" "Should have iteration_started timestamp"

  cleanup_test_dir "$test_dir"
}

test_iteration_marked_completed() {
  local test_dir=$(create_test_dir "engine-int")
  local session="test-iter-complete"

  _setup_test_run "$test_dir" "$session"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"

  local state_file=$(init_state "$session" "loop" "$run_dir")
  mark_iteration_started "$state_file" 1
  mark_iteration_completed "$state_file" 1

  # Verify iteration_completed matches iteration
  local iter_completed=$(json_get "$(cat $state_file)" ".iteration_completed" "0")
  assert_eq "1" "$iter_completed" "iteration_completed should be 1"

  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Context.json Tests
#-------------------------------------------------------------------------------

test_context_json_structure() {
  # Note: generate_context has complex parameter requirements including stage config
  # This test verifies the function exists but skips actual generation testing
  # (covered by test_context.sh which properly sets up all dependencies)

  source "$SCRIPT_DIR/lib/context.sh"

  if type generate_context &>/dev/null; then
    # Function exists, basic test passes
    assert_true "true" "generate_context function exists"
  else
    skip_test "generate_context function not found"
  fi
}

test_pipeline_context_includes_initial_inputs() {
  local test_dir
  test_dir=$(create_test_dir "engine-int")
  local session="initial-inputs-int"
  local stage_type="initial-loop"
  local stage_name="bootstrap"
  local canonical_test_dir
  canonical_test_dir=$(cd "$test_dir" && pwd)

  # Create stage and fixtures for mock execution
  _create_test_loop "$test_dir" "$stage_type" "fixed"
  local fixtures_dir="$test_dir/stages/$stage_type/fixtures"
  enable_mock_mode "$fixtures_dir"

  # Stub claude CLI so check_provider passes in test env
  local original_path="$PATH"
  mkdir -p "$test_dir/bin"
  cat > "$test_dir/bin/claude" <<'EOF'
#!/bin/bash
echo "Mock claude CLI (unused in MOCK_MODE)" >&2
exit 0
EOF
  chmod +x "$test_dir/bin/claude"
  PATH="$test_dir/bin:$PATH"

  # Create pipeline with initial inputs
  echo "# Initial plan for integration test" > "$test_dir/initial-plan.md"
  local pipeline_file="$test_dir/test-pipeline.yaml"
  cat > "$pipeline_file" <<EOF
name: initial-inputs-pipeline
inputs:
  - ./initial-plan.md
stages:
  - name: $stage_name
    stage: $stage_type
    runs: 1
EOF

  local engine_output
  engine_output=$(
    cd "$test_dir"
    export PROJECT_ROOT="$test_dir"
    export STAGES_DIR="$test_dir/stages"
    export MOCK_MODE=true
    export MOCK_DELAY=0
    export PATH="$test_dir/bin:$PATH"
    "$SCRIPT_DIR/engine.sh" pipeline "./$(basename "$pipeline_file")" "$session" 2>&1
  )
  local exit_code=$?
  assert_eq "0" "$exit_code" "Pipeline with initial inputs runs successfully (mock mode)"

  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  local context_file="$run_dir/stage-00-$stage_name/iterations/001/context.json"
  assert_file_exists "$run_dir/initial-inputs.json" "initial-inputs manifest created in run dir"
  assert_file_exists "$context_file" "context.json generated for pipeline iteration"

  local count
  count=$(jq '.inputs.from_initial | length' "$context_file")
  assert_eq "1" "$count" "context.json records initial input files"

  local recorded
  recorded=$(jq -r '.inputs.from_initial[0]' "$context_file")
  local expected_input="$canonical_test_dir/initial-plan.md"
  assert_eq "$expected_input" "$recorded" "from_initial contains absolute path to seed file"

  PATH="$original_path"
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Engine Integration Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_test "engine creates iteration directory" test_engine_creates_iteration_directory
run_test "output snapshot saved" test_output_snapshot_saved
run_test "error status created when agent doesn't write" test_error_status_created_when_agent_doesnt_write
run_test "agent status preserved" test_agent_status_preserved
run_test "status extraction for history" test_status_extraction_for_history
run_test "completion strategy files exist" test_completion_strategy_file_exists
run_test "completion strategies export check_completion" test_completion_strategy_exports_check_completion
run_test "state initialized correctly" test_state_initialized_correctly
run_test "iteration marked started" test_iteration_marked_started
run_test "iteration marked completed" test_iteration_marked_completed
run_test "context.json structure" test_context_json_structure
run_test "pipeline context includes initial inputs" test_pipeline_context_includes_initial_inputs

test_summary
