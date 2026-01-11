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
