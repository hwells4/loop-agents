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
        history: [],
        event_offset: 0
      }' > "$state_file"
  fi

  echo "$state_file"
}

#-------------------------------------------------------------------------------
# Event Snapshot Reconciliation
#-------------------------------------------------------------------------------

SNAPSHOT_STALE="false"
SNAPSHOT_EVENT_OFFSET="0"
SNAPSHOT_EVENT_COUNT="0"

_state_warn_invalid_event_line() {
  local events_file=$1
  local invalid_idx=$2
  local total_lines=$3

  if [ "$invalid_idx" -eq "$total_lines" ]; then
    echo "Warning: Skipping truncated final event line in $events_file" >&2
  else
    echo "Warning: Skipping invalid event line in $events_file" >&2
  fi
}

_state_read_events_file() {
  local events_file=$1

  if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
    echo "[]"
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)
  local total_lines=0
  local invalid_idx=0
  local invalid_count=0
  local valid_count=0
  local line=""

  while IFS= read -r line || [ -n "$line" ]; do
    total_lines=$((total_lines + 1))
    if echo "$line" | jq -e '.' >/dev/null 2>&1; then
      printf '%s\n' "$line" >> "$tmp_file"
      valid_count=$((valid_count + 1))
    else
      invalid_idx=$total_lines
      invalid_count=$((invalid_count + 1))
    fi
  done < "$events_file"

  if [ "$invalid_count" -gt 0 ]; then
    _state_warn_invalid_event_line "$events_file" "$invalid_idx" "$total_lines"
  fi

  if [ "$valid_count" -eq 0 ]; then
    echo "[]"
  else
    jq -s '.' "$tmp_file"
  fi

  rm -f "$tmp_file"
}

_state_count_events_file() {
  local events_file=$1

  if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
    echo "0"
    return 0
  fi

  local total_lines=0
  local invalid_idx=0
  local invalid_count=0
  local valid_count=0
  local line=""

  while IFS= read -r line || [ -n "$line" ]; do
    total_lines=$((total_lines + 1))
    if echo "$line" | jq -e '.' >/dev/null 2>&1; then
      valid_count=$((valid_count + 1))
    else
      invalid_idx=$total_lines
      invalid_count=$((invalid_count + 1))
    fi
  done < "$events_file"

  if [ "$invalid_count" -gt 0 ]; then
    _state_warn_invalid_event_line "$events_file" "$invalid_idx" "$total_lines"
  fi

  echo "$valid_count"
}

_state_default_snapshot() {
  local session=${1:-""}
  local type=${2:-""}
  local started_at=${3:-""}

  if [ -z "$started_at" ]; then
    started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  fi

  jq -n \
    --arg session "$session" \
    --arg type "$type" \
    --arg started "$started_at" \
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
      history: [],
      event_offset: 0
    }'
}

_state_cursor_stage() {
  local node_path=$1

  if [ -z "$node_path" ]; then
    return 0
  fi

  local head="${node_path%%/*}"
  if [[ "$head" =~ ^[0-9]+$ ]]; then
    echo "$head"
  fi
}

# Write snapshot with event_offset
# Usage: write_snapshot "$state_file" "$event_offset" ["$state_json"]
write_snapshot() {
  local state_file=$1
  local event_offset=${2:-""}
  local state_json=${3:-""}

  if [ -z "$event_offset" ]; then
    if [ -n "$state_json" ]; then
      event_offset=$(echo "$state_json" | jq -r '.event_offset // 0' 2>/dev/null || echo "0")
    elif [ -f "$state_file" ]; then
      event_offset=$(jq -r '.event_offset // 0' "$state_file" 2>/dev/null || echo "0")
    else
      event_offset="0"
    fi
  fi

  if ! [[ "$event_offset" =~ ^[0-9]+$ ]]; then
    event_offset="0"
  fi

  mkdir -p "$(dirname "$state_file")"

  if [ -n "$state_json" ]; then
    if ! echo "$state_json" | jq --argjson offset "$event_offset" \
      '.event_offset = $offset' > "$state_file.tmp"; then
      echo "Error: Failed to write snapshot state" >&2
      rm -f "$state_file.tmp"
      return 1
    fi
  elif [ -f "$state_file" ]; then
    if ! jq --argjson offset "$event_offset" \
      '.event_offset = $offset' "$state_file" > "$state_file.tmp"; then
      echo "Error: Failed to update snapshot state" >&2
      rm -f "$state_file.tmp"
      return 1
    fi
  else
    if ! jq -n --argjson offset "$event_offset" \
      '{event_offset: $offset}' > "$state_file.tmp"; then
      echo "Error: Failed to create snapshot state" >&2
      rm -f "$state_file.tmp"
      return 1
    fi
  fi

  mv "$state_file.tmp" "$state_file"
}

