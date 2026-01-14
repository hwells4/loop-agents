#!/bin/bash
set -e

# Unified Pipeline Engine
# Everything is a pipeline. A "loop" is just a single-stage pipeline.
#
# All sessions run in: .claude/pipeline-runs/{session}/
# Each session gets: state.json, progress files, stage directories
#
# Usage:
#   engine.sh pipeline <pipeline.yaml> [session]              # Run multi-stage pipeline
#   engine.sh pipeline --single-stage <type> [session] [max]  # Run single-loop pipeline
#   engine.sh status <session>                                # Check session status

MODE=${1:?"Usage: engine.sh <pipeline|status> <args>"}
shift

# Paths (allow env overrides for testing)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
LIB_DIR="${LIB_DIR:-$SCRIPT_DIR/lib}"
STAGES_DIR="${STAGES_DIR:-$SCRIPT_DIR/stages}"

export PROJECT_ROOT

# Check dependencies
source "$LIB_DIR/deps.sh"
check_deps

# Source libraries
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/progress.sh"
source "$LIB_DIR/resolve.sh"
source "$LIB_DIR/context.sh"
source "$LIB_DIR/status.sh"
source "$LIB_DIR/notify.sh"
source "$LIB_DIR/lock.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/provider.sh"
source "$LIB_DIR/stage.sh"
source "$LIB_DIR/parallel.sh"
source "$LIB_DIR/events.sh"

# Source mock library if MOCK_MODE is enabled (for testing)
if [ "$MOCK_MODE" = true ] && [ -f "$LIB_DIR/mock.sh" ]; then
  source "$LIB_DIR/mock.sh"
fi

# Export for hooks
export CLAUDE_PIPELINE_AGENT=1

#-------------------------------------------------------------------------------
# Event Helpers
#-------------------------------------------------------------------------------

# Build cursor JSON for events.jsonl.
# Usage: build_event_cursor "$node_path" "$iteration" ["$node_run"]
build_event_cursor() {
  local node_path=$1
  local iteration=${2:-0}
  local node_run=${3:-""}

  if [ -z "$node_path" ] || [ "$node_path" = "null" ]; then
    echo "null"
    return 0
  fi

  if [ -z "$node_run" ]; then
    node_run="$iteration"
  fi

  if ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
    iteration=0
  fi
  if ! [[ "$node_run" =~ ^[0-9]+$ ]]; then
    node_run=0
  fi

  jq -c -n \
    --arg path "$node_path" \
    --argjson run "$node_run" \
    --argjson iter "$iteration" \
    '{node_path: $path, node_run: $run, iteration: $iter}'
}

# Build cursor JSON from state snapshot for session-level events.
# Usage: event_cursor_from_state "$state_file"
event_cursor_from_state() {
  local state_file=$1

  local node_path="0"
  local iteration="0"
  if [ -f "$state_file" ]; then
    node_path=$(jq -r '.current_stage // 0' "$state_file" 2>/dev/null)
    iteration=$(jq -r '.iteration_completed // .iteration // 0' "$state_file" 2>/dev/null)
  fi

  build_event_cursor "$node_path" "$iteration" "$iteration"
}

# Append event to events.jsonl (warns on failure).
# Usage: emit_event_or_warn "$type" "$session" ["$cursor_json"] ["$data_json"]
emit_event_or_warn() {
  local type=$1
  local session=$2
  local cursor_json=${3:-"null"}
  local data_json=${4:-"{}"}

  if [ -z "$cursor_json" ]; then
    cursor_json="null"
  fi
  if [ -z "$data_json" ] || [ "$data_json" = "null" ]; then
    data_json="{}"
  fi

  if ! append_event "$type" "$session" "$cursor_json" "$data_json"; then
    echo "Warning: Failed to append event '$type' for session '$session'" >&2
    return 1
  fi
}

#-------------------------------------------------------------------------------
# Run Stage
#-------------------------------------------------------------------------------

