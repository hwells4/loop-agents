#!/bin/bash
# Completion strategy: beads-empty (v3)
# Complete when no beads remain for this session
#
# v3: Accepts result file, checks for error status

source "$(dirname "${BASH_SOURCE[0]}")/../result.sh"

check_completion() {
  local session=$1
  local state_file=$2
  local result_file=$3  # v3: Now receives result file path

  # Check if agent reported error - stop the loop on error
  # (Bug fix: loop-agents-r5x - consistent with fixed-n.sh behavior)
  # Only check for error if the status file actually exists
  local decision=$(result_decision_hint "$result_file" 2>/dev/null)
  local resolved
  resolved=$(result_resolve_file "$result_file" || true)
  if [ -f "$resolved" ] && [ "$decision" = "error" ]; then
    echo "Agent reported error - stopping loop"
    return 0
  fi

  local remaining
  remaining=$(bd ready --label="pipeline/$session" 2>/dev/null | grep -c "^") || remaining=0

  if [ "$remaining" -eq 0 ]; then
    echo "All beads complete"
    return 0
  fi

  return 1
}

# Check for explicit completion signal in output (legacy support)
check_output_signal() {
  local output=$1

  if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
    return 0
  fi

  return 1
}
