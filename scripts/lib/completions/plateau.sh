#!/bin/bash
# Completion strategy: plateau (v3)
# Requires N consecutive agents to write decision: stop
# Prevents single-agent blind spots
#
# v3: Reads from result.json (or legacy status.json) instead of parsing output text

source "$(dirname "${BASH_SOURCE[0]}")/../result.sh"

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

  # Read current decision from result.json (fallback to status.json)
  local decision=$(result_decision_hint "$result_file")
  local reason=$(result_reason_hint "$result_file")
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
