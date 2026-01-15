#!/bin/bash
# Tests for judgment judge module (scripts/lib/judge.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/events.sh"
source "$SCRIPT_DIR/lib/judge.sh"

_reset_project_root() {
  local previous_root=$1

  if [ -n "$previous_root" ]; then
    export PROJECT_ROOT="$previous_root"
  else
    unset PROJECT_ROOT
  fi
}

_reset_judge_prompt_path() {
  local previous_path=$1

  if [ -n "$previous_path" ]; then
    export JUDGE_PROMPT_PATH="$previous_path"
  else
    unset JUDGE_PROMPT_PATH
  fi
}

_write_prompt_fixture() {
  local path=$1

  cat > "$path" <<'EOF'
Stage: ${STAGE_NAME}
Iteration: ${ITERATION}
Termination: ${TERMINATION_CRITERIA}
Result: ${RESULT_JSON}
Progress: ${PROGRESS_MD}
Output: ${NODE_OUTPUT}
EOF
}

#-------------------------------------------------------------------------------
# Prompt rendering
#-------------------------------------------------------------------------------

test_render_judge_prompt_substitutes() {
  local tmp
  tmp=$(create_test_dir "judge")
  local previous_root=${PROJECT_ROOT:-}
  local previous_prompt=${JUDGE_PROMPT_PATH:-}

  export PROJECT_ROOT="$tmp"
  local prompt_file="$tmp/judge.md"
  _write_prompt_fixture "$prompt_file"
  export JUDGE_PROMPT_PATH="$prompt_file"

  local iter_dir="$tmp/iter"
  mkdir -p "$iter_dir"
  printf '%s' '{"summary":"done"}' > "$iter_dir/result.json"
  printf 'progress line' > "$tmp/progress.md"
  printf 'output line' > "$iter_dir/output.md"

  local input_json
  input_json=$(jq -n \
    --arg result "$iter_dir/result.json" \
    --arg progress "$tmp/progress.md" \
    '{session:"s", cursor:{node_path:"0", node_run:1, iteration:2}, node:{id:"plan"}, paths:{result:$result, progress:$progress}, termination:{type:"judgment", max:5}}')

  local prompt
  prompt=$(render_judge_prompt "$input_json")

  assert_contains "$prompt" "Stage: plan" "stage name substituted"
  assert_contains "$prompt" "Iteration: 2" "iteration substituted"
  assert_contains "$prompt" "\"type\":\"judgment\"" "termination embedded"
  assert_contains "$prompt" "\"summary\":\"done\"" "result JSON embedded"
  assert_contains "$prompt" "progress line" "progress content embedded"
  assert_contains "$prompt" "output line" "output content embedded"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
  _reset_judge_prompt_path "$previous_prompt"
}

#-------------------------------------------------------------------------------
# Judge invocation
#-------------------------------------------------------------------------------

test_judge_decision_records_events() {
  local tmp
  tmp=$(create_test_dir "judge")
  local previous_root=${PROJECT_ROOT:-}
  local previous_prompt=${JUDGE_PROMPT_PATH:-}

  export PROJECT_ROOT="$tmp"
  local prompt_file="$tmp/judge.md"
  _write_prompt_fixture "$prompt_file"
  export JUDGE_PROMPT_PATH="$prompt_file"

  local iter_dir="$tmp/iter"
  mkdir -p "$iter_dir"
  printf '%s' '{}' > "$iter_dir/result.json"
  printf 'progress' > "$tmp/progress.md"

  local input_json
  input_json=$(jq -n \
    --arg result "$iter_dir/result.json" \
    --arg progress "$tmp/progress.md" \
    '{session:"judge-session", cursor:{node_path:"0", node_run:1, iteration:1}, node:{id:"stage"}, paths:{result:$result, progress:$progress}, termination:{type:"judgment"}}')

  invoke_judge() {
    echo '{"stop": true, "reason": "done", "confidence": 0.9}'
  }

  local output
  output=$(judge_decision "$input_json")
  local stop
  stop=$(echo "$output" | jq -r '.stop')
  assert_eq "true" "$stop" "judge_decision returns stop=true"

  local events
  events=$(read_events "judge-session")
  local start_count
  start_count=$(echo "$events" | jq '[.[] | select(.type=="judge_start")] | length')
  assert_eq "1" "$start_count" "judge_start logged"

  local complete_status
  complete_status=$(echo "$events" | jq -r '[.[] | select(.type=="judge_complete")] | last | .data.status')
  assert_eq "success" "$complete_status" "judge_complete logged success"

  unset -f invoke_judge
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
  _reset_judge_prompt_path "$previous_prompt"
}