# Load cached snapshot and check if it is stale vs events.jsonl
# Usage: load_snapshot "$state_file" ["$events_file"]
# Echoes snapshot JSON (with event_offset set)
# Sets: SNAPSHOT_STALE, SNAPSHOT_EVENT_OFFSET, SNAPSHOT_EVENT_COUNT
load_snapshot() {
  local state_file=$1
  local events_file=${2:-"$(dirname "$state_file")/events.jsonl"}

  SNAPSHOT_STALE="false"
  SNAPSHOT_EVENT_OFFSET="0"
  SNAPSHOT_EVENT_COUNT="0"

  local state_json="{}"
  if [ -f "$state_file" ]; then
    state_json=$(cat "$state_file")
  fi

  local event_offset
  event_offset=$(echo "$state_json" | jq -r '.event_offset // 0' 2>/dev/null || echo "0")
  if ! [[ "$event_offset" =~ ^[0-9]+$ ]]; then
    event_offset="0"
  fi

  state_json=$(echo "$state_json" | jq --argjson offset "$event_offset" \
    '.event_offset = $offset' 2>/dev/null || echo '{"event_offset":0}')

  local event_count="0"
  if [ -f "$events_file" ] && [ -s "$events_file" ]; then
    event_count=$(_state_count_events_file "$events_file")
  fi
  if ! [[ "$event_count" =~ ^[0-9]+$ ]]; then
    event_count="0"
  fi

  if [ "$event_offset" -ne "$event_count" ]; then
    SNAPSHOT_STALE="true"
  fi

  SNAPSHOT_EVENT_OFFSET="$event_offset"
  SNAPSHOT_EVENT_COUNT="$event_count"

  echo "$state_json"
}

