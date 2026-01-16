#!/bin/bash
# Session Lock Management
# Prevents concurrent sessions with the same name

LOCKS_DIR="${PROJECT_ROOT:-.}/.claude/locks"
LOCK_FD=""
LOCK_SESSION=""
LOCK_TOOL=""

# Detect best available lock implementation
# Returns: flock | shlock | noclobber
detect_flock() {
  if command -v flock >/dev/null 2>&1; then
    echo "flock"
    return 0
  fi

  if command -v shlock >/dev/null 2>&1; then
    echo "shlock"
    return 0
  fi

  echo "noclobber"
}

_file_lock_timestamp() {
  date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

_write_file_lock_metadata() {
  local lock_target=$1
  local meta_file=$2
  local timestamp
  timestamp=$(_file_lock_timestamp)

  mkdir -p "$(dirname "$meta_file")"
  jq -n \
    --arg path "$lock_target" \
    --arg pid "$$" \
    --arg started "$timestamp" \
    '{path: $path, pid: ($pid | tonumber), started_at: $started}' > "$meta_file"
}

_clear_file_lock_metadata() {
  local meta_file=$1
  [ -n "$meta_file" ] && rm -f "$meta_file"
}

_with_file_lock_inner() {
  local lock_target=$1
  local meta_file=$2
  shift 2

  _write_file_lock_metadata "$lock_target" "$meta_file"
  "$@"
  local result=$?
  _clear_file_lock_metadata "$meta_file"
  return $result
}

# Execute command with an exclusive lock for a target file.
# Usage: with_exclusive_file_lock "$target" [timeout_seconds] command [args...]
with_exclusive_file_lock() {
  local lock_target=$1
  shift

  if [ -z "$lock_target" ]; then
    echo "Error: with_exclusive_file_lock requires a target path" >&2
    return 1
  fi

  local timeout=${FILE_LOCK_TIMEOUT:-""}
  if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    timeout=$1
    shift
  fi

  if [ $# -eq 0 ]; then
    echo "Error: with_exclusive_file_lock requires a command" >&2
    return 1
  fi

  local lock_tool
  lock_tool=$(detect_flock)
  local lock_file="${lock_target}.lock"
  mkdir -p "$(dirname "$lock_file")"

  if [ "$lock_tool" = "flock" ]; then
    (
      exec 9<> "$lock_file"
      if [ -n "$timeout" ]; then
        flock -x -w "$timeout" 9 || exit 1
      else
        flock -x 9 || exit 1
      fi
      "$@"
    )
    return $?
  fi

  (
    local start_time=$SECONDS
    while true; do
      if [ "$lock_tool" = "shlock" ]; then
        if shlock -f "$lock_file" -p "$$" >/dev/null 2>&1; then
          break
        fi
      else
        if (set -C; echo "$$" > "$lock_file") 2>/dev/null; then
          break
        fi
      fi

      if [ -n "$timeout" ]; then
        local waited=$((SECONDS - start_time))
        if [ "$waited" -ge "$timeout" ]; then
          exit 1
        fi
      fi
      sleep 0.05
    done
    trap 'rm -f "$lock_file"' EXIT
    "$@"
  )
}

# Execute command with an exclusive lock and metadata tracking.
# Usage: with_file_lock "$target" [timeout_seconds] command [args...]
with_file_lock() {
  local lock_target=$1
  shift

  if [ -z "$lock_target" ]; then
    echo "Error: with_file_lock requires a target path" >&2
    return 1
  fi

  local timeout=${FILE_LOCK_TIMEOUT:-""}
  if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
    timeout=$1
    shift
  fi

  if [ $# -eq 0 ]; then
    echo "Error: with_file_lock requires a command" >&2
    return 1
  fi

  local meta_file="${lock_target}.lock.meta"

  if [ -n "$timeout" ]; then
    with_exclusive_file_lock "$lock_target" "$timeout" _with_file_lock_inner "$lock_target" "$meta_file" "$@"
  else
    with_exclusive_file_lock "$lock_target" _with_file_lock_inner "$lock_target" "$meta_file" "$@"
  fi
}

_write_lock_metadata() {
  local session=$1
  local lock_file=$2
  local mode=${3:-"atomic"}

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  if [ "$mode" = "direct" ]; then
    jq -n \
      --arg session "$session" \
      --arg pid "$$" \
      --arg started "$timestamp" \
      '{session: $session, pid: ($pid | tonumber), started_at: $started}' > "$lock_file"
  else
    local tmp_file
    tmp_file=$(mktemp)
    jq -n \
      --arg session "$session" \
      --arg pid "$$" \
      --arg started "$timestamp" \
      '{session: $session, pid: ($pid | tonumber), started_at: $started}' > "$tmp_file"
    mv "$tmp_file" "$lock_file"
  fi
}

_acquire_noclobber() {
  local session=$1
  local force=${2:-""}

  mkdir -p "$LOCKS_DIR"
  local lock_file="$LOCKS_DIR/${session}.lock"

  # Handle --force flag: remove existing lock first
  if [ "$force" = "--force" ] && [ -f "$lock_file" ]; then
    local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    echo "Warning: Overriding existing lock for session '$session' (PID $existing_pid)" >&2
    rm -f "$lock_file"
  fi

  # Atomic lock creation using noclobber
  # This prevents TOCTOU race conditions
  if ! (set -C; echo "$$" > "$lock_file") 2>/dev/null; then
    # Lock file exists - check if it's stale
    if [ -f "$lock_file" ]; then
      local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)

      if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        # PID is alive - lock is active
        echo "Error: Session '$session' is already running (PID $existing_pid)" >&2
        echo "  Use --force to override" >&2
        return 1
      else
        # Stale lock - PID no longer running, remove and retry
        echo "Cleaning up stale lock for session '$session'" >&2
        rm -f "$lock_file"
        if ! (set -C; echo "$$" > "$lock_file") 2>/dev/null; then
          # Another process won the race
          echo "Error: Failed to acquire lock for session '$session'" >&2
          return 1
        fi
      fi
    fi
  fi

  _write_lock_metadata "$session" "$lock_file" "atomic"
  return 0
}

acquire_flock() {
  local session=$1
  local force=${2:-""}
  local lock_tool=${3:-"flock"}

  mkdir -p "$LOCKS_DIR"
  local lock_file="$LOCKS_DIR/${session}.lock"

  # Handle --force flag: remove existing lock first
  if [ "$force" = "--force" ] && [ -f "$lock_file" ]; then
    local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    echo "Warning: Overriding existing lock for session '$session' (PID $existing_pid)" >&2
    rm -f "$lock_file"
  fi

  if [ "$lock_tool" = "flock" ]; then
    local lock_fd
    exec {lock_fd}<> "$lock_file"
    if ! flock -n "$lock_fd"; then
      local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
      exec {lock_fd}>&-
      if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Error: Session '$session' is already running (PID $existing_pid)" >&2
        echo "  Use --force to override" >&2
      else
        echo "Error: Failed to acquire lock for session '$session'" >&2
      fi
      return 1
    fi

    LOCK_FD=$lock_fd
    LOCK_SESSION=$session
    LOCK_TOOL="flock"
  elif [ "$lock_tool" = "shlock" ]; then
    if ! shlock -f "$lock_file" -p "$$" 2>/dev/null; then
      local existing_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
      if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Error: Session '$session' is already running (PID $existing_pid)" >&2
        echo "  Use --force to override" >&2
      else
        echo "Error: Failed to acquire lock for session '$session'" >&2
      fi
      return 1
    fi

    LOCK_SESSION=$session
    LOCK_TOOL="shlock"
  else
    return 1
  fi

  _write_lock_metadata "$session" "$lock_file" "direct"
  return 0
}

# Acquire a lock for a session
# Usage: acquire_lock "$session" [--force]
# Returns 0 on success, 1 if locked by another process
acquire_lock() {
  local session=$1
  local force=${2:-""}
  local lock_tool
  lock_tool=$(detect_flock)

  if [ "$lock_tool" = "noclobber" ]; then
    _acquire_noclobber "$session" "$force"
    return $?
  fi

  acquire_flock "$session" "$force" "$lock_tool"
  return $?
}

# Release a lock for a session
# Usage: release_lock "$session"
# Only releases if current process owns the lock (prevents accidental release of other process's lock)
release_lock() {
  local session=$1
  local lock_file="$LOCKS_DIR/${session}.lock"

  if [ -n "$LOCK_FD" ] && [ "$LOCK_SESSION" = "$session" ]; then
    exec {LOCK_FD}>&-
    LOCK_FD=""
    LOCK_SESSION=""
    LOCK_TOOL=""
  fi

  if [ -f "$lock_file" ]; then
    local lock_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
    if [ "$lock_pid" = "$$" ]; then
      rm -f "$lock_file"
    fi
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

# Reset in-progress beads for a stale session (prevents orphaned claims).
# Usage: cleanup_orphaned_beads "$session"
cleanup_orphaned_beads() {
  local session=$1
  local label_prefix=${BEADS_LABEL_PREFIX:-"pipeline/"}

  [ -z "$session" ] && return 0

  if ! command -v bd >/dev/null 2>&1; then
    return 0
  fi

  local label="${label_prefix}${session}"
  local in_progress
  in_progress=$(bd list --label="$label" --status=in_progress --json 2>/dev/null || echo "[]")

  local bead_ids
  bead_ids=$(echo "$in_progress" | jq -r '.[]? | .id // empty' 2>/dev/null)

  if [ -z "$bead_ids" ]; then
    return 0
  fi

  echo "Releasing orphaned beads for session '$session'" >&2

  local bead_id
  for bead_id in $bead_ids; do
    bd update "$bead_id" --status=open >/dev/null 2>&1 || true
  done
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
      cleanup_orphaned_beads "$session"
    fi
  done
}
