#!/bin/bash
# Integration Tests: Engine Event Logging
#
# Tests that engine runs write events.jsonl entries for loops and pipelines.
#
# Usage: ./test_engine_events.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/harness.sh"
source "$LIB_DIR/events.sh"

echo "========================================"
echo "Integration Tests: Engine Events"
echo "========================================"
echo ""

# Reset test counters
reset_tests

#-------------------------------------------------------------------------------
# Dependency Stubs
#-------------------------------------------------------------------------------

_setup_yq_stub() {
  local test_dir=$1
  local bin_dir="$test_dir/bin"

  mkdir -p "$bin_dir"

  cat > "$bin_dir/yq" << 'EOF'
#!/bin/bash
if [ "$1" = "--version" ]; then
  echo "yq (https://github.com/mikefarah/yq/) version 4.30.8"
  exit 0
fi

if [ "$1" = "-o=json" ]; then
  shift
  python3 - "$1" << 'PY'
import json
import sys
import yaml

path = sys.argv[1] if len(sys.argv) > 1 else None
if not path:
    sys.exit(1)
with open(path, "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
print(json.dumps(data))
PY
  exit $?
fi

echo "Unsupported yq args: $*" >&2
exit 1
EOF

  chmod +x "$bin_dir/yq"

  echo "$bin_dir"
}

_with_yq_stub() {
  local test_dir=$1
  shift
  local original_path="$PATH"
  local bin_dir
  bin_dir=$(_setup_yq_stub "$test_dir")

  PATH="$bin_dir:$PATH"
  export PATH

  "$@"
  local status=$?

  PATH="$original_path"
  export PATH

  return $status
}

#-------------------------------------------------------------------------------
# Test: Loop sessions write expected event types
#-------------------------------------------------------------------------------
test_engine_events_loop_types() {
  local test_dir
  test_dir=$(create_test_dir "int-events-loop")
  setup_integration_test "$test_dir" "continue-3"

  local session="test-events-loop"
  _with_yq_stub "$test_dir" \
    run_mock_engine "$test_dir" "$session" 2 "test-continue-3" >/dev/null 2>&1 || true

  local run_dir
  run_dir=$(get_run_dir "$test_dir" "$session")
  local events_file="$run_dir/events.jsonl"

  assert_file_exists "$events_file" "events.jsonl created for loop session"

  local events_json
  events_json=$(read_events "$session")

  local event_count
  event_count=$(echo "$events_json" | jq 'length')
  assert_ge "$event_count" 1 "events.jsonl has entries"

  local session_start_count
  session_start_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "session_start")] | length')
  assert_gt "$session_start_count" 0 "session_start event recorded"

  local node_start_count
  node_start_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "node_start")] | length')
  assert_gt "$node_start_count" 0 "node_start event recorded"

  local iter_start_count
  iter_start_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "iteration_start")] | length')
  assert_eq "2" "$iter_start_count" "iteration_start events match iteration count"

  local iter_complete_count
  iter_complete_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "iteration_complete")] | length')
  assert_eq "2" "$iter_complete_count" "iteration_complete events match iteration count"

  local node_complete_count
  node_complete_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "node_complete")] | length')
  assert_gt "$node_complete_count" 0 "node_complete event recorded"

  local session_complete_count
  session_complete_count=$(echo "$events_json" | jq -r '[.[] | select(.type == "session_complete")] | length')
  assert_gt "$session_complete_count" 0 "session_complete event recorded"

  teardown_integration_test "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Iteration cursor includes stage index and iteration number
#-------------------------------------------------------------------------------
test_engine_events_loop_cursor() {
  local test_dir
  test_dir=$(create_test_dir "int-events-cursor")
  setup_integration_test "$test_dir" "continue-3"

  local session="test-events-cursor"
  _with_yq_stub "$test_dir" \
    run_mock_engine "$test_dir" "$session" 1 "test-continue-3" >/dev/null 2>&1 || true

  local events_json
  events_json=$(read_events "$session")

  local node_path
  node_path=$(echo "$events_json" | jq -r '[.[] | select(.type == "iteration_start")][0].cursor.node_path // empty')
  local iteration
  iteration=$(echo "$events_json" | jq -r '[.[] | select(.type == "iteration_start")][0].cursor.iteration // empty')
  local node_run
  node_run=$(echo "$events_json" | jq -r '[.[] | select(.type == "iteration_start")][0].cursor.node_run // empty')

  assert_eq "0" "$node_path" "iteration_start cursor node_path tracks stage index"
  assert_eq "1" "$iteration" "iteration_start cursor iteration tracks iteration"
  assert_eq "1" "$node_run" "iteration_start cursor node_run tracks run index"

  teardown_integration_test "$test_dir"
}

#-------------------------------------------------------------------------------
# Test: Pipeline sessions record pipeline metadata in session_start
#-------------------------------------------------------------------------------
test_engine_events_pipeline_session_start() {
  local test_dir
  test_dir=$(create_test_dir "int-events-pipeline")
  setup_multi_stage_test "$test_dir" "multi-stage-3"

  local session="test-events-pipeline"
  _with_yq_stub "$test_dir" \
    run_mock_pipeline "$test_dir" "$test_dir/.claude/pipelines/pipeline.yaml" "$session" >/dev/null 2>&1 || true

  local events_json
  events_json=$(read_events "$session")

  local mode
  mode=$(echo "$events_json" | jq -r '[.[] | select(.type == "session_start")][0].data.mode // empty')
  local pipeline_name
  pipeline_name=$(echo "$events_json" | jq -r '[.[] | select(.type == "session_start")][0].data.pipeline // empty')

  assert_eq "pipeline" "$mode" "session_start records pipeline mode"
  assert_eq "test-multi-stage" "$pipeline_name" "session_start records pipeline name"

  teardown_integration_test "$test_dir"
}

#-------------------------------------------------------------------------------
# Run All Tests
#-------------------------------------------------------------------------------

run_test "Loop event types recorded" test_engine_events_loop_types
run_test "Loop event cursor tracks iteration" test_engine_events_loop_cursor
run_test "Pipeline session_start metadata recorded" test_engine_events_pipeline_session_start

test_summary
