#!/bin/bash
# Tests for parallel block event integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LIB_DIR="$SCRIPT_DIR/lib"

source "$LIB_DIR/test.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/events.sh"
source "$LIB_DIR/mock.sh"
source "$LIB_DIR/parallel.sh"

create_test_dir() {
  mktemp -d
}

cleanup_test_dir() {
  local dir=$1
  [ -d "$dir" ] && rm -rf "$dir"
}

setup_parallel_event_env() {
  local test_dir=$1

  export PROJECT_ROOT="$test_dir"
  export STAGES_DIR="$test_dir/stages"
  export MOCK_MODE=true
  export MOCK_FIXTURES_DIR="$test_dir/fixtures"
  export EVENT_SPINE_ENABLED="true"

  mkdir -p "$STAGES_DIR/improve-plan"
  cat > "$STAGES_DIR/improve-plan/stage.yaml" << 'EOF'
name: improve-plan
termination:
  type: fixed
  max: 1
EOF
  cat > "$STAGES_DIR/improve-plan/prompt.md" << 'EOF'
Test prompt for ${CTX}
Write status to ${STATUS}
EOF

  mkdir -p "$MOCK_FIXTURES_DIR"
}

reset_parallel_event_env() {
  unset PROJECT_ROOT STAGES_DIR MOCK_MODE MOCK_FIXTURES_DIR EVENT_SPINE_ENABLED
}

test_parallel_events_emitted() {
  local test_dir
  test_dir=$(create_test_dir)
  setup_parallel_event_env "$test_dir"

  local session="parallel-events"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  local state_file
  state_file=$(init_state "$session" "pipeline" "$run_dir")

  local block_config='{"name":"dual-refine","parallel":{"providers":["claude","codex"],"stages":[{"name":"plan","stage":"improve-plan","termination":{"type":"fixed","iterations":1}}]}}'

  run_parallel_block 0 "$block_config" "{}" "$state_file" "$run_dir" "$session" >/dev/null 2>&1

  local events
  events=$(read_events "$session")

  local provider_starts
  provider_starts=$(echo "$events" | jq -r '[.[] | select(.type == "parallel_provider_start") | .cursor.provider] | sort | join(" ")')
  assert_eq "claude codex" "$provider_starts" "parallel provider start events emitted"

  local provider_completes
  provider_completes=$(echo "$events" | jq -r '[.[] | select(.type == "parallel_provider_complete") | .cursor.provider] | sort | join(" ")')
  assert_eq "claude codex" "$provider_completes" "parallel provider complete events emitted"

  local node_paths
  node_paths=$(echo "$events" | jq -r '[.[] | select(.type == "parallel_provider_start") | .cursor.node_path] | unique | join(" ")')
  assert_eq "0" "$node_paths" "parallel provider cursor includes node path"

  local missing_provider
  missing_provider=$(echo "$events" | jq '[.[] | select(.type == "iteration_start") | (.cursor.provider // "")] | any(. == "")')
  assert_eq "false" "$missing_provider" "iteration_start cursor includes provider"

  cleanup_test_dir "$test_dir"
  reset_parallel_event_env
}

test_parallel_resume_skips_completed_provider_from_events() {
  local test_dir
  test_dir=$(create_test_dir)
  setup_parallel_event_env "$test_dir"

  local session="parallel-resume"
  local run_dir="$test_dir/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  local state_file
  state_file=$(init_state "$session" "pipeline" "$run_dir")

  local block_dir
  block_dir=$(init_parallel_block "$run_dir" 0 "dual-refine" "claude codex")
  init_provider_state "$block_dir" "claude" "$session"
  init_provider_state "$block_dir" "codex" "$session"

  local provider_cursor
  provider_cursor=$(jq -c -n --arg path "0" --arg provider "claude" \
    '{node_path: $path, node_run: 1, iteration: 0, provider: $provider}')
  local provider_data
  provider_data=$(jq -c -n --arg provider "claude" --arg status "complete" \
    '{provider: $provider, status: $status}')
  append_event "parallel_provider_complete" "$session" "$provider_cursor" "$provider_data"

  local block_config='{"name":"dual-refine","parallel":{"providers":["claude","codex"],"stages":[{"name":"plan","stage":"improve-plan","termination":{"type":"fixed","iterations":1}}]}}'
  run_parallel_block_resume 0 "$block_config" "{}" "$state_file" "$run_dir" "$session" "$block_dir" >/dev/null 2>&1

  local events
  events=$(read_events "$session")

  local claude_iters
  claude_iters=$(echo "$events" | jq '[.[] | select(.type == "iteration_start" and .cursor.provider == "claude")] | length')
  assert_eq "0" "$claude_iters" "resume skips providers completed in events"

  local codex_iters
  codex_iters=$(echo "$events" | jq '[.[] | select(.type == "iteration_start" and .cursor.provider == "codex")] | length')
  assert_eq "1" "$codex_iters" "resume runs incomplete providers"

  cleanup_test_dir "$test_dir"
  reset_parallel_event_env
}

echo ""
echo "==============================================================="
echo "  Parallel Events"
echo "==============================================================="
echo ""

run_test "parallel events emitted" test_parallel_events_emitted
run_test "parallel resume uses events" test_parallel_resume_skips_completed_provider_from_events

test_summary
