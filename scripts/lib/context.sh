#!/bin/bash
# Context Manifest Generator (v3)
# Creates context.json for each iteration
#
# The context manifest replaces 9+ template variables with a single
# structured JSON file that agents can read for all session context.

# Calculate remaining runtime in seconds
# Usage: calculate_remaining_time "$run_dir" "$stage_config"
# Returns: remaining seconds, or -1 if no limit configured
calculate_remaining_time() {
  local run_dir=$1
  local stage_config=$2

  # Get max runtime from config (check guardrails.max_runtime_seconds first, then top-level)
  local max_runtime=$(echo "$stage_config" | jq -r '.guardrails.max_runtime_seconds // .max_runtime_seconds // -1')

  # If no limit configured, return -1
  if [ "$max_runtime" = "-1" ] || [ "$max_runtime" = "null" ] || [ -z "$max_runtime" ]; then
    echo "-1"
    return
  fi

  # Get started_at from state.json
  local state_file="$run_dir/state.json"
  if [ ! -f "$state_file" ]; then
    echo "$max_runtime"  # Full time if no state yet
    return
  fi

  local started_at=$(jq -r '.started_at // ""' "$state_file" 2>/dev/null)
  if [ -z "$started_at" ] || [ "$started_at" = "null" ]; then
    echo "$max_runtime"
    return
  fi

  # Calculate elapsed time (cross-platform: macOS uses -j -f, Linux uses -d)
  # Note: timestamps are in UTC (ISO 8601 with Z suffix)
  local started_epoch
  # macOS: parse UTC timestamp
  started_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" "+%s" 2>/dev/null)
  if [ -z "$started_epoch" ]; then
    # Linux fallback: -d handles ISO 8601 with Z suffix correctly
    started_epoch=$(date -d "$started_at" "+%s" 2>/dev/null)
  fi
  if [ -z "$started_epoch" ]; then
    # Can't parse date, return full time
    echo "$max_runtime"
    return
  fi

  local now_epoch=$(date -u "+%s")
  local elapsed=$((now_epoch - started_epoch))

  # Calculate remaining
  local remaining=$((max_runtime - elapsed))

  # Return 0 if negative (time exceeded)
  if [ "$remaining" -lt 0 ]; then
    echo "0"
  else
    echo "$remaining"
  fi
}

# Generate context.json for an iteration
# Usage: generate_context "$session" "$iteration" "$stage_config" "$run_dir"
# Returns: path to generated context.json
generate_context() {
  local session=$1
  local iteration=$2
  local stage_config=$3  # JSON object
  local run_dir=$4

  # Extract stage info from config
  local stage_id=$(echo "$stage_config" | jq -r '.id // .name // "default"')
  local stage_idx=$(echo "$stage_config" | jq -r '.index // 0')
  local stage_template=$(echo "$stage_config" | jq -r '.template // .loop // ""')

  # Determine paths
  local stage_dir="$run_dir/stage-$(printf '%02d' $stage_idx)-$stage_id"
  local iter_dir="$stage_dir/iterations/$(printf '%03d' $iteration)"
  # Progress file: check stage-level first, fall back to session-level for backward compatibility
  local progress_file="$stage_dir/progress.md"
  if [ ! -f "$progress_file" ] && [ -f "$run_dir/progress-${session}.md" ]; then
    progress_file="$run_dir/progress-${session}.md"
  fi
  local output_file="$stage_dir/output.md"
  local status_file="$iter_dir/status.json"

  # Ensure directories exist
  mkdir -p "$iter_dir"

  # Build inputs JSON (from previous stage and previous iterations)
  local inputs_json=$(build_inputs_json "$run_dir" "$stage_config" "$iteration")

  # Get limits from stage config
  local max_iterations=$(echo "$stage_config" | jq -r '.max_iterations // 50')
  local remaining_seconds=$(calculate_remaining_time "$run_dir" "$stage_config")

  # Read pipeline name from state if available
  local pipeline=""
  if [ -f "$run_dir/state.json" ]; then
    pipeline=$(jq -r '.pipeline // .type // ""' "$run_dir/state.json" 2>/dev/null)
  fi

  # Extract commands from stage config (for test, build, lint, etc.)
  local commands_json=$(echo "$stage_config" | jq '.commands // {}')

  # Generate context.json
  jq -n \
    --arg session "$session" \
    --arg pipeline "$pipeline" \
    --arg stage_id "$stage_id" \
    --argjson stage_idx "$stage_idx" \
    --arg template "$stage_template" \
    --argjson iteration "$iteration" \
    --arg session_dir "$run_dir" \
    --arg stage_dir "$stage_dir" \
    --arg progress "$progress_file" \
    --arg output "$output_file" \
    --arg status "$status_file" \
    --argjson inputs "$inputs_json" \
    --argjson max_iterations "$max_iterations" \
    --argjson remaining "$remaining_seconds" \
    --argjson commands "$commands_json" \
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
    }' > "$iter_dir/context.json"

  echo "$iter_dir/context.json"
}

