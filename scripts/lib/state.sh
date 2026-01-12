#!/bin/bash
# Unified State Management
# Handles state for both single-stage loops and multi-stage pipelines

# Initialize state file
# Usage: init_state "$session" "$type" "$run_dir"
init_state() {
  local session=$1
  local type=$2  # "loop" or "pipeline"
  local run_dir=${3:-"$PROJECT_ROOT/.claude"}

  mkdir -p "$run_dir"
  local state_file="$run_dir/state.json"

  if [ ! -f "$state_file" ]; then
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    jq -n \
      --arg session "$session" \
      --arg type "$type" \
      --arg started "$timestamp" \
      '{
        session: $session,
        type: $type,
        started_at: $started,
        status: "running",
        current_stage: 0,
        iteration: 0,
        iteration_completed: 0,
        iteration_started: null,
        stages: [],
        history: []
      }' > "$state_file"
  fi

  echo "$state_file"
}

# Update iteration in state
# Usage: update_iteration "$state_file" "$iteration" "$output_vars"
update_iteration() {
  local state_file=$1
  local iteration=$2
  local output_vars=${3:-"{}"}  # JSON object

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --argjson iter "$iteration" \
     --argjson vars "$output_vars" \
     --arg ts "$timestamp" \
     '.iteration = $iter | .history += [{"iteration": $iter, "timestamp": $ts} + $vars]' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Update stage status (for pipelines)
# Usage: update_stage "$state_file" "$stage_idx" "$stage_name" "$status"
update_stage() {
  local state_file=$1
  local stage_idx=$2
  local stage_name=$3
  local status=$4

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Check if stage entry exists
  if jq -e ".stages[$stage_idx]" "$state_file" &>/dev/null; then
    jq --arg status "$status" --arg ts "$timestamp" --argjson idx "$stage_idx" \
      '.stages[$idx].status = $status | .stages[$idx].timestamp = $ts | .current_stage = $idx' \
      "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  else
    jq --arg name "$stage_name" --arg status "$status" --arg ts "$timestamp" --argjson idx "$stage_idx" \
      '.stages += [{"index": $idx, "name": $name, "status": $status, "timestamp": $ts}] | .current_stage = $idx' \
      "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  fi
}

# Get state value
# Usage: get_state "$state_file" "iteration"
get_state() {
  local state_file=$1
  local key=$2

  jq -r ".$key // empty" "$state_file" 2>/dev/null
}

# Get history array
# Usage: get_history "$state_file"
get_history() {
  local state_file=$1
  jq -c '.history' "$state_file" 2>/dev/null || echo "[]"
}

# Mark iteration started
# Usage: mark_iteration_started "$state_file" "$iteration"
mark_iteration_started() {
  local state_file=$1
  local iteration=$2

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --argjson iter "$iteration" \
     --arg ts "$timestamp" \
     '.iteration = $iter | .iteration_started = $ts | .status = "running"' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Mark iteration completed
# Usage: mark_iteration_completed "$state_file" "$iteration"
mark_iteration_completed() {
  local state_file=$1
  local iteration=$2

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --argjson iter "$iteration" \
     --arg ts "$timestamp" \
     '.iteration_completed = $iter | .iteration_started = null' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Mark session as failed
# Usage: mark_failed "$state_file" "$error"
mark_failed() {
  local state_file=$1
  local error=$2

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --arg status "failed" \
     --arg error "$error" \
     --arg ts "$timestamp" \
     '.status = $status | .failed_at = $ts | .error = $error' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Get the iteration to resume from
# Usage: get_resume_iteration "$state_file"
# Returns: iteration number to resume from (last_completed + 1)
get_resume_iteration() {
  local state_file=$1

  if [ ! -f "$state_file" ]; then
    echo "1"
    return 0
  fi

  local completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
  echo "$((completed + 1))"
}

# Check if session can be resumed
# Usage: can_resume "$state_file"
# Returns: 0 if can resume, 1 if not
can_resume() {
  local state_file=$1

  if [ ! -f "$state_file" ]; then
    return 1
  fi

  local status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)

  case "$status" in
    complete)
      return 1  # Already complete, nothing to resume
      ;;
    running|failed)
      return 0  # Can resume
      ;;
    *)
      return 1
      ;;
  esac
}

# Reset state for resume (clears failure status, keeps history, adds resumed_at)
# Usage: reset_for_resume "$state_file"
reset_for_resume() {
  local state_file=$1
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --arg ts "$timestamp" \
     '.status = "running" | .resumed_at = $ts | del(.failed_at) | del(.error) | .iteration_started = null' \
    "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

# Mark complete
# Usage: mark_complete "$state_file" "$reason"
mark_complete() {
  local state_file=$1
  local reason=$2

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --arg status "complete" \
     --arg reason "$reason" \
     --arg ts "$timestamp" \
     '.status = $status | .completed_at = $ts | .completion_reason = $reason | .iteration_started = null' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}