# Run a single stage for N iterations
# Usage: run_stage "$stage_type" "$session" "$max_iterations" "$run_dir" "$stage_idx" "$start_iteration"
run_stage() {
  local stage_type=$1
  local session=$2
  local max_iterations=${3:-25}
  local run_dir=${4:-"$PROJECT_ROOT/.claude"}
  local stage_idx=${5:-0}
  local start_iteration=${6:-1}

  load_stage "$stage_type" || return 1
  if [ "$STAGE_COMPLETION" = "beads-empty" ]; then
    check_deps --require-bd || return 1
  fi

  # Check provider is available (once at session start, not per iteration)
  check_provider "$STAGE_PROVIDER" || return 1

  # Source completion strategy
  local completion_script="$LIB_DIR/completions/${STAGE_COMPLETION}.sh"
  if [ ! -f "$completion_script" ]; then
    echo "Error: Unknown completion strategy: $STAGE_COMPLETION" >&2
    return 1
  fi
  source "$completion_script"

  # Initialize state and progress
  local state_file=$(init_state "$session" "loop" "$run_dir")
  local progress_file=$(init_progress "$session" "$run_dir")

  local events_file
  events_file=$(events_file_path "$session")
  if [ ! -s "$events_file" ]; then
    local start_cursor
    start_cursor=$(build_event_cursor "$stage_idx" 0 0)
    local start_data
    start_data=$(jq -n \
      --arg mode "loop" \
      --arg stage "$stage_type" \
      --arg name "$STAGE_NAME" \
      '{mode: $mode, stage: $stage, stage_name: $name}')
    emit_event_or_warn "session_start" "$session" "$start_cursor" "$start_data" || true

    local node_data
    node_data=$(jq -n \
      --arg name "$STAGE_NAME" \
      --arg type "$stage_type" \
      --arg provider "$STAGE_PROVIDER" \
      --arg model "$STAGE_MODEL" \
      '{name: $name, type: $type, provider: $provider, model: $model}')
    emit_event_or_warn "node_start" "$session" "$start_cursor" "$node_data" || true
  fi

  export CLAUDE_PIPELINE_SESSION="$session"
  export CLAUDE_PIPELINE_TYPE="$stage_type"
  export MAX_ITERATIONS="$max_iterations"

  # Display header
  if [ "$start_iteration" -eq 1 ]; then
    echo ""
    echo "  Loop: $STAGE_NAME"
    echo "  Session: $session"
    echo "  Max iterations: $max_iterations"
    echo "  Model: $STAGE_MODEL"
    echo "  Completion: $STAGE_COMPLETION"
    [ -n "$STAGE_OUTPUT_PATH" ] && echo "  Output: ${STAGE_OUTPUT_PATH//\$\{SESSION\}/$session}"
    echo ""
  else
    show_resume_info "$session" "$start_iteration" "$max_iterations"
  fi

  for i in $(seq $start_iteration $max_iterations); do
    echo ""
    echo "  Iteration $i of $max_iterations"
    echo ""

    # Mark iteration started (for crash recovery)
    mark_iteration_started "$state_file" "$i"
    local iter_cursor
    iter_cursor=$(build_event_cursor "$stage_idx" "$i" "$i")
    local iter_start_data
    iter_start_data=$(jq -n \
      --arg stage "$STAGE_NAME" \
      --arg type "$stage_type" \
      --arg provider "$STAGE_PROVIDER" \
      --arg model "$STAGE_MODEL" \
      '{stage: $stage, type: $type, provider: $provider, model: $model}')
    emit_event_or_warn "iteration_start" "$session" "$iter_cursor" "$iter_start_data" || true

    # Pre-iteration completion check
    if [ "$STAGE_CHECK_BEFORE" = "true" ]; then
      if check_completion "$session" "$state_file" ""; then
        local reason=$(check_completion "$session" "$state_file" "" 2>&1)
        echo "$reason"
        mark_complete "$state_file" "$reason"
        local complete_cursor
        complete_cursor=$(build_event_cursor "$stage_idx" 0 0)
        local node_complete_data
        node_complete_data=$(jq -n \
          --arg name "$STAGE_NAME" \
          --arg reason "$reason" \
          '{name: $name, status: "complete", reason: $reason}')
        emit_event_or_warn "node_complete" "$session" "$complete_cursor" "$node_complete_data" || true
        local session_complete_data
        session_complete_data=$(jq -n --arg reason "$reason" '{reason: $reason}')
        emit_event_or_warn "session_complete" "$session" "$complete_cursor" "$session_complete_data" || true
        record_completion "complete" "$session" "$stage_type"
        return 0
      fi
    fi

    # Resolve output_path (replace ${SESSION} with actual session name)
    local resolved_output_path=""
    if [ -n "$STAGE_OUTPUT_PATH" ]; then
      resolved_output_path="${STAGE_OUTPUT_PATH//\$\{SESSION\}/$session}"
      resolved_output_path="${resolved_output_path//\$\{SESSION_NAME\}/$session}"
      # Create parent directory if it doesn't exist
      local output_dir=$(dirname "$resolved_output_path")
      [ -n "$output_dir" ] && [ "$output_dir" != "." ] && mkdir -p "$output_dir"
    fi

    # Build stage config JSON for context generation
    local stage_config_json=$(jq -n \
      --arg id "$stage_type" \
      --arg name "$stage_type" \
      --argjson index "$stage_idx" \
      --arg loop "$stage_type" \
      --argjson max_iterations "$max_iterations" \
      '{id: $id, name: $name, index: $index, loop: $loop, max_iterations: $max_iterations}')

    # Generate context.json for this iteration (v3)
    local context_file=$(generate_context "$session" "$i" "$stage_config_json" "$run_dir")

    # Build variables for prompt resolution (includes v3 context file)
    local vars_json=$(jq -n \
      --arg session "$session" \
      --arg iteration "$i" \
      --arg index "$((i - 1))" \
      --arg progress "$progress_file" \
      --arg output_path "$resolved_output_path" \
      --arg run_dir "$run_dir" \
      --arg stage_idx "$stage_idx" \
      --arg context_file "$context_file" \
      --arg status_file "$(dirname "$context_file")/status.json" \
      --arg context "$STAGE_CONTEXT" \
      '{session: $session, iteration: $iteration, index: $index, progress: $progress, output_path: $output_path, run_dir: $run_dir, stage_idx: $stage_idx, context_file: $context_file, status_file: $status_file, context: $context}')

    # Resolve prompt
    local resolved_prompt=$(resolve_prompt "$STAGE_PROMPT" "$vars_json")

    # Export status file path for mock mode (mock.sh needs to know where to write status)
    export MOCK_STATUS_FILE="$(dirname "$context_file")/status.json"
    export MOCK_ITERATION="$i"

    # Execute agent
    set +e
    local output=$(execute_agent "$STAGE_PROVIDER" "$resolved_prompt" "$STAGE_MODEL" | tee /dev/stderr)
    local exit_code=$?
    set -e

    # Get iteration directory path (from context file location)
    local iter_dir="$(dirname "$context_file")"
    local status_file="$iter_dir/status.json"

    # Phase 5: Fail fast - no retries, immediate failure with clear state
    if [ $exit_code -ne 0 ]; then
      local error_msg="Claude process exited with code $exit_code"
      local error_cursor
      error_cursor=$(build_event_cursor "$stage_idx" "$i" "$i")
      local error_data
      error_data=$(jq -n \
        --arg message "$error_msg" \
        --argjson code "$exit_code" \
        --arg stage "$STAGE_NAME" \
        '{message: $message, exit_code: $code, stage: $stage}')
      emit_event_or_warn "error" "$session" "$error_cursor" "$error_data" || true

      # Write error status to iteration
      create_error_status "$status_file" "$error_msg"

      # Update state with structured failure info
      mark_failed "$state_file" "$error_msg" "exit_code"

      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Session failed at iteration $i"
      echo "  Error: $error_msg"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "To resume: ./scripts/run.sh loop $stage_type $session $max_iterations --resume"
      echo ""

      record_completion "failed" "$session" "$stage_type"
      return 1
    fi

    # Phase 3: Save output snapshot to iteration directory
    if [ -n "$output" ]; then
      echo "$output" > "$iter_dir/output.md"
    fi

    # Phase 3: Create error status if agent didn't write status.json
    if [ ! -f "$status_file" ]; then
      create_error_status "$status_file" "Agent did not write status.json"
    fi

    # Validate status.json before using it (fail fast on malformed JSON)
    if ! validate_status "$status_file"; then
      echo "Warning: Invalid status.json - creating error status" >&2
      create_error_status "$status_file" "Agent wrote invalid status.json"
    fi

    # Extract status data for state history
    local history_json=$(status_to_history_json "$status_file")

    # Update state - mark iteration completed with status data
    # Pass stage name for multi-stage plateau filtering
    update_iteration "$state_file" "$i" "$history_json" "$STAGE_NAME"
    mark_iteration_completed "$state_file" "$i"
    local iter_decision
    local iter_reason
    iter_decision=$(get_status_decision "$status_file")
    iter_reason=$(get_status_reason "$status_file")
    local iter_complete_data
    iter_complete_data=$(jq -n \
      --arg status "$status_file" \
      --arg decision "$iter_decision" \
      --arg reason "$iter_reason" \
      '{status_file: $status, decision: $decision, reason: $reason}')
    emit_event_or_warn "iteration_complete" "$session" "$iter_cursor" "$iter_complete_data" || true

    # Post-iteration completion check (v3: pass status file path)
    if check_completion "$session" "$state_file" "$status_file"; then
      local reason=$(check_completion "$session" "$state_file" "$status_file" 2>&1)
      echo ""
      echo "$reason"
      mark_complete "$state_file" "$reason"
      local complete_cursor
      complete_cursor=$(build_event_cursor "$stage_idx" "$i" "$i")
      local node_complete_data
      node_complete_data=$(jq -n \
        --arg name "$STAGE_NAME" \
        --arg reason "$reason" \
        '{name: $name, status: "complete", reason: $reason}')
      emit_event_or_warn "node_complete" "$session" "$complete_cursor" "$node_complete_data" || true
      local session_complete_data
      session_complete_data=$(jq -n --arg reason "$reason" '{reason: $reason}')
      emit_event_or_warn "session_complete" "$session" "$complete_cursor" "$session_complete_data" || true
      record_completion "complete" "$session" "$stage_type"
      return 0
    fi

    # Check for explicit completion signal (legacy support)
    if type check_output_signal &>/dev/null && check_output_signal "$output"; then
      echo ""
      echo "Completion signal received"
      mark_complete "$state_file" "completion_signal"
      local complete_cursor
      complete_cursor=$(build_event_cursor "$stage_idx" "$i" "$i")
      local node_complete_data
      node_complete_data=$(jq -n \
        --arg name "$STAGE_NAME" \
        --arg reason "completion_signal" \
        '{name: $name, status: "complete", reason: $reason}')
      emit_event_or_warn "node_complete" "$session" "$complete_cursor" "$node_complete_data" || true
      local session_complete_data
      session_complete_data=$(jq -n --arg reason "completion_signal" '{reason: $reason}')
      emit_event_or_warn "session_complete" "$session" "$complete_cursor" "$session_complete_data" || true
      record_completion "complete" "$session" "$stage_type"
      return 0
    fi

    echo ""
    echo "Waiting ${STAGE_DELAY} seconds..."
    sleep "$STAGE_DELAY"
  done

  echo ""
  echo "Maximum iterations ($max_iterations) reached"
  mark_complete "$state_file" "max_iterations"
  local complete_cursor
  complete_cursor=$(build_event_cursor "$stage_idx" "$max_iterations" "$max_iterations")
  local node_complete_data
  node_complete_data=$(jq -n \
    --arg name "$STAGE_NAME" \
    --arg reason "max_iterations" \
    '{name: $name, status: "complete", reason: $reason}')
  emit_event_or_warn "node_complete" "$session" "$complete_cursor" "$node_complete_data" || true
  local session_complete_data
  session_complete_data=$(jq -n --arg reason "max_iterations" '{reason: $reason}')
  emit_event_or_warn "session_complete" "$session" "$complete_cursor" "$session_complete_data" || true
  record_completion "max_iterations" "$session" "$stage_type"
  return 1
}