# Build inputs JSON based on pipeline config and previous iterations
# Usage: build_inputs_json "$run_dir" "$stage_config" "$iteration"
# Supports parallel_scope for provider isolation within parallel blocks
build_inputs_json() {
  local run_dir=$1
  local stage_config=$2
  local iteration=$3

  # Get inputs configuration
  local inputs_from=$(echo "$stage_config" | jq -r '.inputs.from // ""')
  local inputs_select=$(echo "$stage_config" | jq -r '.inputs.select // "latest"')

  # Check for parallel scope (for provider isolation)
  local scope_root=$(echo "$stage_config" | jq -r '.parallel_scope.scope_root // ""')
  local pipeline_root=$(echo "$stage_config" | jq -r '.parallel_scope.pipeline_root // ""')

  local from_stage="{}"
  local from_iterations="[]"
  local from_parallel="{}"

  # Collect from previous stage if specified
  if [ -n "$inputs_from" ] && [ "$inputs_from" != "null" ]; then
    local source_dir=""

    # When in parallel scope, look in scope_root first, then fall back to pipeline_root
    if [ -n "$scope_root" ]; then
      source_dir=$(find "$scope_root" -maxdepth 1 -type d -name "stage-*-$inputs_from" 2>/dev/null | head -1)
      # Fall back to pipeline_root if not found in scope_root
      if [ -z "$source_dir" ] && [ -n "$pipeline_root" ]; then
        source_dir=$(find "$pipeline_root" -maxdepth 1 -type d -name "stage-*-$inputs_from" 2>/dev/null | head -1)
      fi
    else
      source_dir=$(find "$run_dir" -maxdepth 1 -type d -name "stage-*-$inputs_from" 2>/dev/null | head -1)
    fi

    if [ -d "$source_dir" ]; then
      case "$inputs_select" in
        all)
          # Get all iteration outputs as array of file paths
          local files=()
          while IFS= read -r file; do
            [ -n "$file" ] && files+=("$file")
          done < <(find "$source_dir/iterations" -name "output.md" -type f 2>/dev/null | sort)

          if [ ${#files[@]} -gt 0 ]; then
            from_stage=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s --arg name "$inputs_from" '{($name): .}')
          else
            from_stage=$(jq -n --arg name "$inputs_from" '{($name): []}')
          fi
          ;;
        latest|*)
          # Get only the latest output
          local latest=$(ls -1 "$source_dir/iterations" 2>/dev/null | sort -n | tail -1)
          if [ -n "$latest" ] && [ -f "$source_dir/iterations/$latest/output.md" ]; then
            from_stage=$(jq -n --arg name "$inputs_from" \
              --arg file "$source_dir/iterations/$latest/output.md" \
              '{($name): [$file]}')
          else
            from_stage=$(jq -n --arg name "$inputs_from" '{($name): []}')
          fi
          ;;
      esac
    fi
  fi

  # Handle from_parallel inputs
  local from_parallel_config=$(echo "$stage_config" | jq -c '.inputs.from_parallel // null')
  if [ "$from_parallel_config" != "null" ] && [ -n "$from_parallel_config" ]; then
    from_parallel=$(build_from_parallel_inputs "$stage_config" "$run_dir")
  fi

  # Collect from previous iterations of current stage
  local stage_idx=$(echo "$stage_config" | jq -r '.index // 0')
  local stage_id=$(echo "$stage_config" | jq -r '.id // .name // "default"')
  local current_stage_dir="$run_dir/stage-$(printf '%02d' $stage_idx)-$stage_id"

  if [ "$iteration" -gt 1 ] && [ -d "$current_stage_dir/iterations" ]; then
    local iter_files=()
    for ((i=1; i<iteration; i++)); do
      local iter_output="$current_stage_dir/iterations/$(printf '%03d' $i)/output.md"
      [ -f "$iter_output" ] && iter_files+=("$iter_output")
    done

    if [ ${#iter_files[@]} -gt 0 ]; then
      from_iterations=$(printf '%s\n' "${iter_files[@]}" | jq -R . | jq -s .)
    fi
  fi

  # Load initial inputs from plan.json session.inputs
  local from_initial="[]"
  local plan_file="$run_dir/plan.json"
  if [ -f "$plan_file" ]; then
    from_initial=$(jq -c '.session.inputs // []' "$plan_file" 2>/dev/null || echo "[]")
    # Validate it's valid JSON array
    if ! echo "$from_initial" | jq -e 'type == "array"' >/dev/null 2>&1; then
      from_initial="[]"
    fi
  fi

  # Combine into inputs object
  # Include from_parallel only if it has content
  if [ "$from_parallel" != "{}" ] && [ -n "$from_parallel" ]; then
    jq -n \
      --argjson from_stage "$from_stage" \
      --argjson from_iterations "$from_iterations" \
      --argjson from_initial "$from_initial" \
      --argjson from_parallel "$from_parallel" \
      '{from_stage: $from_stage, from_previous_iterations: $from_iterations, from_initial: $from_initial, from_parallel: $from_parallel}'
  else
    jq -n \
      --argjson from_stage "$from_stage" \
      --argjson from_iterations "$from_iterations" \
      --argjson from_initial "$from_initial" \
      '{from_stage: $from_stage, from_previous_iterations: $from_iterations, from_initial: $from_initial}'
  fi
}

# Build from_parallel inputs based on manifest from a parallel block
# Usage: build_from_parallel_inputs "$stage_config" "$run_dir"
# Returns: JSON object with providers and their outputs
build_from_parallel_inputs() {
  local stage_config=$1
  local run_dir=$2

  # Parse from_parallel configuration
  # Can be shorthand string (stage name) or full object
  local from_parallel_config=$(echo "$stage_config" | jq -c '.inputs.from_parallel')

  local stage_name=""
  local block_name=""
  local select_mode="latest"
  local providers_filter="all"

  # Handle shorthand string vs full object
  if echo "$from_parallel_config" | jq -e 'type == "string"' >/dev/null 2>&1; then
    # Shorthand: just the stage name
    stage_name=$(echo "$from_parallel_config" | jq -r '.')
  else
    # Full object
    stage_name=$(echo "$from_parallel_config" | jq -r '.stage // ""')
    block_name=$(echo "$from_parallel_config" | jq -r '.block // ""')
    select_mode=$(echo "$from_parallel_config" | jq -r '.select // "latest"')
    providers_filter=$(echo "$from_parallel_config" | jq -c '.providers // "all"')
  fi

  # Find manifest path from parallel_blocks config
  local manifest_path=""
  if [ -n "$block_name" ]; then
    manifest_path=$(echo "$stage_config" | jq -r ".parallel_blocks[\"$block_name\"].manifest_path // \"\"")
  else
    # Try to find the most recent parallel block
    manifest_path=$(echo "$stage_config" | jq -r '.parallel_blocks | to_entries | .[0].value.manifest_path // ""')
  fi

  if [ -z "$manifest_path" ] || [ ! -f "$manifest_path" ]; then
    # Return empty if no manifest found
    echo "{}"
    return
  fi

  # Read manifest
  local manifest=$(cat "$manifest_path" 2>/dev/null || echo "{}")

  # Get block info
  local block_name_from_manifest=$(echo "$manifest" | jq -r '.block.name // "unknown"')

  # Build providers output
  local providers_json="{}"
  local all_providers=$(echo "$manifest" | jq -r '.providers | keys[]' 2>/dev/null)

  for provider in $all_providers; do
    # Check if provider is in the filter
    local include_provider=true
    if [ "$providers_filter" != "all" ] && echo "$providers_filter" | jq -e 'type == "array"' >/dev/null 2>&1; then
      if ! echo "$providers_filter" | jq -e "contains([\"$provider\"])" >/dev/null 2>&1; then
        include_provider=false
      fi
    fi

    if [ "$include_provider" = true ]; then
      # Get stage data for this provider
      local stage_data=$(echo "$manifest" | jq -c ".providers[\"$provider\"][\"$stage_name\"] // {}")

      if [ "$stage_data" != "{}" ] && [ -n "$stage_data" ]; then
        local output=$(echo "$stage_data" | jq -r '.latest_output // ""')
        local status=$(echo "$stage_data" | jq -r '.status // ""')
        local iterations=$(echo "$stage_data" | jq -r '.iterations // 0')
        local term_reason=$(echo "$stage_data" | jq -r '.termination_reason // ""')
        local history=$(echo "$stage_data" | jq -c '.history // []')

        local provider_entry
        if [ "$select_mode" = "history" ]; then
          provider_entry=$(jq -n \
            --arg output "$output" \
            --arg status "$status" \
            --argjson iterations "$iterations" \
            --arg term_reason "$term_reason" \
            --argjson history "$history" \
            '{output: $output, status: $status, iterations: $iterations, termination_reason: $term_reason, history: $history}')
        else
          provider_entry=$(jq -n \
            --arg output "$output" \
            --arg status "$status" \
            --argjson iterations "$iterations" \
            --arg term_reason "$term_reason" \
            '{output: $output, status: $status, iterations: $iterations, termination_reason: $term_reason}')
        fi

        providers_json=$(echo "$providers_json" | jq --arg p "$provider" --argjson data "$provider_entry" '. + {($p): $data}')
      fi
    fi
  done

  # Build final from_parallel object
  jq -n \
    --arg stage "$stage_name" \
    --arg block "$block_name_from_manifest" \
    --arg select "$select_mode" \
    --arg manifest "$manifest_path" \
    --argjson providers "$providers_json" \
    '{stage: $stage, block: $block, select: $select, manifest: $manifest, providers: $providers}'
}
