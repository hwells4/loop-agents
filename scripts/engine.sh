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

# Source mock library if MOCK_MODE is enabled (for testing)
if [ "$MOCK_MODE" = true ] && [ -f "$LIB_DIR/mock.sh" ]; then
  source "$LIB_DIR/mock.sh"
fi

# Export for hooks
export CLAUDE_PIPELINE_AGENT=1

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

    # Pre-iteration completion check
    if [ "$STAGE_CHECK_BEFORE" = "true" ]; then
      if check_completion "$session" "$state_file" ""; then
        local reason=$(check_completion "$session" "$state_file" "" 2>&1)
        echo "$reason"
        mark_complete "$state_file" "$reason"
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

    # Post-iteration completion check (v3: pass status file path)
    if check_completion "$session" "$state_file" "$status_file"; then
      local reason=$(check_completion "$session" "$state_file" "$status_file" 2>&1)
      echo ""
      echo "$reason"
      mark_complete "$state_file" "$reason"
      record_completion "complete" "$session" "$stage_type"
      return 0
    fi

    # Check for explicit completion signal (legacy support)
    if type check_output_signal &>/dev/null && check_output_signal "$output"; then
      echo ""
      echo "Completion signal received"
      mark_complete "$state_file" "completion_signal"
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

  # Validate pipeline before execution (Bug fix: loop-agents-otc)
  if ! validate_pipeline_file "$pipeline_file" "--quiet"; then
    local pipeline_name_for_error
    pipeline_name_for_error=$(basename "$pipeline_file" .yaml)
    echo "Error: Pipeline validation failed. Run './scripts/run.sh lint pipeline $pipeline_name_for_error' for details." >&2
    return 1
  fi

  # Parse pipeline
  local pipeline_json=$(yaml_to_json "$pipeline_file")
  local pipeline_name=$(json_get "$pipeline_json" ".name" "pipeline")
  local session=${session_override:-"${pipeline_name}-$(date +%Y%m%d-%H%M%S)"}

  # Set up run directory
  local run_dir="$PROJECT_ROOT/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  cp "$pipeline_file" "$run_dir/pipeline.yaml"

  # Resolve and store initial inputs (v4: pipeline-level inputs)
  local initial_inputs=$(json_get "$pipeline_json" ".inputs" "[]")
  # Also check for CLI-provided inputs (via PIPELINE_CLI_INPUTS env var)
  if [ -n "$PIPELINE_CLI_INPUTS" ]; then
    # Merge CLI inputs with YAML inputs (CLI takes precedence if both exist)
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

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Pipeline: $pipeline_name"
  echo "║  Session:  $session"
  echo "║  Run dir:  $run_dir"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Get defaults (CLI > env > pipeline config > built-in)
  # Resolve provider first (needed for model default)
  local default_provider=${PIPELINE_CLI_PROVIDER:-${CLAUDE_PIPELINE_PROVIDER:-$(json_get "$pipeline_json" ".defaults.provider" "claude")}}
  local provider_default_model=$(get_default_model "$default_provider")
  local default_model=${PIPELINE_CLI_MODEL:-${CLAUDE_PIPELINE_MODEL:-$(json_get "$pipeline_json" ".defaults.model" "$provider_default_model")}}

  # Execute each stage
  local stage_count=$(json_array_len "$pipeline_json" ".stages")

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    # Skip completed stages during resume
    if [ "$stage_idx" -lt "$start_stage" ]; then
      if is_stage_complete "$state_file" "$stage_idx"; then
        local skipped_name=$(json_get "$pipeline_json" ".stages[$stage_idx].name")
        echo "  ⏭ Skipping completed stage: $skipped_name"
        continue
      fi
    fi

    local stage_name=$(json_get "$pipeline_json" ".stages[$stage_idx].name")
    local stage_runs=$(json_get "$pipeline_json" ".stages[$stage_idx].runs" "1")
    local stage_model=$(json_get "$pipeline_json" ".stages[$stage_idx].model" "$default_model")
    local stage_provider=$(json_get "$pipeline_json" ".stages[$stage_idx].provider" "$default_provider")
    # Support both "stage" (new) and "loop" (legacy) keywords
    local stage_type=$(json_get "$pipeline_json" ".stages[$stage_idx].stage" "")
    [ -z "$stage_type" ] && stage_type=$(json_get "$pipeline_json" ".stages[$stage_idx].loop" "")
    local stage_prompt=$(json_get "$pipeline_json" ".stages[$stage_idx].prompt" "")
    local stage_completion=$(json_get "$pipeline_json" ".stages[$stage_idx].completion" "")
    local stage_desc=$(json_get "$pipeline_json" ".stages[$stage_idx].description" "")
    # v3: Get inputs configuration
    local stage_inputs_from=$(json_get "$pipeline_json" ".stages[$stage_idx].inputs.from" "")
    local stage_inputs_select=$(json_get "$pipeline_json" ".stages[$stage_idx].inputs.select" "latest")
    # v4: Get context injection (CLI > pipeline stage > stage.yaml)
    local stage_context=${PIPELINE_CLI_CONTEXT:-$(json_get "$pipeline_json" ".stages[$stage_idx].context" "")}

    # Check if this is a parallel block
    local is_parallel=$(echo "$pipeline_json" | jq -e ".stages[$stage_idx].parallel" 2>/dev/null)
    if [ -n "$is_parallel" ] && [ "$is_parallel" != "null" ]; then
      # Extract full stage config for parallel block
      local block_config=$(echo "$pipeline_json" | jq ".stages[$stage_idx]")
      local defaults_json=$(jq -n \
        --arg provider "$default_provider" \
        --arg model "$default_model" \
        '{provider: $provider, model: $model}')
      local block_needs_bd=""
      block_needs_bd=$(echo "$block_config" | jq -r '[.parallel.stages[]?.termination.type // empty] | any(. == "queue")')
      if [ "$block_needs_bd" = "true" ]; then
        check_deps --require-bd || return 1
      fi

      # Run parallel block
      if ! run_parallel_block "$stage_idx" "$block_config" "$defaults_json" "$state_file" "$run_dir" "$session"; then
        echo "Error: Parallel block '$stage_name' failed"
        mark_failed "$state_file" "Parallel block '$stage_name' failed" "parallel_block_failed"
        return 1
      fi

      update_stage "$state_file" "$stage_idx" "$stage_name" "complete"
      echo ""
      continue  # Skip to next stage
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

    update_stage "$state_file" "$stage_idx" "$stage_name" "running"

    # Reset iteration counters when starting a stage fresh (not resuming mid-stage)
    # This prevents stale iteration_completed from previous stage causing resume issues
    # See: docs/bug-investigation-2026-01-12-state-transition.md
    if [ "$stage_idx" -ne "$start_stage" ] || [ "$start_iteration" -le 1 ]; then
      reset_iteration_counters "$state_file"
    fi

    # If using a stage type, load its config
    if [ -n "$stage_type" ]; then
      load_stage "$stage_type" || exit 1
      [ -z "$stage_prompt" ] && stage_prompt="$STAGE_PROMPT"
      [ -z "$stage_completion" ] && stage_completion="$STAGE_COMPLETION"
      [ -z "$stage_context" ] && stage_context="$STAGE_CONTEXT"
    else
      # Bug fix: loop-agents-qnx - Inline prompt stages default to fixed-n termination
      [ -z "$stage_completion" ] && stage_completion="fixed-n"
    fi
    if [ "$stage_completion" = "beads-empty" ]; then
      check_deps --require-bd || return 1
    fi

    # Check provider is available (once per stage, not per iteration)
    check_provider "$stage_provider" || return 1

    # Initialize progress for this stage
    local progress_file=$(init_stage_progress "$stage_dir")

    # Get perspectives array
    local perspectives=$(json_get "$pipeline_json" ".stages[$stage_idx].perspectives" "")

    # Source completion strategy if specified
    if [ -n "$stage_completion" ]; then
      local completion_script="$LIB_DIR/completions/${stage_completion}.sh"
      [ -f "$completion_script" ] && source "$completion_script"
    fi

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
        --arg inputs_from "$stage_inputs_from" \
        --arg inputs_select "$stage_inputs_select" \
        '{id: $id, name: $name, index: $index, loop: $loop, max_iterations: $max_iterations, inputs: {from: $inputs_from, select: $inputs_select}}')

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
      update_stage "$state_file" "$stage_idx" "$stage_name" "failed"
      mark_failed "$state_file" "Stage '$stage_name' completed zero iterations" "zero_iterations"
      return 1
    fi

    update_stage "$state_file" "$stage_idx" "$stage_name" "complete"
    echo ""
  done

  mark_complete "$state_file" "all_loops_complete"

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
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE_FLAG="--force" ;;
    --resume) RESUME_FLAG="--resume" ;;
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
      PIPELINE_FILE=${1:?"Usage: engine.sh pipeline <pipeline.yaml> [session] [--force] [--resume]"}
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
    echo ""
    echo "All sessions run in: .claude/pipeline-runs/{session}/"
    exit 1
    ;;
esac
