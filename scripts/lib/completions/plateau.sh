#!/bin/bash
# Completion strategy: plateau (v3)
# Requires N consecutive agents to write decision: stop
# Prevents single-agent blind spots
#
# v3: Reads from result.json (or legacy status.json) instead of parsing output text
# v3.1: Optionally uses external judge (Haiku) for better trend detection
#
# Set USE_JUDGE=true to enable external judge evaluation

PLATEAU_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$PLATEAU_SCRIPT_DIR/../result.sh"

# Try to load judge module for external evaluation
_plateau_load_judge() {
  if [ -f "$PLATEAU_SCRIPT_DIR/../judge.sh" ]; then
    source "$PLATEAU_SCRIPT_DIR/../judge.sh"
    return 0
  fi
  return 1
}

# Get judge decision on whether to stop
# Returns: "stop" or "continue"
_plateau_judge_decision() {
  local session=$1
  local iteration=$2
  local result_file=$3
  local progress_file=$4
  local stage_name=$5
  local iter_dir=$6

  # Build previous iterations list
  local prev_files="[]"
  if [ "$iteration" -gt 1 ] && [ -n "$iter_dir" ]; then
    local parent_dir=$(dirname "$iter_dir")
    local files=()
    for ((i=1; i<iteration; i++)); do
      local candidate="$parent_dir/$(printf '%03d' $i)/output.md"
      [ -f "$candidate" ] && files+=("$candidate")
    done
    if [ ${#files[@]} -gt 0 ]; then
      prev_files=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)
    fi
  fi

  local judge_input
  judge_input=$(jq -n \
    --arg session "$session" \
    --argjson iteration "$iteration" \
    --arg stage_name "$stage_name" \
    --arg result "$result_file" \
    --arg progress "$progress_file" \
    --argjson prev_iterations "$prev_files" \
    '{
      session: $session,
      cursor: {iteration: $iteration},
      node: {id: $stage_name},
      paths: {result: $result, progress: $progress},
      inputs: {from_previous_iterations: $prev_iterations},
      termination: {}
    }')

  local judge_output
  judge_output=$(judge_decision "$judge_input" 2>/dev/null) || {
    echo "continue"
    return
  }

  local stop
  stop=$(echo "$judge_output" | jq -r '.stop // false')
  if [ "$stop" = "true" ]; then
    echo "stop"
  else
    echo "continue"
  fi
}

check_completion() {
  local session=$1
  local state_file=$2
  local result_file=$3  # v3: Now receives result file path

  # Get configurable consensus count (default 2)
  local consensus_needed=${CONSENSUS:-2}
  local min_iterations=${MIN_ITERATIONS:-2}

  # Read current iteration
  local iteration=$(get_state "$state_file" "iteration")

  # Must hit minimum iterations first
  if [ "$iteration" -lt "$min_iterations" ]; then
    return 1
  fi

  # Determine decision source: external judge or worker signal
  local decision=""
  local reason=""
  local use_judge="${USE_JUDGE:-false}"

  if [ "$use_judge" = "true" ] && _plateau_load_judge; then
    # Use external judge (Haiku) for decision
    local progress_file=$(jq -r '.progress_file // ""' "$state_file" 2>/dev/null)
    local stage_name=$(jq -r '.stages[.current_stage // 0].name // "stage"' "$state_file" 2>/dev/null)
    local iter_dir=$(dirname "$result_file")

    decision=$(_plateau_judge_decision "$session" "$iteration" "$result_file" "$progress_file" "$stage_name" "$iter_dir")
    reason="Judge evaluation based on iteration history"
  else
    # Read current decision from result.json (fallback to status.json)
    decision=$(result_decision_hint "$result_file")
    reason=$(result_reason_hint "$result_file")
  fi
  local resolved
  resolved=$(result_resolve_file "$result_file" || true)

  # Check if agent reported error - stop the loop on error
  # (Bug fix: loop-agents-r5x - consistent with fixed-n.sh behavior)
  # Only check for error if the result/status file actually exists
  if [ -f "$resolved" ] && [ "$decision" = "error" ]; then
    echo "Agent reported error - stopping loop"
    echo "  Reason: $reason"
    return 0
  fi

  if [ "$decision" = "stop" ]; then
    # Get current stage name for filtering (multi-stage pipeline support)
    local current_stage_idx=$(jq -r '.current_stage // 0' "$state_file" 2>/dev/null)
    local current_stage_name=$(jq -r ".stages[$current_stage_idx].name // \"\"" "$state_file" 2>/dev/null)

    # Count consecutive "stop" decisions from history (filtered by current stage)
    # NOTE: History already includes the current iteration's decision (added by
    # update_iteration before check_completion is called), so we count from
    # history only - no separate count for status_file to avoid double-counting
    local history=$(get_history "$state_file")
    local consecutive=0

    # Check iterations for consecutive stops (same stage only), starting from most recent
    local history_len=$(echo "$history" | jq 'length')
    for ((i = history_len - 1; i >= 0 && consecutive < consensus_needed; i--)); do
      local entry_stage=$(echo "$history" | jq -r ".[$i].stage // \"\"")

      # Skip entries from different stages (for multi-stage pipelines)
      if [ -n "$current_stage_name" ] && [ -n "$entry_stage" ] && [ "$entry_stage" != "$current_stage_name" ]; then
        continue
      fi

      local prev_decision=$(echo "$history" | jq -r ".[$i].decision // \"continue\"")
      if [ "$prev_decision" = "stop" ]; then
        ((consecutive++))
      else
        break
      fi
    done

    if [ "$consecutive" -ge "$consensus_needed" ]; then
      echo "Consensus reached: $consecutive consecutive agents agree to stop"
      echo "  Reason: $reason"
      return 0
    else
      echo "Stop suggested but not confirmed ($consecutive/$consensus_needed needed)"
      echo "  Current agent says: $reason"
      echo "  Continuing for independent confirmation..."
      return 1
    fi
  fi

  return 1
}