# Reconcile snapshot with events.jsonl, replaying from event_offset
# Usage: reconcile_with_events "$state_file" ["$events_file"] ["$session"] ["$type"]
reconcile_with_events() {
  local state_file=$1
  local events_file=${2:-"$(dirname "$state_file")/events.jsonl"}
  local session=${3:-""}
  local type=${4:-""}

  if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
    return 0
  fi

  local state_json=""
  if [ -f "$state_file" ]; then
    state_json=$(cat "$state_file")
  fi

  local events_json
  events_json=$(_state_read_events_file "$events_file")

  local event_count
  event_count=$(echo "$events_json" | jq -r 'length' 2>/dev/null || echo "0")
  if ! [[ "$event_count" =~ ^[0-9]+$ ]]; then
    event_count="0"
  fi

  local event_offset="0"
  if [ -n "$state_json" ]; then
    event_offset=$(echo "$state_json" | jq -r '.event_offset // 0' 2>/dev/null || echo "0")
  fi
  if ! [[ "$event_offset" =~ ^[0-9]+$ ]]; then
    event_offset="0"
  fi
  if [ "$event_offset" -gt "$event_count" ]; then
    echo "Warning: state event_offset ($event_offset) exceeds events count ($event_count); rebuilding from scratch" >&2
    event_offset="0"
  fi

  if [ -z "$state_json" ] || ! echo "$state_json" | jq -e '.' >/dev/null 2>&1; then
    if [ -z "$session" ]; then
      session=$(echo "$events_json" | jq -r '.[0].session // ""' 2>/dev/null)
    fi
    local started_at=""
    started_at=$(echo "$events_json" | jq -r \
      '[.[] | select(.type == "session_start")][0].ts // .[0].ts // empty' 2>/dev/null)
    state_json=$(_state_default_snapshot "$session" "$type" "$started_at")
  else
    state_json=$(echo "$state_json" | jq --argjson offset "$event_offset" \
      '.event_offset = $offset' 2>/dev/null || _state_default_snapshot "$session" "$type" "")
  fi

  local updates="[]"
  if [ "$event_offset" -lt "$event_count" ]; then
    updates=$(echo "$events_json" | jq -c --argjson offset "$event_offset" \
      'if $offset >= length then [] else .[$offset:] end' 2>/dev/null || echo "[]")
  fi

  local updated_state="$state_json"
  if [ "$updates" != "[]" ]; then
    while IFS= read -r event; do
      [ -z "$event" ] && continue
      local type_name=""
      local ts=""
      local cursor="null"
      local iteration=""
      local node_path=""
      local stage_idx=""

      type_name=$(echo "$event" | jq -r '.type // ""' 2>/dev/null)
      ts=$(echo "$event" | jq -r '.ts // empty' 2>/dev/null)
      cursor=$(echo "$event" | jq -c '.cursor // null' 2>/dev/null)

      if [ "$cursor" != "null" ] && [ -n "$cursor" ]; then
        updated_state=$(echo "$updated_state" | jq --argjson cursor "$cursor" '.cursor = $cursor')

        iteration=$(echo "$cursor" | jq -r '.iteration // empty' 2>/dev/null)
        if [[ "$iteration" =~ ^[0-9]+$ ]]; then
          updated_state=$(echo "$updated_state" | jq --argjson iter "$iteration" '.iteration = $iter')
        fi

        node_path=$(echo "$cursor" | jq -r '.node_path // empty' 2>/dev/null)
        stage_idx=$(_state_cursor_stage "$node_path")
        if [ -n "$stage_idx" ]; then
          updated_state=$(echo "$updated_state" | jq --argjson stage "$stage_idx" '.current_stage = $stage')
        fi
      fi

      case "$type_name" in
        iteration_start)
          if [[ "$iteration" =~ ^[0-9]+$ ]]; then
            if [ -n "$ts" ]; then
              updated_state=$(echo "$updated_state" | jq \
                --argjson iter "$iteration" --arg ts "$ts" \
                '.iteration = $iter | .iteration_started = $ts | .status = "running"')
            else
              updated_state=$(echo "$updated_state" | jq \
                --argjson iter "$iteration" \
                '.iteration = $iter | .iteration_started = null | .status = "running"')
            fi
          fi
          ;;
        iteration_complete)
          if [[ "$iteration" =~ ^[0-9]+$ ]]; then
            updated_state=$(echo "$updated_state" | jq \
              --argjson iter "$iteration" \
              '.iteration_completed = $iter | .iteration_started = null')
          fi
          ;;
        session_complete)
          if [ -n "$ts" ]; then
            updated_state=$(echo "$updated_state" | jq \
              --arg ts "$ts" \
              '.status = "complete" | .completed_at = $ts')
          else
            updated_state=$(echo "$updated_state" | jq '.status = "complete"')
          fi
          ;;
        error)
          if [ -n "$ts" ]; then
            updated_state=$(echo "$updated_state" | jq \
              --arg ts "$ts" \
              '.status = "failed" | .failed_at = $ts')
          else
            updated_state=$(echo "$updated_state" | jq '.status = "failed"')
          fi
          ;;
      esac
    done <<< "$(echo "$updates" | jq -c '.[]' 2>/dev/null)"
  fi

  updated_state=$(echo "$updated_state" | jq --argjson offset "$event_count" \
    '.event_offset = $offset')

  write_snapshot "$state_file" "$event_count" "$updated_state"
}

# Update iteration in state
# Usage: update_iteration "$state_file" "$iteration" "$output_vars"
update_iteration() {
  local state_file=$1
  local iteration=$2
  local output_vars=${3:-"{}"}  # JSON object
  local stage_name=${4:-""}     # Optional: stage name for multi-stage pipelines

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Include stage in history entry if provided (for multi-stage plateau filtering)
  local stage_arg=""
  if [ -n "$stage_name" ]; then
    stage_arg="--arg stage \"$stage_name\""
  fi

  if ! jq --argjson iter "$iteration" \
     --argjson vars "$output_vars" \
     --arg ts "$timestamp" \
     --arg stage "$stage_name" \
     '.iteration = $iter | .history += [{"iteration": $iter, "timestamp": $ts, "stage": $stage} + $vars]' \
     "$state_file" > "$state_file.tmp"; then
    echo "Error: Failed to update iteration in state file" >&2
    rm -f "$state_file.tmp"
    return 1
  fi
  mv "$state_file.tmp" "$state_file"
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

  if ! jq --argjson iter "$iteration" \
     --arg ts "$timestamp" \
     '.iteration = $iter | .iteration_started = $ts | .status = "running"' \
     "$state_file" > "$state_file.tmp"; then
    echo "Error: Failed to mark iteration started in state file" >&2
    rm -f "$state_file.tmp"
    return 1
  fi
  mv "$state_file.tmp" "$state_file"
}

