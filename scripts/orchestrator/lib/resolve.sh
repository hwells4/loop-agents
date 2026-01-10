#!/bin/bash
# Variable Resolution for Pipeline Prompts
#
# Resolves variables in prompt templates:
#   ${SESSION}           - Pipeline session name
#   ${INDEX}             - Current run index (0-based)
#   ${PERSPECTIVE}       - Current perspective from array
#   ${OUTPUT}            - Path to write output
#   ${PROGRESS}          - Path to progress file (for multi-run stages)
#   ${INPUTS.stage-name} - Outputs from a previous stage
#   ${INPUTS}            - All outputs from previous stage (shorthand)

# Resolve all variables in a prompt template
resolve_prompt() {
  local template=$1
  local stage_idx=$2
  local run_idx=$3
  local perspective=$4
  local output_file=$5
  local progress_file=${6:-""}

  local resolved="$template"

  # Basic substitutions
  resolved=$(echo "$resolved" | sed "s|\${SESSION}|$SESSION_NAME|g")
  resolved=$(echo "$resolved" | sed "s|\${INDEX}|$run_idx|g")
  resolved=$(echo "$resolved" | sed "s|\${PERSPECTIVE}|$perspective|g")
  resolved=$(echo "$resolved" | sed "s|\${OUTPUT}|$output_file|g")

  if [ -n "$progress_file" ]; then
    resolved=$(echo "$resolved" | sed "s|\${PROGRESS}|$progress_file|g")
  fi

  # Resolve ${INPUTS.stage-name} references
  # Find all ${INPUTS.xxx} patterns
  while [[ "$resolved" =~ \$\{INPUTS\.([a-zA-Z0-9_-]+)\} ]]; do
    local ref_stage_name="${BASH_REMATCH[1]}"
    local inputs_content=$(resolve_stage_inputs "$ref_stage_name")

    # Escape special characters for sed
    local escaped_content=$(printf '%s\n' "$inputs_content" | sed 's/[&/\]/\\&/g')
    resolved=$(echo "$resolved" | sed "s|\${INPUTS\.$ref_stage_name}|$escaped_content|g")
  done

  # Resolve ${INPUTS} (previous stage shorthand)
  if [[ "$resolved" =~ \$\{INPUTS\} ]]; then
    if [ "$stage_idx" -gt 0 ]; then
      local prev_stage_name=$(get_stage_value "$((stage_idx - 1))" "name")
      local inputs_content=$(resolve_stage_inputs "$prev_stage_name")
      local escaped_content=$(printf '%s\n' "$inputs_content" | sed 's/[&/\]/\\&/g')
      resolved=$(echo "$resolved" | sed "s|\${INPUTS}|$escaped_content|g")
    fi
  fi

  echo "$resolved"
}

# Get outputs from a named stage
resolve_stage_inputs() {
  local stage_name=$1
  local result=""

  # Find the stage directory
  local stage_dir=$(find "$RUN_DIR" -maxdepth 1 -type d -name "stage-*-$stage_name" 2>/dev/null | head -1)

  if [ -z "$stage_dir" ] || [ ! -d "$stage_dir" ]; then
    echo "[No outputs found for stage: $stage_name]"
    return
  fi

  # Collect all output files
  local output_files=$(find "$stage_dir" -name "*.md" -type f | sort)

  if [ -z "$output_files" ]; then
    echo "[No output files in stage: $stage_name]"
    return
  fi

  # If single output, just return its content
  local file_count=$(echo "$output_files" | wc -l | tr -d ' ')

  if [ "$file_count" -eq 1 ]; then
    cat "$output_files"
    return
  fi

  # Multiple outputs - format them
  result="--- Outputs from stage: $stage_name ---"$'\n'

  for file in $output_files; do
    local filename=$(basename "$file")
    result="${result}"$'\n'"=== $filename ==="$'\n'
    result="${result}$(cat "$file")"$'\n'
  done

  echo "$result"
}

# Resolve inputs for prompt (shorthand for previous stage)
resolve_stage_inputs_for_prompt() {
  local stage_idx=$1

  if [ "$stage_idx" -gt 0 ]; then
    local prev_stage_name=$(get_stage_value "$((stage_idx - 1))" "name")
    resolve_stage_inputs "$prev_stage_name"
  else
    echo ""
  fi
}

# Check if a stage completion condition is met
check_stage_completion() {
  local completion_type=$1
  local output=$2
  local stage_dir=$3
  local run_idx=$4

  case "$completion_type" in
    plateau)
      check_plateau_completion "$output" "$stage_dir" "$run_idx"
      return $?
      ;;
    beads-empty)
      check_beads_completion "$SESSION_NAME"
      return $?
      ;;
    *)
      # Unknown completion type, don't stop early
      return 1
      ;;
  esac
}

# Check plateau completion (2 consecutive agents agree)
check_plateau_completion() {
  local output=$1
  local stage_dir=$2
  local run_idx=$3

  # Extract PLATEAU value from output
  local plateau_value=$(echo "$output" | grep -E "^PLATEAU:" | tail -1 | cut -d: -f2- | tr -d ' ' | tr '[:upper:]' '[:lower:]')

  # Store this run's plateau vote
  echo "$plateau_value" >> "$stage_dir/.plateau_votes"

  if [ "$plateau_value" = "true" ]; then
    # Check if previous run also said true
    if [ "$run_idx" -gt 0 ]; then
      local prev_vote=$(sed -n "${run_idx}p" "$stage_dir/.plateau_votes" 2>/dev/null)
      if [ "$prev_vote" = "true" ]; then
        # Two consecutive trues - plateau confirmed
        return 0
      fi
    fi
  fi

  return 1
}

# Check beads-empty completion
check_beads_completion() {
  local session=$1

  if ! command -v bd &>/dev/null; then
    return 1
  fi

  local remaining=$(bd ready --label="loop/$session" 2>/dev/null | grep -c "^" || echo "0")

  if [ "$remaining" -eq 0 ]; then
    return 0
  fi

  return 1
}
