#!/bin/bash
# Parallel Block Execution for Agent Pipelines
#
# Provides functions for running parallel blocks with multiple providers.
# Each provider runs stages sequentially in isolation, providers run concurrently.
#
# Functions:
#   run_parallel_provider - Run stages for a single provider (called in subshell)
#   run_parallel_block - Orchestrate parallel providers, wait, build manifest
#
# Dependencies: state.sh, context.sh, provider.sh, result.sh, resolve.sh, progress.sh

PARALLEL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$PARALLEL_SCRIPT_DIR}"

if [ -f "$LIB_DIR/result.sh" ]; then
  source "$LIB_DIR/result.sh"
fi

if [ -f "$LIB_DIR/events.sh" ]; then
  source "$LIB_DIR/events.sh"
fi

if [ -f "$LIB_DIR/lock.sh" ]; then
  source "$LIB_DIR/lock.sh"
fi

#-------------------------------------------------------------------------------
# Parallel Event Helpers
#-------------------------------------------------------------------------------

parallel_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

parallel_int_or_default() {
  local value=$1
  local fallback=$2
  if parallel_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

parallel_build_cursor() {
  local node_path=$1
  local node_run=$2
  local iteration=$3
  local provider=${4:-""}

  if [ -z "$node_path" ] || [ "$node_path" = "null" ]; then
    echo "null"
    return 0
  fi

  node_run=$(parallel_int_or_default "$node_run" 1)
  iteration=$(parallel_int_or_default "$iteration" 0)

  if [ -n "$provider" ] && [ "$provider" != "null" ]; then
    jq -c -n \
      --arg path "$node_path" \
      --argjson run "$node_run" \
      --argjson iter "$iteration" \
      --arg provider "$provider" \
      '{node_path: $path, node_run: $run, iteration: $iter, provider: $provider}'
  else
    jq -c -n \
      --arg path "$node_path" \
      --argjson run "$node_run" \
      --argjson iter "$iteration" \
      '{node_path: $path, node_run: $run, iteration: $iter}'
  fi
}

parallel_emit_event() {
  local type=$1
  local session=$2
  local cursor_json=$3
  local data_json=${4:-"{}"}

  if [ "${EVENT_SPINE_ENABLED:-true}" != "true" ]; then
    return 0
  fi

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

parallel_events_json() {
  local session=$1

  if type read_events &>/dev/null; then
    read_events "$session" 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

parallel_provider_complete_from_events() {
  local events_json=$1
  local node_path=$2
  local provider=$3

  if [ -z "$events_json" ] || [ "$events_json" = "[]" ]; then
    return 1
  fi

  local match_count
  match_count=$(echo "$events_json" | jq \
    --arg path "$node_path" \
    --arg provider "$provider" \
    '[.[] | select(.type == "parallel_provider_complete" and .cursor.node_path == $path and .cursor.provider == $provider)] | length')
  [ "$match_count" -gt 0 ]
}

#-------------------------------------------------------------------------------
# Parallel Provider State Helpers
#-------------------------------------------------------------------------------

_parallel_update_provider_state() {
  local provider_state=$1
  shift

  local tmp_file="${provider_state}.tmp"
  if ! jq "$@" "$provider_state" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  mv "$tmp_file" "$provider_state"
}

#-------------------------------------------------------------------------------
# Parallel Provider Execution
#-------------------------------------------------------------------------------

# Run stages sequentially for a single provider within a parallel block
# Called in a subshell, one per provider
# Usage: run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults_json" "$node_path" "$node_run" "$provider_inputs" "$provider_model"
# Returns: 0 on success, 1 on failure
run_parallel_provider() {
  local provider=$1
  local block_dir=$2
  local stages_json=$3
  local session=$4
  local defaults_json=$5
  local node_path=${6:-"0"}
  local node_run=${7:-1}
  local provider_inputs=${8:-"{}"}
  local provider_model=${9:-""}

  local provider_dir="$block_dir/providers/$provider"
  local provider_state="$provider_dir/state.json"

  # Mark provider as running
  if type with_exclusive_file_lock &>/dev/null; then
    with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" '.status = "running"'
  else
    _parallel_update_provider_state "$provider_state" '.status = "running"'
  fi

  node_run=$(parallel_int_or_default "$node_run" 1)
  local provider_cursor
  provider_cursor=$(parallel_build_cursor "$node_path" "$node_run" 0 "$provider")
  local stage_names
  stage_names=$(echo "$stages_json" | jq -c '[.[].name]')
  parallel_emit_event "parallel_provider_start" "$session" "$provider_cursor" \
    "$(jq -n --arg provider "$provider" --argjson stages "$stage_names" '{provider: $provider, stages: $stages}')" || true

  local stage_count=$(echo "$stages_json" | jq 'length')
  # Provider-aware model: use explicit provider_model if set, otherwise get default for provider
  local default_model
  if [ -n "$provider_model" ] && [ "$provider_model" != "null" ]; then
    default_model="$provider_model"
  else
    default_model=$(get_default_model "$provider")
  fi

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    local stage_config=$(echo "$stages_json" | jq ".[$stage_idx]")
    local stage_name=$(echo "$stage_config" | jq -r '.name')
    local stage_type=$(echo "$stage_config" | jq -r '.stage // empty')
    local stage_model=$(echo "$stage_config" | jq -r ".model // \"$default_model\"")
    local stage_prompt_inline=$(echo "$stage_config" | jq -r '.prompt // empty')
    local stage_prompt_path=$(echo "$stage_config" | jq -r '.prompt_path // empty')
    local stage_context=$(echo "$stage_config" | jq -r '.context // empty')

    # Get termination config
    local term_type=$(echo "$stage_config" | jq -r '.termination.type // "fixed"')
    local max_iters=$(echo "$stage_config" | jq -r '.termination.iterations // .termination.max // 1')
    local consensus=$(echo "$stage_config" | jq -r '.termination.consensus // 2')
    local min_iters=$(echo "$stage_config" | jq -r '.termination.min_iterations // 1')

    # Create stage directory
    local stage_dir="$provider_dir/stage-$(printf '%02d' $stage_idx)-$stage_name"
    mkdir -p "$stage_dir"

    # Load prompt (plan-provided overrides stage.yaml)
    local stage_prompt=""
    if [ -n "$stage_prompt_inline" ] && [ "$stage_prompt_inline" != "null" ]; then
      stage_prompt="$stage_prompt_inline"
    elif [ -n "$stage_prompt_path" ] && [ "$stage_prompt_path" != "null" ]; then
      local resolved_prompt_path="$stage_prompt_path"
      if [[ "$resolved_prompt_path" != /* ]]; then
        resolved_prompt_path="$PROJECT_ROOT/$resolved_prompt_path"
      fi
      if [ -f "$resolved_prompt_path" ]; then
        stage_prompt=$(cat "$resolved_prompt_path")
      else
        echo "Error: Prompt file not found: $resolved_prompt_path" >&2
        return 1
      fi
    elif [ -n "$stage_type" ] && type load_stage &>/dev/null; then
      load_stage "$stage_type" || return 1
      stage_prompt="$STAGE_PROMPT"
    fi

    if [ -z "$stage_prompt" ]; then
      echo "Error: No prompt found for stage '$stage_name'" >&2
      parallel_emit_event "error" "$session" "$(parallel_build_cursor "$node_path" "$node_run" 0 "$provider")" \
        "$(jq -n --arg msg "No prompt found for stage '$stage_name'" --arg stage "$stage_name" '{message: $msg, stage: $stage}')" || true
      return 1
    fi

    # Initialize progress for this stage
    local progress_file="$provider_dir/progress.md"

    # Source completion strategy
    local completion_script=""
    case "$term_type" in
      queue) completion_script="${LIB_DIR:-scripts/lib}/completions/beads-empty.sh" ;;
      judgment) completion_script="${LIB_DIR:-scripts/lib}/completions/plateau.sh" ;;
      fixed) completion_script="${LIB_DIR:-scripts/lib}/completions/fixed-n.sh" ;;
    esac
    [ -f "$completion_script" ] && source "$completion_script"

    # Export for completion checks
    export MIN_ITERATIONS="$min_iters"
    export CONSENSUS="$consensus"
    export MAX_ITERATIONS="$max_iters"

    # Track stage history for plateau detection
    local stage_history="[]"

    for iter in $(seq 1 $max_iters); do
      local iter_dir="$stage_dir/iterations/$(printf '%03d' $iter)"
      mkdir -p "$iter_dir"

      # Build stage config for context generation with parallel_scope
      # Include provider-specific inputs if provided
      local ctx_config=$(jq -n \
        --arg id "$stage_name" \
        --arg name "$stage_name" \
        --argjson index "$stage_idx" \
        --arg loop "$stage_type" \
        --argjson max_iterations "$max_iters" \
        --arg scope_root "$provider_dir" \
        --arg pipeline_root "$(dirname "$block_dir")" \
        --argjson provider_inputs "$provider_inputs" \
        '{
          id: $id,
          name: $name,
          index: $index,
          loop: $loop,
          max_iterations: $max_iterations,
          parallel_scope: {
            scope_root: $scope_root,
            pipeline_root: $pipeline_root
          },
          inputs: $provider_inputs
        }')

      # Generate context.json
      local context_file
      if type generate_context &>/dev/null; then
        context_file=$(generate_context "$session" "$iter" "$ctx_config" "$provider_dir")
      else
        # Fallback: create basic context file
        context_file="$iter_dir/context.json"
        echo "$ctx_config" > "$context_file"
      fi
      local status_file="$iter_dir/status.json"
      local result_file="$iter_dir/result.json"

      # Build variables for prompt resolution
      local vars_json=$(jq -n \
        --arg session "$session" \
        --arg iteration "$iter" \
        --arg index "$((iter - 1))" \
        --arg progress "$progress_file" \
        --arg context_file "$context_file" \
        --arg status_file "$status_file" \
        --arg result_file "$result_file" \
        --arg context "$stage_context" \
        '{session: $session, iteration: $iteration, index: $index, progress: $progress, context_file: $context_file, status_file: $status_file, result_file: $result_file, context: $context}')

      # Resolve prompt
      local resolved_prompt=""
      if [ -n "$stage_prompt" ] && type resolve_prompt &>/dev/null; then
        resolved_prompt=$(resolve_prompt "$stage_prompt" "$vars_json")
      else
        resolved_prompt="$stage_prompt"
      fi

      # Update provider state
      if type with_exclusive_file_lock &>/dev/null; then
        with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" \
          --argjson iter "$iter" --arg stage "$stage_name" \
          '.iteration = $iter | .current_stage_name = $stage'
      else
        _parallel_update_provider_state "$provider_state" \
          --argjson iter "$iter" --arg stage "$stage_name" \
          '.iteration = $iter | .current_stage_name = $stage'
      fi

      local iter_cursor
      iter_cursor=$(parallel_build_cursor "$node_path" "$node_run" "$iter" "$provider")
      parallel_emit_event "iteration_start" "$session" "$iter_cursor" \
        "$(jq -n --arg stage "$stage_name" --arg ref "$stage_type" --arg provider "$provider" --arg model "$stage_model" \
          --argjson stage_index "$stage_idx" '{stage: $stage, ref: $ref, provider: $provider, model: $model, stage_index: $stage_index}')" || true

      # Export status file path for mock mode
      export MOCK_STATUS_FILE="$status_file"
      export MOCK_RESULT_FILE="$result_file"
      export MOCK_ITERATION="$iter"
      export MOCK_PROVIDER="$provider"

      # Export status file path for Codex watchdog (enables early termination on completion)
      export CODEX_STATUS_FILE="$status_file"

      # Execute agent
      local output=""
      local exit_code=0
      set +e
      if type execute_agent &>/dev/null; then
        output=$(execute_agent "$provider" "$resolved_prompt" "$stage_model")
        exit_code=$?
      else
        # Mock mode fallback for testing
        output="Mock output for $provider $stage_name iteration $iter"
        exit_code=0
      fi
      set -e

      if [ $exit_code -ne 0 ]; then
        if type with_exclusive_file_lock &>/dev/null; then
          with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" \
            --arg err "Exit code $exit_code" '.status = "failed" | .error = $err'
        else
          _parallel_update_provider_state "$provider_state" \
            --arg err "Exit code $exit_code" '.status = "failed" | .error = $err'
        fi
        parallel_emit_event "error" "$session" "$iter_cursor" \
          "$(jq -n --arg msg "Provider $provider exited with $exit_code" --argjson code "$exit_code" \
            --arg stage "$stage_name" '{message: $msg, exit_code: $code, stage: $stage}')" || true
        return 1
      fi

      # Save output
      [ -n "$output" ] && echo "$output" > "$iter_dir/output.md"

      if [ ! -f "$result_file" ] && [ -f "$status_file" ]; then
        local converted_result
        if converted_result=$(result_from_status "$status_file"); then
          result_write_atomic "$result_file" "$converted_result"
        fi
      fi

      # Create default result if not written
      if [ ! -f "$result_file" ]; then
        if type create_error_result &>/dev/null; then
          create_error_result "$result_file" "Agent did not write result.json"
        else
          # Fallback: minimal valid result
          echo '{"summary":"mock iteration","work":{"items_completed":[],"files_touched":[]},"artifacts":{"outputs":[],"paths":[]},"signals":{"plateau_suspected":false,"risk":"low","notes":""}}' > "$result_file"
        fi
      fi

      # Validate result
      if type validate_result &>/dev/null && ! validate_result "$result_file"; then
        create_error_result "$result_file" "Agent wrote invalid result.json"
      fi

      # Extract result for history and completion check
      local history_entry
      if type result_to_history_json &>/dev/null; then
        history_entry=$(result_to_history_json "$result_file")
      else
        history_entry=$(jq -c '{summary: .summary}' "$result_file" 2>/dev/null || echo '{"summary":"unknown"}')
      fi
      stage_history=$(echo "$stage_history" | jq --argjson entry "$history_entry" '. + [$entry]')

      # Update provider state iteration completed
      if type with_exclusive_file_lock &>/dev/null; then
        with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" \
          --argjson iter "$iter" '.iteration_completed = $iter'
      else
        _parallel_update_provider_state "$provider_state" \
          --argjson iter "$iter" '.iteration_completed = $iter'
      fi

      parallel_emit_event "worker_complete" "$session" "$iter_cursor" \
        "$(jq -n --arg result "$result_file" --argjson code "$exit_code" '{result_file: $result, exit_code: $code}')" || true

      local summary
      summary=$(jq -r '.summary // ""' "$result_file" 2>/dev/null || echo "")
      local signals
      signals=$(jq -c '.signals // {}' "$result_file" 2>/dev/null || echo "{}")
      parallel_emit_event "iteration_complete" "$session" "$iter_cursor" \
        "$(jq -n --arg result "$result_file" --arg summary "$summary" --argjson signals "$signals" \
          --arg stage "$stage_name" '{result_file: $result, summary: $summary, signals: $signals, stage: $stage}')" || true

      # Check completion (for judgment/plateau termination)
      if [ "$term_type" = "judgment" ]; then
        # Filter history for this stage only and check plateau
        local stage_history_count=$(echo "$stage_history" | jq 'length')
        if [ "$stage_history_count" -ge "$min_iters" ]; then
          local stop_count=$(echo "$stage_history" | jq '[.[] | select(.decision == "stop")] | length')
          local recent_stops=$(echo "$stage_history" | jq --argjson n "$consensus" '.[-($n):] | [.[] | select(.decision == "stop")] | length')
          if [ "$recent_stops" -ge "$consensus" ]; then
            break  # Plateau reached
          fi
        fi
      fi
    done

    # Record stage completion in provider state
    local term_reason="max_iterations"
    if [ "$term_type" = "judgment" ]; then
      local recent_stops=$(echo "$stage_history" | jq --argjson n "$consensus" '.[-($n):] | [.[] | select(.decision == "stop")] | length')
      [ "$recent_stops" -ge "$consensus" ] && term_reason="plateau"
    elif [ "$term_type" = "fixed" ]; then
      term_reason="fixed"
    fi

    local final_iter=$(jq -r '.iteration_completed // 0' "$provider_state")
    if type with_exclusive_file_lock &>/dev/null; then
      with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" \
        --arg name "$stage_name" --argjson iters "$final_iter" --arg reason "$term_reason" \
        '.stages += [{"name": $name, "iterations": $iters, "termination_reason": $reason}]'
    else
      _parallel_update_provider_state "$provider_state" \
        --arg name "$stage_name" --argjson iters "$final_iter" --arg reason "$term_reason" \
        '.stages += [{"name": $name, "iterations": $iters, "termination_reason": $reason}]'
    fi

    # Reset iteration counters for next stage
    if type with_exclusive_file_lock &>/dev/null; then
      with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" \
        '.iteration = 0 | .iteration_completed = 0'
    else
      _parallel_update_provider_state "$provider_state" \
        '.iteration = 0 | .iteration_completed = 0'
    fi
  done

  # Mark provider complete
  if type with_exclusive_file_lock &>/dev/null; then
    with_exclusive_file_lock "$provider_state" _parallel_update_provider_state "$provider_state" '.status = "complete"'
  else
    _parallel_update_provider_state "$provider_state" '.status = "complete"'
  fi

  parallel_emit_event "parallel_provider_complete" "$session" "$provider_cursor" \
    "$(jq -n --arg provider "$provider" --arg status "complete" '{provider: $provider, status: $status}')" || true

  return 0
}

#-------------------------------------------------------------------------------
# Parallel Block Orchestration
#-------------------------------------------------------------------------------

# Run a parallel block: spawn providers, wait for all, build manifest
# Usage: run_parallel_block "$stage_idx" "$block_config" "$defaults" "$state_file" "$run_dir" "$session"
# Returns: 0 on success, 1 on any provider failure
run_parallel_block() {
  local stage_idx=$1
  local block_config=$2
  local defaults=$3
  local state_file=$4
  local run_dir=$5
  local session=$6

  # Parse block config
  local block_name=$(echo "$block_config" | jq -r '.name // empty')
  local stages_json=$(echo "$block_config" | jq -c '.parallel.stages')
  local stage_names=$(echo "$stages_json" | jq -r '.[].name' | tr '\n' ' ')

  # Parse providers - can be strings ["claude", "codex"] or objects [{name: "claude", inputs: {...}}]
  # Normalize to get list of provider names
  local providers_json=$(echo "$block_config" | jq -c '.parallel.providers')
  local providers=""
  local first_provider_type=$(echo "$providers_json" | jq -r '.[0] | type')

  if [ "$first_provider_type" = "string" ]; then
    # Simple string array: ["claude", "codex"]
    providers=$(echo "$providers_json" | jq -r '.[]' | tr '\n' ' ')
  else
    # Object array: [{name: "claude", inputs: {...}}, ...]
    providers=$(echo "$providers_json" | jq -r '.[].name' | tr '\n' ' ')
  fi

  # Initialize block directory
  local block_dir
  if type init_parallel_block &>/dev/null; then
    block_dir=$(init_parallel_block "$run_dir" "$stage_idx" "$block_name" "$providers")
  else
    # Fallback: create manually
    local idx_fmt=$(printf '%02d' "$stage_idx")
    local block_dir_name="parallel-${idx_fmt}-${block_name:-block}"
    block_dir="$run_dir/$block_dir_name"
    mkdir -p "$block_dir"
    for p in $providers; do
      mkdir -p "$block_dir/providers/$p"
    done
  fi

  # Initialize provider states
  for provider in $providers; do
    if type init_provider_state &>/dev/null; then
      init_provider_state "$block_dir" "$provider" "$session"
    else
      # Fallback: create basic state
      mkdir -p "$block_dir/providers/$provider"
      echo '{"status": "pending", "stages": [], "iteration": 0, "iteration_completed": 0}' > "$block_dir/providers/$provider/state.json"
      echo "# Progress: $session ($provider)" > "$block_dir/providers/$provider/progress.md"
    fi
  done

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "running"
  fi

  echo ""
  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ Parallel Block: ${block_name:-parallel-$stage_idx}"
  echo "│ Providers: $providers"
  echo "│ Stages: $stage_names"
  echo "└──────────────────────────────────────────────────────────────"
  echo ""

  # Track provider PIDs for parallel execution (bash 3.x compatible)
  local all_pids=""
  local any_failed=false

  # Spawn subshell for each provider
  for provider in $providers; do
    # Extract provider-specific inputs and model (if using object format)
    local provider_inputs="{}"
    local provider_model=""
    if [ "$first_provider_type" != "string" ]; then
      provider_inputs=$(echo "$providers_json" | jq -c --arg p "$provider" '.[] | select(.name == $p) | .inputs // {}')
      [ -z "$provider_inputs" ] && provider_inputs="{}"
      provider_model=$(echo "$providers_json" | jq -r --arg p "$provider" '.[] | select(.name == $p) | .model // empty')
    fi
    # Debug: log provider inputs extraction
    [ -n "$DEBUG_PARALLEL" ] && echo "  [DEBUG] $provider provider_inputs: $provider_inputs, model: $provider_model" >&2

    (
      # Export necessary vars for subshell
      export MOCK_MODE MOCK_FIXTURES_DIR STAGES_DIR LIB_DIR PROJECT_ROOT

      # Re-source libraries in subshell (functions don't inherit)
      source "$LIB_DIR/yaml.sh"
      source "$LIB_DIR/state.sh"
      source "$LIB_DIR/progress.sh"
      source "$LIB_DIR/resolve.sh"
      source "$LIB_DIR/context.sh"
      source "$LIB_DIR/status.sh"
      source "$LIB_DIR/provider.sh"
      source "$LIB_DIR/stage.sh"
      source "$LIB_DIR/events.sh"
      [ "$MOCK_MODE" = true ] && [ -f "$LIB_DIR/mock.sh" ] && source "$LIB_DIR/mock.sh"

      # Debug: log what we're passing to run_parallel_provider
      [ -n "$DEBUG_PARALLEL" ] && echo "  [DEBUG] Calling run_parallel_provider with inputs: $provider_inputs, model: $provider_model" >&2

      # Run provider stages sequentially (pass provider-specific inputs and model)
      run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults" "$stage_idx" "1" "$provider_inputs" "$provider_model"
    ) &
    local pid=$!
    all_pids="$all_pids $pid"
    echo "  Started $provider (PID $pid)"
  done

  # Wait for all PIDs and check provider states
  local failed_providers=""
  for pid in $all_pids; do
    wait "$pid" || any_failed=true
  done

  # Check which providers succeeded/failed by reading their state files
  for provider in $providers; do
    local provider_state="$block_dir/providers/$provider/state.json"
    local status=$(jq -r '.status // "unknown"' "$provider_state" 2>/dev/null)
    if [ "$status" = "complete" ]; then
      echo "  ✓ $provider complete"
    else
      echo "  ✗ $provider failed"
      failed_providers="$failed_providers $provider"
      any_failed=true
    fi
  done

  # Handle failure
  if [ "$any_failed" = true ]; then
    echo ""
    echo "  Parallel block failed. Failed providers:$failed_providers"
    if type update_stage &>/dev/null; then
      update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "failed"
    fi
    return 1
  fi

  # Build manifest on success
  if type write_parallel_manifest &>/dev/null; then
    write_parallel_manifest "$block_dir" "${block_name:-parallel}" "$stage_idx" "$stage_names" "$providers"
  fi

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "complete"
  fi

  echo ""
  echo "  Parallel block complete. Manifest written to $block_dir/manifest.json"

  return 0
}

#-------------------------------------------------------------------------------
# Parallel Block Resume
#-------------------------------------------------------------------------------

# Resume a parallel block: skip completed providers, restart others
# Usage: run_parallel_block_resume "$stage_idx" "$block_config" "$defaults" "$state_file" "$run_dir" "$session" "$block_dir"
# Returns: 0 on success, 1 on any provider failure
run_parallel_block_resume() {
  local stage_idx=$1
  local block_config=$2
  local defaults=$3
  local state_file=$4
  local run_dir=$5
  local session=$6
  local block_dir=$7

  # Parse block config
  local block_name=$(echo "$block_config" | jq -r '.name // empty')
  local stages_json=$(echo "$block_config" | jq -c '.parallel.stages')
  local stage_names=$(echo "$stages_json" | jq -r '.[].name' | tr '\n' ' ')

  # Parse providers - can be strings or objects (same as run_parallel_block)
  local providers_json=$(echo "$block_config" | jq -c '.parallel.providers')
  local providers=""
  local first_provider_type=$(echo "$providers_json" | jq -r '.[0] | type')

  if [ "$first_provider_type" = "string" ]; then
    providers=$(echo "$providers_json" | jq -r '.[]' | tr '\n' ' ')
  else
    providers=$(echo "$providers_json" | jq -r '.[].name' | tr '\n' ' ')
  fi

  echo ""
  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ Resuming Parallel Block: ${block_name:-parallel-$stage_idx}"
  echo "│ Providers: $providers"
  echo "└──────────────────────────────────────────────────────────────"
  echo ""

  # Determine which providers need to run
  local providers_to_run=""
  local skipped_providers=""

  local events_json
  events_json=$(parallel_events_json "$session")

  for provider in $providers; do
    local provider_state="$block_dir/providers/$provider/state.json"
    local resume_hint=""
    local status_from_events=""

    if parallel_provider_complete_from_events "$events_json" "$stage_idx" "$provider"; then
      status_from_events="complete"
      if [ -f "$provider_state" ]; then
        jq '.status = "complete"' "$provider_state" > "$provider_state.tmp" && mv "$provider_state.tmp" "$provider_state"
      fi
    fi

    local status="pending"
    if [ -f "$provider_state" ]; then
      status=$(jq -r '.status // "pending"' "$provider_state")
    fi

    if [ -n "$status_from_events" ]; then
      status="$status_from_events"
    else
      if type get_parallel_resume_hint &>/dev/null; then
        resume_hint=$(get_parallel_resume_hint "$block_dir" "$provider")
      fi
      if [ -n "$resume_hint" ]; then
        local hint_status=$(echo "$resume_hint" | jq -r '.status // empty')
        [ -n "$hint_status" ] && status="$hint_status"
      fi
    fi

    if [ "$status" = "complete" ]; then
      skipped_providers="$skipped_providers $provider"
      echo "  ○ $provider (already complete, skipping)"
    else
      providers_to_run="$providers_to_run $provider"
      echo "  ● $provider (needs resume)"
    fi
  done

  # If all providers are complete, just build manifest and return
  if [ -z "$(echo "$providers_to_run" | tr -d ' ')" ]; then
    echo ""
    echo "  All providers already complete."
    if type write_parallel_manifest &>/dev/null; then
      write_parallel_manifest "$block_dir" "${block_name:-parallel}" "$stage_idx" "$stage_names" "$providers"
    fi
    if type update_stage &>/dev/null; then
      update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "complete"
    fi
    return 0
  fi

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "running"
  fi

  echo ""

  # Track provider PIDs for parallel execution (bash 3.x compatible)
  local all_pids=""
  local any_failed=false

  # Spawn subshell for each provider that needs to run
  for provider in $providers_to_run; do
    # Extract provider-specific inputs and model (if using object format)
    local provider_inputs="{}"
    local provider_model=""
    if [ "$first_provider_type" != "string" ]; then
      provider_inputs=$(echo "$providers_json" | jq -c --arg p "$provider" '.[] | select(.name == $p) | .inputs // {}')
      [ -z "$provider_inputs" ] && provider_inputs="{}"
      provider_model=$(echo "$providers_json" | jq -r --arg p "$provider" '.[] | select(.name == $p) | .model // empty')
    fi

    (
      # Export necessary vars for subshell
      export MOCK_MODE MOCK_FIXTURES_DIR STAGES_DIR LIB_DIR PROJECT_ROOT

      # Re-source libraries in subshell (functions don't inherit)
      source "$LIB_DIR/yaml.sh"
      source "$LIB_DIR/state.sh"
      source "$LIB_DIR/progress.sh"
      source "$LIB_DIR/resolve.sh"
      source "$LIB_DIR/context.sh"
      source "$LIB_DIR/status.sh"
      source "$LIB_DIR/provider.sh"
      source "$LIB_DIR/stage.sh"
      source "$LIB_DIR/events.sh"
      [ "$MOCK_MODE" = true ] && [ -f "$LIB_DIR/mock.sh" ] && source "$LIB_DIR/mock.sh"

      # Initialize provider state if needed
      if [ ! -f "$block_dir/providers/$provider/state.json" ]; then
        if type init_provider_state &>/dev/null; then
          init_provider_state "$block_dir" "$provider" "$session"
        fi
      fi

      # Run provider stages sequentially (pass provider-specific inputs and model)
      run_parallel_provider "$provider" "$block_dir" "$stages_json" "$session" "$defaults" "$stage_idx" "1" "$provider_inputs" "$provider_model"
    ) &
    local pid=$!
    all_pids="$all_pids $pid"
    echo "  Started $provider (PID $pid)"
  done

  # Wait for all PIDs and check provider states
  local failed_providers=""
  for pid in $all_pids; do
    wait "$pid" || any_failed=true
  done

  # Check which providers succeeded/failed
  for provider in $providers_to_run; do
    local provider_state="$block_dir/providers/$provider/state.json"
    local status=$(jq -r '.status // "unknown"' "$provider_state" 2>/dev/null)
    if [ "$status" = "complete" ]; then
      echo "  ✓ $provider complete"
    else
      echo "  ✗ $provider failed"
      failed_providers="$failed_providers $provider"
      any_failed=true
    fi
  done

  # Handle failure
  if [ "$any_failed" = true ]; then
    echo ""
    echo "  Parallel block resume failed. Failed providers:$failed_providers"
    if type update_stage &>/dev/null; then
      update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "failed"
    fi
    return 1
  fi

  # Build manifest on success (now includes both previously-complete and newly-complete providers)
  if type write_parallel_manifest &>/dev/null; then
    write_parallel_manifest "$block_dir" "${block_name:-parallel}" "$stage_idx" "$stage_names" "$providers"
  fi

  # Update pipeline state
  if type update_stage &>/dev/null; then
    update_stage "$state_file" "$stage_idx" "${block_name:-parallel-$stage_idx}" "complete"
  fi

  echo ""
  echo "  Parallel block resume complete. Manifest written to $block_dir/manifest.json"

  return 0
}

# Check if a parallel block can be resumed
# Usage: can_resume_parallel_block "$block_dir"
# Returns: 0 if resumable (has incomplete providers), 1 if not
can_resume_parallel_block() {
  local block_dir=$1

  if [ ! -d "$block_dir/providers" ]; then
    return 1
  fi

  local has_incomplete=false
  for provider_dir in "$block_dir/providers"/*; do
    [ -d "$provider_dir" ] || continue
    local provider_state="$provider_dir/state.json"
    if [ -f "$provider_state" ]; then
      local status=$(jq -r '.status // "pending"' "$provider_state")
      if [ "$status" != "complete" ]; then
        has_incomplete=true
        break
      fi
    else
      has_incomplete=true
      break
    fi
  done

  [ "$has_incomplete" = true ]
}

# Get resume status summary for a parallel block
# Usage: get_parallel_block_resume_status "$block_dir"
# Returns: JSON object with provider statuses
get_parallel_block_resume_status() {
  local block_dir=$1

  local result="{}"
  for provider_dir in "$block_dir/providers"/*; do
    [ -d "$provider_dir" ] || continue
    local provider=$(basename "$provider_dir")
    local provider_state="$provider_dir/state.json"

    local status="pending"
    local current_stage=0
    local iteration=0

    if [ -f "$provider_state" ]; then
      status=$(jq -r '.status // "pending"' "$provider_state")
      current_stage=$(jq -r '.current_stage // 0' "$provider_state")
      iteration=$(jq -r '.iteration_completed // 0' "$provider_state")
    fi

    result=$(echo "$result" | jq \
      --arg p "$provider" \
      --arg s "$status" \
      --argjson stage "$current_stage" \
      --argjson iter "$iteration" \
      '. + {($p): {status: $s, current_stage: $stage, iteration_completed: $iter}}')
  done

  echo "$result"
}

# Export functions for use in subshells
export -f run_parallel_provider run_parallel_block run_parallel_block_resume 2>/dev/null || true
