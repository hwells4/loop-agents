#!/bin/bash
# Completion strategy: fixed-n (v3)
# Complete after exactly N iterations, OR if agent writes decision: stop
#
# This allows agents to exit early when work is done, while still
# enforcing a maximum iteration limit.

source "$(dirname "${BASH_SOURCE[0]}")/../result.sh"

check_completion() {
  local session=$1
  local state_file=$2
  local result_file=$3

  # Safely get iteration with integer validation
  local iteration=$(get_state "$state_file" "iteration" | tr -d '[:space:]')
  iteration=${iteration:-0}
  # Ensure iteration is a valid integer (strip non-numeric chars as safety)
  [[ ! "$iteration" =~ ^[0-9]+$ ]] && iteration=0

  # Get target with proper fallback chain (handle empty strings)
  local target="${FIXED_ITERATIONS:-}"
  [ -z "$target" ] && target="${MAX_ITERATIONS:-}"
  [ -z "$target" ] && target=10
  # Ensure target is a valid integer
  [[ ! "$target" =~ ^[0-9]+$ ]] && target=10

  # Check if agent signaled stop
  if [ -n "$result_file" ]; then
    local decision=$(result_decision_hint "$result_file")
    if [ "$decision" = "stop" ]; then
      echo "Agent requested stop at iteration $iteration"
      return 0
    fi
    if [ "$decision" = "error" ]; then
      echo "Agent reported error at iteration $iteration"
      return 0
    fi
  fi

  # Check if we've hit the iteration limit
  if [ "$iteration" -ge "$target" ]; then
    echo "Completed $iteration iterations (max: $target)"
    return 0
  fi

  return 1
}
