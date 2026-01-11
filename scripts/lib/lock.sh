#!/bin/bash
# Session Lock Management
# Prevents concurrent sessions with the same name

LOCKS_DIR="${PROJECT_ROOT:-.}/.claude/locks"

# Acquire a lock for a session
# Usage: acquire_lock "$session" [--force]
# Returns 0 on success, 1 if locked by another process
acquire_lock() {
  local session=$1
  local force=${2:-""}

  mkdir -p "$LOCKS_DIR"
  local lock_file="$LOCKS_DIR/${session}.lock"

  # Check for existing lock
  if [ -f "$lock_file" ]; then
    local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)

    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      # PID is alive
      if [ "$force" = "--force" ]; then
        echo "Warning: Overriding existing lock for session '$session' (PID $existing_pid)" >&2
      else
        echo "Error: Session '$session' is already running (PID $existing_pid)" >&2
        echo "  Use --force to override" >&2
        return 1
      fi
    else
      # Stale lock - PID no longer running
      echo "Cleaning up stale lock for session '$session'" >&2
      rm -f "$lock_file"
    fi
  fi

  # Create lock file
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  jq -n \
    --arg session "$session" \
    --arg pid "$$" \
    --arg started "$timestamp" \
    '{session: $session, pid: ($pid | tonumber), started_at: $started}' > "$lock_file"

  return 0
}

# Release a lock for a session
# Usage: release_lock "$session"
release_lock() {
  local session=$1
  local lock_file="$LOCKS_DIR/${session}.lock"

  if [ -f "$lock_file" ]; then
    rm -f "$lock_file"
  fi
}

# Check if a session is locked
# Usage: is_locked "$session"
# Returns 0 if locked (by running process), 1 if not locked
is_locked() {
  local session=$1
  local lock_file="$LOCKS_DIR/${session}.lock"

  if [ ! -f "$lock_file" ]; then
    return 1
  fi

  local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)

  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
    return 0
  fi

  return 1
}

# Clean up stale locks (for dead PIDs)
# Usage: cleanup_stale_locks
cleanup_stale_locks() {
  mkdir -p "$LOCKS_DIR"

  # Handle case where no lock files exist
  local lock_files=("$LOCKS_DIR"/*.lock)
  [ -e "${lock_files[0]}" ] || return 0

  for lock_file in "${lock_files[@]}"; do
    [ -f "$lock_file" ] || continue

    local pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    local session=$(jq -r '.session // empty' "$lock_file" 2>/dev/null)

    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      echo "Removing stale lock: $session (PID $pid)" >&2
      rm -f "$lock_file"
    fi
  done
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
  local lock_file="$LOCKS_DIR/${session}.lock"

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

# Get resume iteration from state file
# Usage: get_resume_iteration "$state_file"
# Returns: iteration number to resume from
get_resume_iteration() {
  local state_file=$1
  local completed=$(jq -r '.iteration_completed // 0' "$state_file" 2>/dev/null)
  echo $((completed + 1))
}

# Reset state file for resume
# Usage: reset_for_resume "$state_file"
reset_for_resume() {
  local state_file=$1
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq --arg ts "$timestamp" \
     '.status = "running" | .resumed_at = $ts | .iteration_started = null' \
     "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
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