# Mark iteration completed
# Usage: mark_iteration_completed "$state_file" "$iteration"
mark_iteration_completed() {
  local state_file=$1
  local iteration=$2

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  if ! jq --argjson iter "$iteration" \
     --arg ts "$timestamp" \
     '.iteration_completed = $iter | .iteration_started = null' \
     "$state_file" > "$state_file.tmp"; then
    echo "Error: Failed to mark iteration completed in state file" >&2
    rm -f "$state_file.tmp"
    return 1
  fi
  mv "$state_file.tmp" "$state_file"
}

# Mark session as failed with detailed error (v3)
# Usage: mark_failed "$state_file" "$error_message" [error_type]
# Creates structured error object with type, message, timestamp
# Also sets resume_from for crash recovery
mark_failed() {
  local state_file=$1
  local error_message=$2
  local error_type=${3:-"unknown"}

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  local iteration_completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
  local resume_from=$((iteration_completed + 1))

  jq --arg error_msg "$error_message" \
     --arg error_type "$error_type" \
     --arg ts "$timestamp" \
     --argjson resume "$resume_from" \
     '.status = "failed" |
      .failed_at = $ts |
      .error = {
        type: $error_type,
        message: $error_msg,
        timestamp: $ts
      } |
      .resume_from = $resume' \
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

# Get the stage to resume from (for multi-stage pipelines)
# Usage: get_resume_stage "$state_file"
# Returns: stage index to resume from (current_stage if running, or first incomplete stage)
get_resume_stage() {
  local state_file=$1

  if [ ! -f "$state_file" ]; then
    echo "0"
    return 0
  fi

  local current_stage=$(jq -r '.current_stage // 0' "$state_file" 2>/dev/null)
  echo "$current_stage"
}

# Check if a stage is complete
# Usage: is_stage_complete "$state_file" "$stage_idx"
# Returns: 0 if complete, 1 otherwise
is_stage_complete() {
  local state_file=$1
  local stage_idx=$2

  if [ ! -f "$state_file" ]; then
    return 1
  fi

  local stage_status=$(jq -r ".stages[$stage_idx].status // \"\"" "$state_file" 2>/dev/null)
  [ "$stage_status" = "complete" ]
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

# Reset iteration counters for new stage
# Usage: reset_iteration_counters "$state_file"
# Call this when starting a new stage in a multi-stage pipeline
# to prevent stale iteration_completed values from previous stage
reset_iteration_counters() {
  local state_file=$1

  jq '.iteration = 0 | .iteration_completed = 0 | .iteration_started = null' \
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

#-------------------------------------------------------------------------------
# Session Status (for crash recovery)
#-------------------------------------------------------------------------------

# Global variable for status details
SESSION_STATUS_DETAILS=""

# Get session status
# Usage: get_session_status "$session" "$state_file"
# Returns: "none", "active", "failed", "completed"
# Sets: SESSION_STATUS_DETAILS with human-readable info
get_session_status() {
  local session=$1
  local state_file=$2
  local lock_file="${PROJECT_ROOT:-.}/.claude/locks/${session}.lock"

  SESSION_STATUS_DETAILS=""

  # Check if state file exists
  if [ ! -f "$state_file" ]; then
    SESSION_STATUS_DETAILS="No previous session found"
    echo "none"
    return
  fi

  # Check status in state file
  local state_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)

  if [ "$state_status" = "completed" ]; then
    local completed_at=$(jq -r '.completed_at // "unknown"' "$state_file" 2>/dev/null)
    local reason=$(jq -r '.completion_reason // "unknown"' "$state_file" 2>/dev/null)
    SESSION_STATUS_DETAILS="Completed at $completed_at (reason: $reason)"
    echo "completed"
    return
  fi

  # Check if lock exists
  if [ -f "$lock_file" ]; then
    local pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    local started=$(jq -r '.started_at // "unknown"' "$lock_file" 2>/dev/null)

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      SESSION_STATUS_DETAILS="Running since $started (PID $pid)"
      echo "active"
      return
    else
      # Lock exists but PID dead = crashed
      local last_iter=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
      SESSION_STATUS_DETAILS="Crashed at iteration $last_iter (PID $pid no longer running)"
      echo "failed"
      return
    fi
  fi

  # No lock but status is "running" = crashed without lock
  if [ "$state_status" = "running" ]; then
    local last_iter=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
    SESSION_STATUS_DETAILS="Crashed at iteration $last_iter (no lock file found)"
    echo "failed"
    return
  fi

  SESSION_STATUS_DETAILS="Unknown state"
  echo "none"
}

# Get crash recovery info
# Usage: get_crash_info "$session" "$state_file"
# Sets: CRASH_LAST_ITERATION, CRASH_LAST_COMPLETED
get_crash_info() {
  local session=$1
  local state_file=$2

  CRASH_LAST_ITERATION=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
  CRASH_LAST_COMPLETED=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
}

# Show crash recovery information
# Usage: show_crash_recovery_info "$session" "$state_file" "$max_iterations"
show_crash_recovery_info() {
  local session=$1
  local state_file=$2
  local max_iterations=$3

  get_crash_info "$session" "$state_file"

  echo ""
  echo "Session '$session' crashed and can be resumed."
  echo ""
  echo "  Last iteration started:   $CRASH_LAST_ITERATION"
  echo "  Last iteration completed: $CRASH_LAST_COMPLETED"
  echo ""
  echo "To resume from iteration $((CRASH_LAST_COMPLETED + 1)):"
  echo "  ./scripts/run.sh loop <type> $session $max_iterations --resume"
  echo ""
}

# Show resume information
# Usage: show_resume_info "$session" "$start_iteration" "$max_iterations"
show_resume_info() {
  local session=$1
  local start_iteration=$2
  local max_iterations=$3

  echo ""
  echo "═══════════════════════════════════════"
  echo "  RESUMING SESSION"
  echo "  Session: $session"
  echo "  Starting from iteration: $start_iteration"
  echo "  Max iterations: $max_iterations"
  echo "═══════════════════════════════════════"
  echo ""
}

#-------------------------------------------------------------------------------
# Parallel Block Support
#-------------------------------------------------------------------------------

# Initialize parallel block directory structure
# Usage: block_dir=$(init_parallel_block "$run_dir" "$stage_idx" "$block_name" "$providers")
# Returns: Path to block directory
init_parallel_block() {
  local run_dir=$1
  local stage_idx=$2
  local block_name=$3       # Optional: if empty, auto-generates
  local providers=$4        # Space-separated list of providers

  # Generate block directory name: parallel-XX-name or parallel-XX if no name
  local idx_fmt=$(printf '%02d' "$stage_idx")
  local block_dir_name
  if [ -n "$block_name" ]; then
    block_dir_name="parallel-${idx_fmt}-${block_name}"
  else
    block_dir_name="parallel-${idx_fmt}"
  fi

  local block_dir="$run_dir/$block_dir_name"
  mkdir -p "$block_dir"

  # Create provider directories
  for provider in $providers; do
    mkdir -p "$block_dir/providers/$provider"
  done

  echo "$block_dir"
}

# Initialize provider state within a parallel block
# Usage: init_provider_state "$block_dir" "$provider" "$session"
# Creates: state.json and progress.md for the provider
init_provider_state() {
  local block_dir=$1
  local provider=$2
  local session=$3

  local provider_dir="$block_dir/providers/$provider"
  mkdir -p "$provider_dir"

  # Create provider-specific state file
  local state_file="$provider_dir/state.json"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq -n \
    --arg provider "$provider" \
    --arg session "$session" \
    --arg started "$timestamp" \
    '{
      provider: $provider,
      session: $session,
      started_at: $started,
      status: "pending",
      current_stage: 0,
      iteration: 0,
      iteration_completed: 0,
      stages: []
    }' > "$state_file"

  # Create provider-specific progress file
  local progress_file="$provider_dir/progress.md"
  cat > "$progress_file" << EOF
# Progress: $session ($provider)

Provider: $provider

---

EOF

  echo "$state_file"
}

# Write parallel block manifest after all providers complete
# Usage: write_parallel_manifest "$block_dir" "$block_name" "$block_idx" "$stages" "$providers"
# Creates: manifest.json with provider outputs
write_parallel_manifest() {
  local block_dir=$1
  local block_name=$2
  local block_idx=$3
  local stages=$4          # Space-separated list of stage names
  local providers=$5       # Space-separated list of providers

  local manifest_file="$block_dir/manifest.json"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Build stages array
  local stages_json="[]"
  for stage in $stages; do
    stages_json=$(echo "$stages_json" | jq --arg s "$stage" '. + [$s]')
  done

  # Build providers object
  local providers_json="{}"
  for provider in $providers; do
    local provider_dir="$block_dir/providers/$provider"
    local provider_state="$provider_dir/state.json"

    if [ -f "$provider_state" ]; then
      # Read provider's stage outputs
      local provider_stages=$(jq -c '.stages // []' "$provider_state")

      # Build output paths for each stage
      local provider_data="{}"
      local stage_idx=0
      for stage in $stages; do
        local stage_dir_name="stage-$(printf '%02d' $stage_idx)-${stage}"
        local stage_dir="$provider_dir/$stage_dir_name"

        if [ -d "$stage_dir" ]; then
          # Find latest iteration
          local latest_iter=$(ls -1 "$stage_dir/iterations" 2>/dev/null | sort -n | tail -1)
          if [ -n "$latest_iter" ]; then
            local iter_dir="$stage_dir/iterations/$latest_iter"
            local output_path="$iter_dir/output.md"
            local status_path="$iter_dir/status.json"
            local result_path="$iter_dir/result.json"

            # Get iteration count and termination reason from provider state
            local stage_info=$(echo "$provider_stages" | jq --arg name "$stage" '.[] | select(.name == $name)')
            local iterations=$(echo "$stage_info" | jq -r '.iterations // 1')
            local term_reason=$(echo "$stage_info" | jq -r '.termination_reason // "unknown"')

            # Build history array of all iteration outputs
            local history="[]"
            for iter in $(ls -1 "$stage_dir/iterations" 2>/dev/null | sort -n); do
              local iter_output="$stage_dir/iterations/$iter/output.md"
              if [ -f "$iter_output" ]; then
                history=$(echo "$history" | jq --arg p "$iter_output" '. + [$p]')
              fi
            done

            provider_data=$(echo "$provider_data" | jq \
              --arg stage "$stage" \
              --arg output "$output_path" \
              --arg status "$status_path" \
              --arg result "$result_path" \
              --argjson iters "$iterations" \
              --arg reason "$term_reason" \
              --argjson history "$history" \
              '. + {($stage): {latest_output: $output, status: $status, result: $result, iterations: $iters, termination_reason: $reason, history: $history}}')
          fi
        fi
        stage_idx=$((stage_idx + 1))
      done

      providers_json=$(echo "$providers_json" | jq --arg p "$provider" --argjson data "$provider_data" '. + {($p): $data}')
    fi
  done

  # Write manifest
  jq -n \
    --arg name "$block_name" \
    --argjson index "$block_idx" \
    --argjson stages "$stages_json" \
    --argjson providers "$providers_json" \
    --arg ts "$timestamp" \
    '{
      block: {name: $name, index: $index, stages: $stages},
      providers: $providers,
      completed_at: $ts
    }' > "$manifest_file"
}

