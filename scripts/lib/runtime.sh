#!/bin/bash
# Unified v3 runtime executor for plan.json nodes.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

RUNTIME_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$RUNTIME_SCRIPT_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$RUNTIME_SCRIPT_DIR/../.." && pwd)}"

source "$LIB_DIR/events.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/progress.sh"
source "$LIB_DIR/resolve.sh"
source "$LIB_DIR/provider.sh"
source "$LIB_DIR/status.sh"
source "$LIB_DIR/deps.sh"
source "$LIB_DIR/lock.sh"
source "$LIB_DIR/stage.sh"

RUNTIME_PLAN_FILE=""
RUNTIME_SESSION=""
RUNTIME_SESSION_DIR=""
RUNTIME_STATE_FILE=""
RUNTIME_PROGRESS_FILE=""
RUNTIME_PIPELINE_NAME=""
RUNTIME_COMMANDS_JSON="{}"
RUNTIME_INITIAL_INPUTS_JSON="[]"

runtime_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

runtime_int_or_default() {
  local value=$1
  local fallback=$2
  if runtime_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

runtime_stage_index_from_path() {
  local node_path=$1
  local head="${node_path%%.*}"
  runtime_int_or_default "$head" 0
}

runtime_format_index() {
  local value=$1
  printf '%04d' "$value"
}

runtime_node_dir() {
  local session_dir=$1
  local node_path=$2
  echo "$session_dir/artifacts/node-${node_path}"
}

runtime_node_run_dir() {
  local node_dir=$1
  local node_run=$2
  echo "$node_dir/run-$(runtime_format_index "$node_run")"
}

runtime_node_iteration_dir() {
  local node_run_dir=$1
  local iteration=$2
  echo "$node_run_dir/iteration-$(runtime_format_index "$iteration")"
}

runtime_write_atomic() {
  local path=$1
  local content=$2
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"
  local tmp_file
  tmp_file=$(mktemp)
  printf '%s\n' "$content" > "$tmp_file"
  mv "$tmp_file" "$path"
}

runtime_build_cursor() {
  local node_path=$1
  local node_run=$2
  local iteration=$3

  if [ -z "$node_path" ] || [ "$node_path" = "null" ]; then
    echo "null"
    return 0
  fi

  node_run=$(runtime_int_or_default "$node_run" 0)
  iteration=$(runtime_int_or_default "$iteration" 0)

  jq -c -n \
    --arg path "$node_path" \
    --argjson run "$node_run" \
    --argjson iter "$iteration" \
    '{node_path: $path, node_run: $run, iteration: $iter}'
}

runtime_emit_event() {
  local type=$1
  local cursor_json=${2:-"null"}
  local data_json=${3:-"{}"}

  if [ -z "$RUNTIME_SESSION" ]; then
    return 1
  fi

  if [ -z "$cursor_json" ]; then
    cursor_json="null"
  fi
  if [ -z "$data_json" ] || [ "$data_json" = "null" ]; then
    data_json="{}"
  fi

  if ! append_event "$type" "$RUNTIME_SESSION" "$cursor_json" "$data_json"; then
    echo "Warning: Failed to append event '$type' for session '$RUNTIME_SESSION'" >&2
    return 1
  fi
}

runtime_initial_inputs() {
  local plan_file=$1
  local initial="[]"

  if [ -f "$plan_file" ]; then
    initial=$(jq -c '.session.inputs // .pipeline.inputs // []' "$plan_file" 2>/dev/null || echo "[]")
    if ! echo "$initial" | jq -e 'type == "array"' >/dev/null 2>&1; then
      initial="[]"
    fi
  fi

  echo "$initial"
}

runtime_inputs_json() {
  local node_run_dir=$1
  local iteration=$2

  local from_previous="[]"
  if [ "$iteration" -gt 1 ]; then
    local files=()
    for ((i=1; i<iteration; i++)); do
      local candidate="$node_run_dir/iteration-$(runtime_format_index "$i")/output.md"
      [ -f "$candidate" ] && files+=("$candidate")
    done

    if [ ${#files[@]} -gt 0 ]; then
      from_previous=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)
    fi
  fi

  jq -n \
    --argjson from_stage '{}' \
    --argjson from_previous "$from_previous" \
    --argjson from_initial "$RUNTIME_INITIAL_INPUTS_JSON" \
    '{from_stage: $from_stage, from_previous_iterations: $from_previous, from_initial: $from_initial}'
}

runtime_context_json() {
  local node_id=$1
  local node_path=$2
  local template=$3
  local iteration=$4
  local node_dir=$5
  local progress_file=$6
  local output_file=$7
  local status_file=$8
  local inputs_json=$9
  local max_iterations=${10}

  local stage_index
  stage_index=$(runtime_stage_index_from_path "$node_path")

  jq -n \
    --arg session "$RUNTIME_SESSION" \
    --arg pipeline "$RUNTIME_PIPELINE_NAME" \
    --arg stage_id "$node_id" \
    --argjson stage_idx "$stage_index" \
    --arg template "$template" \
    --argjson iteration "$iteration" \
    --arg session_dir "$RUNTIME_SESSION_DIR" \
    --arg stage_dir "$node_dir" \
    --arg progress "$progress_file" \
    --arg output "$output_file" \
    --arg status "$status_file" \
    --argjson inputs "$inputs_json" \
    --argjson max_iterations "$max_iterations" \
    --argjson remaining "-1" \
    --argjson commands "$RUNTIME_COMMANDS_JSON" \
    '{
      session: $session,
      pipeline: $pipeline,
      stage: {id: $stage_id, index: $stage_idx, template: $template},
      iteration: $iteration,
      paths: {
        session_dir: $session_dir,
        stage_dir: $stage_dir,
        progress: $progress,
        output: $output,
        status: $status
      },
      inputs: $inputs,
      limits: {
        max_iterations: $max_iterations,
        remaining_seconds: $remaining
      },
      commands: $commands
    }'
}

runtime_resolve_output_path() {
  local output_path=$1
  local session=$2

  if [ -z "$output_path" ] || [ "$output_path" = "null" ]; then
    echo ""
    return
  fi

  local resolved="${output_path//\$\{SESSION\}/$session}"
  resolved="${resolved//\$\{SESSION_NAME\}/$session}"
  echo "$resolved"
}

runtime_load_prompt() {
  local node_json=$1
  local stage_ref=$2

  local prompt_inline
  prompt_inline=$(echo "$node_json" | jq -r '.prompt // empty')
  if [ -n "$prompt_inline" ] && [ "$prompt_inline" != "null" ]; then
    echo "$prompt_inline"
    return 0
  fi

  local prompt_path
  prompt_path=$(echo "$node_json" | jq -r '.prompt_path // empty')
  if [ -n "$prompt_path" ] && [ "$prompt_path" != "null" ]; then
    local resolved="$prompt_path"
    if [[ "$resolved" != /* ]]; then
      resolved="$PROJECT_ROOT/$resolved"
    fi
    if [ ! -f "$resolved" ]; then
      echo "Error: Prompt file not found: $resolved" >&2
      return 1
    fi
    cat "$resolved"
    return 0
  fi

  if [ -n "$stage_ref" ]; then
    load_stage "$stage_ref" || return 1
    echo "$STAGE_PROMPT"
    return 0
  fi

  echo "Error: No prompt found for node" >&2
  return 1
}

run_session() {
  local plan_file=$1
  local session_dir=${2:-""}

  if [ -z "$plan_file" ] || [ ! -f "$plan_file" ]; then
    echo "Error: plan.json not found: $plan_file" >&2
    return 1
  fi

  check_deps || return 1

  if [ -z "$session_dir" ]; then
    session_dir=$(dirname "$plan_file")
  fi

  local session
  session=$(jq -r '.session.name // empty' "$plan_file")
  if [ -z "$session" ] || [ "$session" = "null" ]; then
    session=$(basename "$session_dir")
  fi

  RUNTIME_PLAN_FILE="$plan_file"
  RUNTIME_SESSION="$session"
  RUNTIME_SESSION_DIR="$session_dir"
  RUNTIME_STATE_FILE=$(init_state "$session" "pipeline" "$session_dir")
  RUNTIME_PROGRESS_FILE=$(init_progress "$session" "$session_dir")
  RUNTIME_PIPELINE_NAME=$(jq -r '.pipeline.name // .session.name // ""' "$plan_file")
  RUNTIME_COMMANDS_JSON=$(jq -c '.pipeline.commands // {}' "$plan_file" 2>/dev/null || echo "{}")
  RUNTIME_INITIAL_INPUTS_JSON=$(runtime_initial_inputs "$plan_file")

  export CLAUDE_PIPELINE_SESSION="$session"
  export CLAUDE_PIPELINE_TYPE="$RUNTIME_PIPELINE_NAME"

  if [ "${PIPELINE_NO_LOCK:-}" != "1" ] && [ "${NO_LOCK:-}" != "1" ]; then
    acquire_lock "$session" || return 1
    trap 'release_lock "$RUNTIME_SESSION"' EXIT
  fi

  local start_cursor
  start_cursor=$(runtime_build_cursor "0" 0 0)
  local session_data
  session_data=$(jq -n --arg session "$session" '{session: $session}')
  runtime_emit_event "session_start" "$start_cursor" "$session_data" || true

  local node_json=""
  local node_count
  node_count=$(jq -r '.nodes | length' "$plan_file" 2>/dev/null || echo "0")

  if ! runtime_is_int "$node_count"; then
    node_count=0
  fi

  if [ "$node_count" -eq 0 ]; then
    runtime_emit_event "session_complete" "$start_cursor" "{}" || true
    mark_complete "$RUNTIME_STATE_FILE" "no_nodes"
    return 0
  fi

  while IFS= read -r node_json; do
    [ -z "$node_json" ] && continue
    if ! run_node "$node_json"; then
      local error_data
      error_data=$(jq -n --arg node "$(echo "$node_json" | jq -r '.id // "unknown"')" \
        '{message: "node_failed", node: $node}')
      runtime_emit_event "error" "$(runtime_build_cursor "0" 0 0)" "$error_data" || true
      return 1
    fi
  done < <(jq -c '.nodes[]' "$plan_file")

  runtime_emit_event "session_complete" "$(runtime_build_cursor "0" 0 0)" "{}" || true
  mark_complete "$RUNTIME_STATE_FILE" "complete"
  return 0
}

run_node() {
  local node_json=$1
  local node_path
  node_path=$(echo "$node_json" | jq -r '.path // empty')
  local node_id
  node_id=$(echo "$node_json" | jq -r '.id // empty')
  local node_kind
  node_kind=$(echo "$node_json" | jq -r '.kind // "stage"')
  local runs
  runs=$(echo "$node_json" | jq -r '.runs // 1')
  runs=$(runtime_int_or_default "$runs" 1)

  local stage_idx
  stage_idx=$(runtime_stage_index_from_path "$node_path")
  update_stage "$RUNTIME_STATE_FILE" "$stage_idx" "$node_id" "running" || true

  runtime_emit_event "node_start" "$(runtime_build_cursor "$node_path" 0 0)" \
    "$(jq -n --arg id "$node_id" --arg kind "$node_kind" --arg path "$node_path" '{id: $id, kind: $kind, path: $path}')" || true

  local run_index
  for run_index in $(seq 1 "$runs"); do
    runtime_emit_event "node_run_start" "$(runtime_build_cursor "$node_path" "$run_index" 0)" \
      "$(jq -n --argjson run "$run_index" '{run: $run}')" || true

    case "$node_kind" in
      stage)
        run_stage "$node_json" "$run_index" || return 1
        ;;
      pipeline)
        run_pipeline "$node_json" "$run_index" || return 1
        ;;
      *)
        echo "Error: Unknown node kind '$node_kind'" >&2
        return 1
        ;;
    esac
  done

  update_stage "$RUNTIME_STATE_FILE" "$stage_idx" "$node_id" "complete" || true
  runtime_emit_event "node_complete" "$(runtime_build_cursor "$node_path" "$runs" 0)" \
    "$(jq -n --arg id "$node_id" '{id: $id, status: "complete"}')" || true
  return 0
}

run_stage() {
  local node_json=$1
  local node_run=$2

  local node_path
  node_path=$(echo "$node_json" | jq -r '.path // empty')
  local node_id
  node_id=$(echo "$node_json" | jq -r '.id // empty')
  local stage_ref
  stage_ref=$(echo "$node_json" | jq -r '.ref // empty')

  local term_type
  term_type=$(echo "$node_json" | jq -r '.termination.type // "fixed"')
  local max_iters
  max_iters=$(echo "$node_json" | jq -r '.termination.max // .termination.iterations // 1')
  max_iters=$(runtime_int_or_default "$max_iters" 1)
  local min_iters
  min_iters=$(echo "$node_json" | jq -r '.termination.min_iterations // 1')
  min_iters=$(runtime_int_or_default "$min_iters" 1)
  local consensus
  consensus=$(echo "$node_json" | jq -r '.termination.consensus // 2')
  consensus=$(runtime_int_or_default "$consensus" 2)
  local delay_raw
  delay_raw=$(echo "$node_json" | jq -r '.delay // empty')
  local delay="$delay_raw"

  local provider
  provider=$(echo "$node_json" | jq -r '.provider.type // empty')
  local model
  model=$(echo "$node_json" | jq -r '.provider.model // empty')

  local node_context
  node_context=$(echo "$node_json" | jq -r '.context // empty')

  local stage_prompt
  stage_prompt=$(runtime_load_prompt "$node_json" "$stage_ref") || return 1

  if [ -z "$provider" ] && [ -n "$stage_ref" ]; then
    load_stage "$stage_ref" || return 1
    provider="$STAGE_PROVIDER"
    [ -z "$model" ] && model="$STAGE_MODEL"
    [ -z "$node_context" ] && node_context="$STAGE_CONTEXT"
    if [ -z "$delay" ]; then
      delay="$STAGE_DELAY"
    fi
  fi

  delay=$(runtime_int_or_default "$delay" 0)

  if [ -z "$provider" ]; then
    provider="claude"
  fi
  if [ -z "$model" ]; then
    model=$(get_default_model "$provider")
  fi

  if [ "$MOCK_MODE" != true ]; then
    check_provider "$provider" || return 1
  fi

  local completion_script=""
  case "$term_type" in
    queue) completion_script="$LIB_DIR/completions/beads-empty.sh" ;;
    judgment) completion_script="$LIB_DIR/completions/plateau.sh" ;;
    fixed|*) completion_script="$LIB_DIR/completions/fixed-n.sh" ;;
  esac
  if [ -f "$completion_script" ]; then
    source "$completion_script"
  fi

  export MIN_ITERATIONS="$min_iters"
  export CONSENSUS="$consensus"
  export MAX_ITERATIONS="$max_iters"
  export FIXED_ITERATIONS="$max_iters"

  local node_dir
  node_dir=$(runtime_node_dir "$RUNTIME_SESSION_DIR" "$node_path")
  local node_run_dir
  node_run_dir=$(runtime_node_run_dir "$node_dir" "$node_run")
  mkdir -p "$node_run_dir"

  local completion_reason=""

  for iter in $(seq 1 "$max_iters"); do
    local iter_dir
    iter_dir=$(runtime_node_iteration_dir "$node_run_dir" "$iter")
    mkdir -p "$iter_dir"

    mark_iteration_started "$RUNTIME_STATE_FILE" "$iter" || true
    runtime_emit_event "iteration_start" "$(runtime_build_cursor "$node_path" "$node_run" "$iter")" \
      "$(jq -n --arg id "$node_id" --arg provider "$provider" --arg model "$model" '{id: $id, provider: $provider, model: $model}')" || true

    local output_file="$iter_dir/output.md"
    local status_file="$iter_dir/status.json"
    local resolved_output_path
    resolved_output_path=$(runtime_resolve_output_path "$(echo "$node_json" | jq -r '.output_path // empty')" "$RUNTIME_SESSION")
    if [ -n "$resolved_output_path" ]; then
      mkdir -p "$(dirname "$resolved_output_path")"
    fi

    local inputs_json
    inputs_json=$(runtime_inputs_json "$node_run_dir" "$iter")
    local context_json
    context_json=$(runtime_context_json "$node_id" "$node_path" "$stage_ref" "$iter" "$node_dir" \
      "$RUNTIME_PROGRESS_FILE" "$output_file" "$status_file" "$inputs_json" "$max_iters")
    local context_file="$iter_dir/ctx.json"
    runtime_write_atomic "$context_file" "$context_json"

    local vars_json
    vars_json=$(jq -n \
      --arg session "$RUNTIME_SESSION" \
      --arg iteration "$iter" \
      --arg index "$((iter - 1))" \
      --arg progress "$RUNTIME_PROGRESS_FILE" \
      --arg output "$output_file" \
      --arg output_path "$resolved_output_path" \
      --arg context_file "$context_file" \
      --arg status_file "$status_file" \
      --arg context "$node_context" \
      '{session: $session, iteration: $iteration, index: $index, progress: $progress, output: $output, output_path: $output_path, context_file: $context_file, status_file: $status_file, context: $context}')

    local resolved_prompt
    resolved_prompt=$(resolve_prompt "$stage_prompt" "$vars_json")

    export MOCK_STATUS_FILE="$status_file"
    export MOCK_ITERATION="$iter"

    local output=""
    local exit_code=0
    set +e
    output=$(execute_agent "$provider" "$resolved_prompt" "$model")
    exit_code=$?
    set -e

    if [ $exit_code -ne 0 ]; then
      runtime_emit_event "error" "$(runtime_build_cursor "$node_path" "$node_run" "$iter")" \
        "$(jq -n --arg msg "Agent exited with $exit_code" --argjson code "$exit_code" '{message: $msg, exit_code: $code}')" || true
      create_error_status "$status_file" "Agent exited with code $exit_code"
      mark_failed "$RUNTIME_STATE_FILE" "Agent exited with code $exit_code" "exit_code"
      return 1
    fi

    [ -n "$output" ] && echo "$output" > "$output_file"

    if [ ! -f "$status_file" ]; then
      create_error_status "$status_file" "Agent did not write status.json"
    fi

    if ! validate_status "$status_file"; then
      create_error_status "$status_file" "Agent wrote invalid status.json"
    fi

    local history_json
    history_json=$(status_to_history_json "$status_file")
    update_iteration "$RUNTIME_STATE_FILE" "$iter" "$history_json" "$node_id" || true
    mark_iteration_completed "$RUNTIME_STATE_FILE" "$iter" || true

    runtime_emit_event "worker_complete" "$(runtime_build_cursor "$node_path" "$node_run" "$iter")" \
      "$(jq -n --arg status "$status_file" --argjson code "$exit_code" '{status_file: $status, exit_code: $code}')" || true

    local decision
    decision=$(get_status_decision "$status_file")
    local reason
    reason=$(get_status_reason "$status_file")
    runtime_emit_event "iteration_complete" "$(runtime_build_cursor "$node_path" "$node_run" "$iter")" \
      "$(jq -n --arg decision "$decision" --arg reason "$reason" '{decision: $decision, reason: $reason}')" || true

    if type check_completion >/dev/null 2>&1; then
      local completion_output=""
      if completion_output=$(check_completion "$RUNTIME_SESSION" "$RUNTIME_STATE_FILE" "$status_file"); then
        completion_reason="$completion_output"
        break
      fi
    fi

    if type check_output_signal >/dev/null 2>&1; then
      if check_output_signal "$output"; then
        completion_reason="completion_signal"
        break
      fi
    fi

    if [ "$delay" -gt 0 ]; then
      sleep "$delay"
    fi
  done

  if [ -z "$completion_reason" ]; then
    completion_reason="max_iterations"
  fi

  return 0
}

run_pipeline() {
  local node_json=$1
  local node_run=$2
  local node_path
  node_path=$(echo "$node_json" | jq -r '.path // empty')

  local subplan
  subplan=$(echo "$node_json" | jq -c '.plan // .subplan // empty')
  if [ -z "$subplan" ] || [ "$subplan" = "null" ]; then
    echo "Error: Pipeline node missing embedded plan" >&2
    return 1
  fi

  local subnode_json=""
  while IFS= read -r subnode_json; do
    [ -z "$subnode_json" ] && continue
    local sub_path
    sub_path=$(echo "$subnode_json" | jq -r '.path // empty')
    local combined_path="$sub_path"
    if [ -n "$node_path" ] && [ -n "$sub_path" ] && [[ "$sub_path" != "$node_path."* ]]; then
      combined_path="${node_path}.${sub_path}"
    fi
    subnode_json=$(echo "$subnode_json" | jq -c --arg path "$combined_path" '.path = $path')
    run_node "$subnode_json" || return 1
  done < <(echo "$subplan" | jq -c '.nodes[]')

  return 0
}