#-------------------------------------------------------------------------------
# Initial Inputs
#-------------------------------------------------------------------------------

# Resolve initial input paths (files, globs, directories) to absolute paths
# Usage: resolve_initial_inputs "$inputs_json"
# Returns: JSON array of absolute file paths
resolve_initial_inputs() {
  local inputs_json=$1

  # Handle empty or null inputs
  if [ -z "$inputs_json" ] || [ "$inputs_json" = "null" ] || [ "$inputs_json" = "[]" ]; then
    echo "[]"
    return
  fi

  local resolved_files=()

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    # Make path absolute if relative
    local abs_pattern="$pattern"
    [[ "$pattern" != /* ]] && abs_pattern="$PROJECT_ROOT/$pattern"

    if [ -d "$abs_pattern" ]; then
      # Directory: expand to all files (md, yaml, json, txt)
      while IFS= read -r f; do
        [ -n "$f" ] && resolved_files+=("$f")
      done < <(find "$abs_pattern" -type f \( -name "*.md" -o -name "*.yaml" -o -name "*.json" -o -name "*.txt" \) 2>/dev/null | sort)
    elif [[ "$abs_pattern" == *"*"* ]]; then
      # Glob: expand pattern
      for f in $abs_pattern; do
        [ -f "$f" ] && resolved_files+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
      done
    elif [ -f "$abs_pattern" ]; then
      # Single file
      resolved_files+=("$(cd "$(dirname "$abs_pattern")" && pwd)/$(basename "$abs_pattern")")
    fi
  done < <(echo "$inputs_json" | jq -r '.[]' 2>/dev/null)

  # Output as JSON array
  if [ ${#resolved_files[@]} -eq 0 ]; then
    echo "[]"
  else
    printf '%s\n' "${resolved_files[@]}" | jq -R . | jq -s .
  fi
}

#-------------------------------------------------------------------------------
# Plan.json Helpers
#-------------------------------------------------------------------------------

validate_plan_file() {
  local plan_file=$1

  [ -f "$plan_file" ] || return 1

  jq -e '
    .version == 1
    and (.nodes | type == "array")
    and (.dependencies.jq == true)
    and (.dependencies.yq == true)
    and (.session.name | length > 0)
    and (.nodes | all(.path != null and .id != null and .kind != null))
  ' "$plan_file" >/dev/null 2>&1
}

plan_needs_recompile() {
  local pipeline_file=$1
  local plan_file=$2
  local force_recompile=${3:-""}

  if [ "$force_recompile" = "--recompile" ]; then
    return 0
  fi

  if [ ! -f "$plan_file" ]; then
    return 0
  fi

  if [ -f "$pipeline_file" ] && [ "$pipeline_file" -nt "$plan_file" ]; then
    return 0
  fi

  if ! validate_plan_file "$plan_file"; then
    return 0
  fi

  return 1
}

compile_plan_file() {
  local pipeline_file=$1
  local session_name=$2
  local run_dir=$3
  local compile_script="$LIB_DIR/compile.sh"

  if [ ! -f "$compile_script" ]; then
    echo "Error: compile.sh not found at $compile_script" >&2
    return 1
  fi

  bash "$compile_script" "$pipeline_file" "$session_name" "$run_dir"
}

resolve_plan_prompt() {
  local prompt_inline=$1
  local prompt_path=$2

  if [ -n "$prompt_inline" ] && [ "$prompt_inline" != "null" ]; then
    echo "$prompt_inline"
    return 0
  fi

  if [ -z "$prompt_path" ] || [ "$prompt_path" = "null" ]; then
    return 1
  fi

  local resolved="$prompt_path"
  if [[ "$resolved" != /* ]]; then
    resolved="$PROJECT_ROOT/$resolved"
  fi

  if [ ! -f "$resolved" ]; then
    echo "Error: Prompt file not found: $resolved" >&2
    return 1
  fi

  cat "$resolved"
}

#-------------------------------------------------------------------------------
# Pipeline Mode
#-------------------------------------------------------------------------------

run_pipeline() {
  local pipeline_file=$1
  local session_override=$2
  local start_stage=${3:-0}
  local start_iteration=${4:-1}

  # Resolve pipeline file
  if [ ! -f "$pipeline_file" ]; then
    if [ -f ".claude/pipelines/${pipeline_file}" ]; then
      pipeline_file=".claude/pipelines/${pipeline_file}"
    elif [ -f ".claude/pipelines/${pipeline_file}.yaml" ]; then
      pipeline_file=".claude/pipelines/${pipeline_file}.yaml"
    elif [ -f "$SCRIPT_DIR/pipelines/${pipeline_file}" ]; then
      pipeline_file="$SCRIPT_DIR/pipelines/${pipeline_file}"
    elif [ -f "$SCRIPT_DIR/pipelines/${pipeline_file}.yaml" ]; then
      pipeline_file="$SCRIPT_DIR/pipelines/${pipeline_file}.yaml"
    else
      echo "Error: Pipeline not found: $pipeline_file" >&2
      exit 1
    fi
  fi

  local session=${session_override:-""}
  if [ -z "$session" ]; then
    local fallback_name
    fallback_name=$(basename "$pipeline_file" .yaml)
    session="${fallback_name}-$(date +%Y%m%d-%H%M%S)"
  fi

  # Set up run directory
  local run_dir="$PROJECT_ROOT/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  cp "$pipeline_file" "$run_dir/pipeline.yaml"

  local plan_file="$run_dir/plan.json"
  local recompile_flag="$RECOMPILE_FLAG"
  if [ -n "${PIPELINE_CLI_PROVIDER:-}" ] || [ -n "${PIPELINE_CLI_MODEL:-}" ]; then
    recompile_flag="--recompile"
  fi

  if plan_needs_recompile "$pipeline_file" "$plan_file" "$recompile_flag"; then
    echo "Compiling plan.json..."
    if ! compile_plan_file "$pipeline_file" "$session" "$run_dir"; then
      return 1
    fi
  fi

  if ! validate_plan_file "$plan_file"; then
    echo "Error: plan.json missing or invalid. Recompile required." >&2
    return 1
  fi

  local plan_json
  plan_json=$(cat "$plan_file")
  local pipeline_name=$(json_get "$plan_json" ".pipeline.name" "pipeline")
  local pipeline_desc=$(json_get "$plan_json" ".pipeline.description" "")
  local pipeline_inputs=$(echo "$plan_json" | jq -c '.pipeline.inputs // []')
  local pipeline_commands=$(echo "$plan_json" | jq -c '.pipeline.commands // {}')

  # Resolve and store initial inputs (v4: pipeline-level inputs)
  local initial_inputs="$pipeline_inputs"
  if [ -n "$PIPELINE_CLI_INPUTS" ]; then
    # Merge CLI inputs with plan inputs (CLI takes precedence if both exist)
    if [ "$initial_inputs" = "[]" ] || [ "$initial_inputs" = "null" ]; then
      initial_inputs="$PIPELINE_CLI_INPUTS"
    else
      initial_inputs=$(echo "$initial_inputs $PIPELINE_CLI_INPUTS" | jq -s 'add')
    fi
  fi
  local resolved_inputs=$(resolve_initial_inputs "$initial_inputs")
  echo "$resolved_inputs" > "$run_dir/initial-inputs.json"

  # Initialize state
  local state_file=$(init_state "$session" "pipeline" "$run_dir")

  local events_file
  events_file=$(events_file_path "$session")
  if [ ! -s "$events_file" ]; then
    local start_cursor
    start_cursor=$(build_event_cursor "0" 0 0)
    local start_data
    start_data=$(jq -n \
      --arg mode "pipeline" \
      --arg name "$pipeline_name" \
      --arg file "$pipeline_file" \
      '{mode: $mode, pipeline: $name, pipeline_file: $file}')
    emit_event_or_warn "session_start" "$session" "$start_cursor" "$start_data" || true
  fi

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Pipeline: $pipeline_name"
  echo "║  Session:  $session"
  echo "║  Run dir:  $run_dir"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Execute each stage
  local stage_count
  stage_count=$(echo "$plan_json" | jq -r '.nodes | length')

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    local node_json
    node_json=$(echo "$plan_json" | jq -c ".nodes[$stage_idx]")
    local node_kind
    node_kind=$(echo "$node_json" | jq -r '.kind // "stage"')
    local stage_name
    stage_name=$(echo "$node_json" | jq -r '.id // empty')
    [ -z "$stage_name" ] && stage_name="stage-$stage_idx"

    # Skip completed stages during resume
    if [ "$stage_idx" -lt "$start_stage" ]; then
      if is_stage_complete "$state_file" "$stage_idx"; then
        echo "  ⏭ Skipping completed stage: $stage_name"
        continue
      fi
    fi

    if [ "$node_kind" = "parallel" ]; then
      local block_config
      block_config=$(echo "$node_json" | jq -c '
        {
          name: .id,
          description: (.description // ""),
          inputs: (.inputs // {}),
          parallel: (
            {
              providers: (.providers // []),
              stages: [
                .stages[] | {
                  name: .id,
                  stage: (.ref // empty),
                  model: (.model // empty),
                  prompt: (.prompt // empty),
                  prompt_path: (.prompt_path // empty),
                  context: (.context // empty),
                  output_path: (.output_path // empty),
                  delay: (.delay // empty),
                  termination: (.termination // {}),
                  inputs: (.inputs // {})
                }
              ]
            }
            + (if .failure_mode? then {failure_mode: .failure_mode} else {} end)
          )
        }
      ')
      local defaults_json
      defaults_json=$(jq -n '{}')
      local block_needs_bd=""
      block_needs_bd=$(echo "$block_config" | jq -r '[.parallel.stages[]?.termination.type // empty] | any(. == "queue")')
      if [ "$block_needs_bd" = "true" ]; then
        check_deps --require-bd || return 1
      fi

      local block_cursor
      block_cursor=$(build_event_cursor "$stage_idx" 0 0)
      local block_data
      block_data=$(echo "$block_config" | jq -c --arg name "$stage_name" '
        {
          name: $name,
          kind: "parallel",
          providers: (.parallel.providers // []),
          stages: (.parallel.stages | map(.name))
        }')
      emit_event_or_warn "node_start" "$session" "$block_cursor" "$block_data" || true

      # Run parallel block
      if ! run_parallel_block "$stage_idx" "$block_config" "$defaults_json" "$state_file" "$run_dir" "$session"; then
        echo "Error: Parallel block '$stage_name' failed"
        local error_data
        error_data=$(jq -n \
          --arg message "Parallel block '$stage_name' failed" \
          --arg stage "$stage_name" \
          '{message: $message, stage: $stage}')
        emit_event_or_warn "error" "$session" "$block_cursor" "$error_data" || true
        mark_failed "$state_file" "Parallel block '$stage_name' failed" "parallel_block_failed"
        return 1
      fi

      update_stage "$state_file" "$stage_idx" "$stage_name" "complete"
      local block_complete_data
      block_complete_data=$(jq -n \
        --arg name "$stage_name" \
        '{name: $name, status: "complete"}')
      emit_event_or_warn "node_complete" "$session" "$block_cursor" "$block_complete_data" || true
      echo ""
      continue  # Skip to next stage
    fi

    local stage_type
    stage_type=$(echo "$node_json" | jq -r '.ref // empty')
    local stage_desc
    stage_desc=$(echo "$node_json" | jq -r '.description // empty')
    local stage_context
    stage_context=$(echo "$node_json" | jq -r '.context // empty')
    if [ -n "${PIPELINE_CLI_CONTEXT:-}" ]; then
      stage_context="$PIPELINE_CLI_CONTEXT"
    fi
    local stage_prompt_inline
    stage_prompt_inline=$(echo "$node_json" | jq -r '.prompt // empty')
    local stage_prompt_path
    stage_prompt_path=$(echo "$node_json" | jq -r '.prompt_path // empty')
    local stage_provider
    stage_provider=$(echo "$node_json" | jq -r '.provider.type // empty')
    local stage_model
    stage_model=$(echo "$node_json" | jq -r '.provider.model // empty')
    local term_type
    term_type=$(echo "$node_json" | jq -r '.termination.type // "fixed"')
    local stage_runs
    stage_runs=$(echo "$node_json" | jq -r '.termination.max // .termination.iterations // 1')
    local min_iters
    min_iters=$(echo "$node_json" | jq -r '.termination.min_iterations // 1')
    local consensus
    consensus=$(echo "$node_json" | jq -r '.termination.consensus // 2')
    local stage_inputs
    stage_inputs=$(echo "$node_json" | jq -c '.inputs // {}')

    [[ ! "$stage_runs" =~ ^[0-9]+$ ]] && stage_runs=1
    [[ ! "$min_iters" =~ ^[0-9]+$ ]] && min_iters=1
    [[ ! "$consensus" =~ ^[0-9]+$ ]] && consensus=2

    local stage_prompt=""
    if ! stage_prompt=$(resolve_plan_prompt "$stage_prompt_inline" "$stage_prompt_path"); then
      if [ -n "$stage_type" ]; then
        load_stage "$stage_type" || exit 1
        stage_prompt="$STAGE_PROMPT"
      else
        echo "Error: No prompt found for stage '$stage_name'" >&2
        return 1
      fi
    fi

    local stage_completion=""
    case "$term_type" in
      queue) stage_completion="beads-empty" ;;
      judgment) stage_completion="plateau" ;;
      fixed) stage_completion="fixed-n" ;;
      *) stage_completion="$term_type" ;;
    esac

    if [ "$stage_completion" = "beads-empty" ]; then
      check_deps --require-bd || return 1
    fi

    [ -z "$stage_provider" ] && stage_provider="claude"
    if [ -z "$stage_model" ]; then
      stage_model=$(get_default_model "$stage_provider")
    fi

    # Create stage output directory (v3 format: stage-00-name)
    local stage_dir="$run_dir/stage-$(printf '%02d' $stage_idx)-$stage_name"
    mkdir -p "$stage_dir"

    echo "┌──────────────────────────────────────────────────────────────"
    echo "│ Loop $((stage_idx + 1))/$stage_count: $stage_name"
    [ -n "$stage_desc" ] && echo "│ $stage_desc"
    [ -n "$stage_type" ] && echo "│ Using stage type: $stage_type"
    echo "│ Runs: $stage_runs | Model: $stage_model"
    echo "└──────────────────────────────────────────────────────────────"
    echo ""

    if [ "$stage_idx" -ne "$start_stage" ] || [ "$start_iteration" -le 1 ]; then
      local node_cursor
      node_cursor=$(build_event_cursor "$stage_idx" 0 0)
      local node_start_data
      node_start_data=$(jq -n \
        --arg name "$stage_name" \
        --arg type "$stage_type" \
        --arg provider "$stage_provider" \
        --arg model "$stage_model" \
        --argjson runs "$stage_runs" \
        '{name: $name, type: $type, provider: $provider, model: $model, runs: $runs}')
      emit_event_or_warn "node_start" "$session" "$node_cursor" "$node_start_data" || true
    fi

    update_stage "$state_file" "$stage_idx" "$stage_name" "running"

    # Reset iteration counters when starting a stage fresh (not resuming mid-stage)
    # This prevents stale iteration_completed from previous stage causing resume issues
    # See: docs/bug-investigation-2026-01-12-state-transition.md
    if [ "$stage_idx" -ne "$start_stage" ] || [ "$start_iteration" -le 1 ]; then
      reset_iteration_counters "$state_file"
    fi

    # Check provider is available (once per stage, not per iteration)
    check_provider "$stage_provider" || return 1

    # Initialize progress for this stage
    local progress_file=$(init_stage_progress "$stage_dir")
    local perspectives=""

    # Source completion strategy if specified
    if [ -n "$stage_completion" ]; then
      local completion_script="$LIB_DIR/completions/${stage_completion}.sh"
      [ -f "$completion_script" ] && source "$completion_script"
    fi

    export MIN_ITERATIONS="$min_iters"
    export CONSENSUS="$consensus"
    export MAX_ITERATIONS="$stage_runs"

    # Determine starting iteration for this stage
    local stage_start_iter=0
    if [ "$stage_idx" -eq "$start_stage" ] && [ "$start_iteration" -gt 1 ]; then
      stage_start_iter=$((start_iteration - 1))
      echo "  Resuming from iteration $start_iteration..."
    fi

    # Run iterations
    local iterations_run=0
    for run_idx in $(seq $stage_start_iter $((stage_runs - 1))); do
      local iteration=$((run_idx + 1))
      echo "  Iteration $iteration/$stage_runs..."
      iterations_run=$((iterations_run + 1))

      # Build stage config JSON for v3 context generation
      local stage_config_json=$(jq -n \
        --arg id "$stage_name" \
        --arg name "$stage_name" \
        --argjson index "$stage_idx" \
        --arg loop "$stage_type" \
        --argjson max_iterations "$stage_runs" \
        --argjson inputs "$stage_inputs" \
        --argjson commands "$pipeline_commands" \
        '{id: $id, name: $name, index: $index, loop: $loop, max_iterations: $max_iterations, inputs: $inputs, commands: $commands}')

      # Generate context.json for this iteration (v3)
      local context_file=$(generate_context "$session" "$iteration" "$stage_config_json" "$run_dir")
      local iter_dir="$(dirname "$context_file")"
      local status_file="$iter_dir/status.json"

      # Determine output file
      local output_file
      if [ "$stage_runs" -eq 1 ]; then
        output_file="$stage_dir/output.md"
      else
        output_file="$stage_dir/run-$run_idx.md"
      fi

      # Get perspective for this run
      local perspective=""
      if [ -n "$perspectives" ]; then
        perspective=$(echo "$perspectives" | jq -r ".[$run_idx] // empty" 2>/dev/null)
      fi

      # Build variables (v3: includes context file)
      local vars_json=$(jq -n \
        --arg session "$session" \
        --arg iteration "$iteration" \
        --arg index "$run_idx" \
        --arg perspective "$perspective" \
        --arg output "$output_file" \
        --arg progress "$progress_file" \
        --arg run_dir "$run_dir" \
        --arg stage_idx "$stage_idx" \
        --arg context_file "$context_file" \
        --arg status_file "$status_file" \
        --arg context "$stage_context" \
        '{session: $session, iteration: $iteration, index: $index, perspective: $perspective, output: $output, progress: $progress, run_dir: $run_dir, stage_idx: $stage_idx, context_file: $context_file, status_file: $status_file, context: $context}')

      # Resolve prompt
      local resolved_prompt=$(resolve_prompt "$stage_prompt" "$vars_json")

      # Track iteration start in state
      mark_iteration_started "$state_file" "$iteration"
      local iter_cursor
      iter_cursor=$(build_event_cursor "$stage_idx" "$iteration" "$((run_idx + 1))")
      local iter_start_data
      iter_start_data=$(jq -n \
        --arg stage "$stage_name" \
        --arg type "$stage_type" \
        --arg provider "$stage_provider" \
        --arg model "$stage_model" \
        '{stage: $stage, type: $type, provider: $provider, model: $model}')
      emit_event_or_warn "iteration_start" "$session" "$iter_cursor" "$iter_start_data" || true

      # Export status file path for mock mode (mock.sh needs to know where to write status)
      export MOCK_STATUS_FILE="$status_file"
      export MOCK_ITERATION="$iteration"

      # Execute agent
      set +e
      local output=$(execute_agent "$stage_provider" "$resolved_prompt" "$stage_model" "$output_file")
      local exit_code=$?
      set -e

      # Phase 5: Fail fast - no retries, immediate failure with clear state
      if [ $exit_code -ne 0 ]; then
        local error_msg="Claude process exited with code $exit_code during stage '$stage_name'"
        local error_cursor
        error_cursor=$(build_event_cursor "$stage_idx" "$iteration" "$((run_idx + 1))")
        local error_data
        error_data=$(jq -n \
          --arg message "$error_msg" \
          --argjson code "$exit_code" \
          --arg stage "$stage_name" \
          '{message: $message, exit_code: $code, stage: $stage}')
        emit_event_or_warn "error" "$session" "$error_cursor" "$error_data" || true

        # Write error status to iteration
        create_error_status "$status_file" "$error_msg"

        # Update state with structured failure info
        update_stage "$state_file" "$stage_idx" "$stage_name" "failed"
        mark_failed "$state_file" "$error_msg" "exit_code"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Pipeline failed during stage: $stage_name"
        echo "  Iteration: $iteration"
        echo "  Error: $error_msg"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "To resume: ./scripts/run.sh pipeline $pipeline_file $session --resume"
        echo ""

        return 1
      fi

      # Phase 3: Save output snapshot to iteration directory
      if [ -n "$output" ]; then
        echo "$output" > "$iter_dir/output.md"
      fi

      # Phase 3: Create error status if agent didn't write status.json
      if [ ! -f "$status_file" ]; then
        create_error_status "$status_file" "Agent did not write status.json"
      fi

      # Validate status.json before using it (fail fast on malformed JSON)
      if ! validate_status "$status_file"; then
        echo "Warning: Invalid status.json - creating error status" >&2
        create_error_status "$status_file" "Agent wrote invalid status.json"
      fi

      # Extract status data and update history (needed for plateau to work across stages)
      local history_json=$(status_to_history_json "$status_file")
      update_iteration "$state_file" "$iteration" "$history_json" "$stage_name"
      mark_iteration_completed "$state_file" "$iteration"
      local iter_decision
      local iter_reason
      iter_decision=$(get_status_decision "$status_file")
      iter_reason=$(get_status_reason "$status_file")
      local iter_complete_data
      iter_complete_data=$(jq -n \
        --arg status "$status_file" \
        --arg decision "$iter_decision" \
        --arg reason "$iter_reason" \
        '{status_file: $status, decision: $decision, reason: $reason}')
      emit_event_or_warn "iteration_complete" "$session" "$iter_cursor" "$iter_complete_data" || true

      # Check completion (v3: pass status file path)
      if [ -n "$stage_completion" ] && type check_completion &>/dev/null; then
        if check_completion "$session" "$state_file" "$status_file"; then
          echo "  ✓ Completion condition met after $iteration iterations"
          break
        fi
      fi

      # Skip delay between runs in mock mode for faster testing
      [ "$run_idx" -lt "$((stage_runs - 1))" ] && [ "$MOCK_MODE" != "true" ] && sleep 2
    done

    # Bug 3 fix: Validate that at least one iteration ran
    if [ "$iterations_run" -eq 0 ]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "  Error: Stage '$stage_name' completed zero iterations"
      echo "  This indicates a bug in the pipeline configuration or engine"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      local error_cursor
      error_cursor=$(build_event_cursor "$stage_idx" 0 0)
      local error_data
      error_data=$(jq -n \
        --arg message "Stage '$stage_name' completed zero iterations" \
        --arg stage "$stage_name" \
        '{message: $message, stage: $stage}')
      emit_event_or_warn "error" "$session" "$error_cursor" "$error_data" || true
      update_stage "$state_file" "$stage_idx" "$stage_name" "failed"
      mark_failed "$state_file" "Stage '$stage_name' completed zero iterations" "zero_iterations"
      return 1
    fi

    update_stage "$state_file" "$stage_idx" "$stage_name" "complete"
    local stage_complete_cursor
    stage_complete_cursor=$(event_cursor_from_state "$state_file")
    local stage_complete_data
    stage_complete_data=$(jq -n \
      --arg name "$stage_name" \
      '{name: $name, status: "complete"}')
    emit_event_or_warn "node_complete" "$session" "$stage_complete_cursor" "$stage_complete_data" || true
    echo ""
  done

  mark_complete "$state_file" "all_loops_complete"
  local session_complete_cursor
  session_complete_cursor=$(event_cursor_from_state "$state_file")
  local session_complete_data
  session_complete_data=$(jq -n --arg reason "all_loops_complete" '{reason: $reason}')
  emit_event_or_warn "session_complete" "$session" "$session_complete_cursor" "$session_complete_data" || true

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  PIPELINE COMPLETE                                           ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  Pipeline: $pipeline_name"
  echo "║  Session:  $session"
  echo "║  Loops:   $stage_count"
  echo "║  Output:   $run_dir"
  echo "╚══════════════════════════════════════════════════════════════╝"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Parse flags from remaining args
FORCE_FLAG=""
RESUME_FLAG=""
RECOMPILE_FLAG=""
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE_FLAG="--force" ;;
    --resume) RESUME_FLAG="--resume" ;;
    --recompile) RECOMPILE_FLAG="--recompile" ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

# Cleanup stale locks on startup
cleanup_stale_locks

# Helper function to get state file path for a session
# All sessions now use pipeline-runs directory
get_state_file_path() {
  local session=$1
  local run_dir="${PROJECT_ROOT}/.claude/pipeline-runs/$session"
  echo "$run_dir/state.json"
}

# Helper function to check for failed session and handle resume
check_failed_session() {
  local session=$1
  local state_file=$2
  local max_iterations=$3

  # Get session status
  local status=$(get_session_status "$session" "$state_file")

  case "$status" in
    completed)
      echo "Session '$session' is already complete."
      echo "$SESSION_STATUS_DETAILS"
      exit 0
      ;;
    active)
      echo "Error: Session '$session' is currently active."
      echo "$SESSION_STATUS_DETAILS"
      echo ""
      echo "Use --force to override if you're sure it's not running."
      exit 1
      ;;
    failed)
      if [ "$RESUME_FLAG" = "--resume" ]; then
        return 0  # Allow resume
      else
        show_crash_recovery_info "$session" "$state_file" "$max_iterations"
        exit 1
      fi
      ;;
    none)
      if [ "$RESUME_FLAG" = "--resume" ]; then
        echo "Error: Cannot resume - no previous session '$session' found."
        exit 1
      fi
      return 0  # New session
      ;;
  esac
}

case "$MODE" in
  pipeline)
    # Check for --single-stage flag (used by run.sh loop shortcut)
    SINGLE_STAGE=""
    if [ "$1" = "--single-stage" ]; then
      SINGLE_STAGE="true"
      shift
      STAGE_TYPE=${1:?"Usage: engine.sh pipeline --single-stage <stage-type> [session] [max]"}
      SESSION=${2:-"$STAGE_TYPE"}
      MAX_ITERATIONS=${3:-25}
    else
      PIPELINE_FILE=${1:?"Usage: engine.sh pipeline <pipeline.yaml> [session] [--force] [--resume] [--recompile]"}
      SESSION=$2
      # For pipelines, derive session name if not provided
      if [ -z "$SESSION" ]; then
        pipeline_json=$(yaml_to_json "$PIPELINE_FILE" 2>/dev/null || echo "{}")
        SESSION=$(json_get "$pipeline_json" ".name" "pipeline")-$(date +%Y%m%d-%H%M%S)
      fi
    fi

    # Validate session name for security (prevent path traversal, injection)
    if ! validate_session_name "$SESSION"; then
      exit 1
    fi

    # Determine run directory and state file for pipeline
    RUN_DIR="$PROJECT_ROOT/.claude/pipeline-runs/$SESSION"
    STATE_FILE="$RUN_DIR/state.json"

    # Check for existing/failed session (only if state file exists)
    if [ -f "$STATE_FILE" ]; then
      check_failed_session "$SESSION" "$STATE_FILE" "${MAX_ITERATIONS:-?}"
    fi

    # Determine start iteration and stage for resume
    START_ITERATION=1
    START_STAGE=0
    if [ "$RESUME_FLAG" = "--resume" ]; then
      if [ -f "$STATE_FILE" ]; then
        START_ITERATION=$(get_resume_iteration "$STATE_FILE")
        START_STAGE=$(get_resume_stage "$STATE_FILE")
        reset_for_resume "$STATE_FILE"
        if [ "$SINGLE_STAGE" = "true" ]; then
          echo "Resuming session '$SESSION' from iteration $START_ITERATION"
        else
          echo "Resuming session '$SESSION' from stage $((START_STAGE + 1)), iteration $START_ITERATION"
        fi
      else
        echo "Error: Cannot resume - no previous session '$SESSION' found."
        exit 1
      fi
    fi

    # Acquire lock before starting
    if ! acquire_lock "$SESSION" "$FORCE_FLAG"; then
      exit 1
    fi

    # Ensure lock is released on exit (success, error, or signal)
    trap 'release_lock "$SESSION"' EXIT

    if [ "$SINGLE_STAGE" = "true" ]; then
      # Single-stage pipeline: run the loop directly using run_stage
      mkdir -p "$RUN_DIR"
      run_stage "$STAGE_TYPE" "$SESSION" "$MAX_ITERATIONS" "$RUN_DIR" "0" "$START_ITERATION"
    else
      run_pipeline "$PIPELINE_FILE" "$SESSION" "$START_STAGE" "$START_ITERATION"
    fi
    ;;

  status)
    # Show status of a session
    SESSION=${1:?"Usage: engine.sh status <session>"}
    if ! validate_session_name "$SESSION"; then
      exit 1
    fi
    STATE_FILE=$(get_state_file_path "$SESSION")
    RUN_DIR="$PROJECT_ROOT/.claude/pipeline-runs/$SESSION"

    status=$(get_session_status "$SESSION" "$STATE_FILE")
    echo "Session: $SESSION"
    echo "Status: $status"
    echo "$SESSION_STATUS_DETAILS"
    echo "Run dir: $RUN_DIR"

    if [ "$status" = "failed" ]; then
      get_crash_info "$SESSION" "$STATE_FILE"
      echo ""
      echo "Last iteration started: $CRASH_LAST_ITERATION"
      echo "Last iteration completed: $CRASH_LAST_COMPLETED"
      [ -n "$CRASH_ERROR" ] && echo "Error: $CRASH_ERROR"
      echo ""
      echo "To resume: ./scripts/run.sh loop <type> $SESSION <max> --resume"
    fi
    ;;

  *)
    echo "Usage: engine.sh <pipeline|status> <args>"
    echo ""
    echo "Everything is a pipeline. Use run.sh for the user-friendly interface."
    echo ""
    echo "Modes:"
    echo "  pipeline <file.yaml> [session]              - Run a multi-stage pipeline"
    echo "  pipeline --single-stage <type> [session] [max] - Run a single-loop pipeline"
    echo "  status <session>                            - Check session status"
    echo ""
    echo "Options:"
    echo "  --force    Override existing session lock"
    echo "  --resume   Resume a failed/crashed session"
    echo "  --recompile  Regenerate plan.json before running"
    echo ""
    echo "All sessions run in: .claude/pipeline-runs/{session}/"
    exit 1
    ;;
esac