# Write parallel block resume hints for crash recovery
# Usage: write_parallel_resume "$block_dir" "$provider" "$stage_idx" "$iteration" "$status"
write_parallel_resume() {
  local block_dir=$1
  local provider=$2
  local stage_idx=$3
  local iteration=$4
  local status=$5

  local resume_file="$block_dir/resume.json"

  # Create or update resume file
  if [ ! -f "$resume_file" ]; then
    echo "{}" > "$resume_file"
  fi

  jq --arg provider "$provider" \
     --argjson stage "$stage_idx" \
     --argjson iter "$iteration" \
     --arg status "$status" \
     '. + {($provider): {stage_index: $stage, iteration: $iter, status: $status}}' \
     "$resume_file" > "$resume_file.tmp" && mv "$resume_file.tmp" "$resume_file"
}

# Get parallel block resume hint for a provider
# Usage: get_parallel_resume_hint "$block_dir" "$provider"
# Returns: JSON object with stage_index, iteration, status
get_parallel_resume_hint() {
  local block_dir=$1
  local provider=$2

  local resume_file="$block_dir/resume.json"

  if [ -f "$resume_file" ]; then
    jq -c --arg p "$provider" '.[$p] // {stage_index: 0, iteration: 1, status: "pending"}' "$resume_file"
  else
    echo '{"stage_index": 0, "iteration": 1, "status": "pending"}'
  fi
}
