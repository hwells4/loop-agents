#!/bin/bash
# Context Manifest Generator (v3)
# Creates context.json for each iteration
#
# The context manifest replaces 9+ template variables with a single
# structured JSON file that agents can read for all session context.

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

  # Get limits from stage config and state
  local max_iterations=$(echo "$stage_config" | jq -r '.max_iterations // 50')
  local started_at=""
  if [ -f "$run_dir/state.json" ]; then
    started_at=$(jq -r '.started_at // ""' "$run_dir/state.json" 2>/dev/null)
  fi
  local remaining_seconds=$(calculate_remaining_time "$started_at" "$stage_config")

  # Read pipeline name from state if available
  local pipeline=""
  if [ -f "$run_dir/state.json" ]; then
    pipeline=$(jq -r '.pipeline // .type // ""' "$run_dir/state.json" 2>/dev/null)
  fi

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
      }
    }' > "$iter_dir/context.json"

  echo "$iter_dir/context.json"
}

# Build inputs JSON based on pipeline config and previous iterations
# Usage: build_inputs_json "$run_dir" "$stage_config" "$iteration"
build_inputs_json() {
  local run_dir=$1
  local stage_config=$2
  local iteration=$3

  # Get inputs configuration
  local inputs_from=$(echo "$stage_config" | jq -r '.inputs.from // ""')
  local inputs_select=$(echo "$stage_config" | jq -r '.inputs.select // "latest"')

  local from_stage="{}"
  local from_iterations="[]"

  # Collect from previous stage if specified
  if [ -n "$inputs_from" ] && [ "$inputs_from" != "null" ]; then
    local source_dir=$(find "$run_dir" -maxdepth 1 -type d -name "stage-*-$inputs_from" 2>/dev/null | head -1)

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

  # Combine into inputs object
  jq -n \
    --argjson from_stage "$from_stage" \
    --argjson from_iterations "$from_iterations" \
    '{from_stage: $from_stage, from_previous_iterations: $from_iterations}'
}

# Calculate remaining runtime in seconds
# Usage: calculate_remaining_time "$started_at" "$stage_config"
# Returns: remaining seconds (or -1 if no limit)
calculate_remaining_time() {
  local started_at=$1
  local stage_config=$2

  # Get max runtime from config
  local max_runtime=$(echo "$stage_config" | jq -r '.guardrails.max_runtime_seconds // .max_runtime_seconds // ""')

  if [ -z "$max_runtime" ] || [ "$max_runtime" = "null" ]; then
    echo "-1"
    return
  fi

  if [ -z "$started_at" ] || [ "$started_at" = "null" ]; then
    echo "$max_runtime"
    return
  fi

  # Calculate elapsed time
  local now=$(date +%s)
  local start_epoch

  # Parse ISO 8601 timestamp to epoch
  if command -v gdate &>/dev/null; then
    start_epoch=$(gdate -d "$started_at" +%s 2>/dev/null || echo "0")
  else
    # macOS date or fallback
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || \
                  date -j -f "%Y-%m-%dT%H:%M:%S" "$started_at" +%s 2>/dev/null || \
                  echo "0")
  fi

  if [ "$start_epoch" -eq 0 ]; then
    echo "$max_runtime"
    return
  fi

  local elapsed=$((now - start_epoch))
  local remaining=$((max_runtime - elapsed))

  if [ "$remaining" -lt 0 ]; then
    echo "0"
  else
    echo "$remaining"
  fi
}