test_judge_decision_retries_once() {
  local tmp
  tmp=$(create_test_dir "judge")
  local previous_root=${PROJECT_ROOT:-}
  local previous_prompt=${JUDGE_PROMPT_PATH:-}

  export PROJECT_ROOT="$tmp"
  local prompt_file="$tmp/judge.md"
  _write_prompt_fixture "$prompt_file"
  export JUDGE_PROMPT_PATH="$prompt_file"

  local iter_dir="$tmp/iter"
  mkdir -p "$iter_dir"
  printf '%s' '{}' > "$iter_dir/result.json"
  printf 'progress' > "$tmp/progress.md"

  local input_json
  input_json=$(jq -n \
    --arg result "$iter_dir/result.json" \
    --arg progress "$tmp/progress.md" \
    '{session:"judge-retry", cursor:{node_path:"0", node_run:1, iteration:2}, node:{id:"stage"}, paths:{result:$result, progress:$progress}, termination:{type:"judgment"}}')

  local attempts=0
  invoke_judge() {
    attempts=$((attempts + 1))
    if [ "$attempts" -eq 1 ]; then
      return 1
    fi
    echo '{"stop": false, "reason": "keep", "confidence": 0.9}'
  }

  judge_decision "$input_json" >/dev/null
  assert_eq "2" "$attempts" "judge_decision retries once on failure"

  unset -f invoke_judge
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
  _reset_judge_prompt_path "$previous_prompt"
}

test_judge_decision_skips_after_failures() {
  local tmp
  tmp=$(create_test_dir "judge")
  local previous_root=${PROJECT_ROOT:-}
  local previous_prompt=${JUDGE_PROMPT_PATH:-}

  export PROJECT_ROOT="$tmp"
  local prompt_file="$tmp/judge.md"
  _write_prompt_fixture "$prompt_file"
  export JUDGE_PROMPT_PATH="$prompt_file"

  local iter_dir="$tmp/iter"
  mkdir -p "$iter_dir"
  printf '%s' '{}' > "$iter_dir/result.json"
  printf 'progress' > "$tmp/progress.md"

  local session="judge-unreliable"
  local cursor
  cursor=$(jq -n --arg path "0" --argjson run 1 --argjson iter 1 \
    '{node_path: $path, node_run: $run, iteration: $iter}')
  append_event "judge_complete" "$session" "$cursor" '{"status":"failed","reason":"invalid"}'
  cursor=$(jq -n --arg path "0" --argjson run 1 --argjson iter 2 \
    '{node_path: $path, node_run: $run, iteration: $iter}')
  append_event "judge_complete" "$session" "$cursor" '{"status":"failed","reason":"invalid"}'
  cursor=$(jq -n --arg path "0" --argjson run 1 --argjson iter 3 \
    '{node_path: $path, node_run: $run, iteration: $iter}')
  append_event "judge_complete" "$session" "$cursor" '{"status":"failed","reason":"invalid"}'

  local input_json
  input_json=$(jq -n \
    --arg result "$iter_dir/result.json" \
    --arg progress "$tmp/progress.md" \
    --arg session "$session" \
    '{session:$session, cursor:{node_path:"0", node_run:1, iteration:4}, node:{id:"stage"}, paths:{result:$result, progress:$progress}, termination:{type:"judgment"}}')

  local attempts=0
  invoke_judge() {
    attempts=$((attempts + 1))
    echo '{"stop": true, "reason": "done", "confidence": 0.9}'
  }

  local output
  output=$(judge_decision "$input_json")
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  assert_eq "judge_unreliable" "$reason" "judge skips after consecutive failures"
  assert_eq "0" "$attempts" "judge not invoked after failures"

  unset -f invoke_judge
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
  _reset_judge_prompt_path "$previous_prompt"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Judgment Judge"
echo "==============================================================="

run_test "render_judge_prompt substitutes values" test_render_judge_prompt_substitutes
run_test "judge_decision logs events" test_judge_decision_records_events
run_test "judge_decision retries once" test_judge_decision_retries_once
run_test "judge_decision skips after failures" test_judge_decision_skips_after_failures

test_summary
