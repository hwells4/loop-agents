#!/bin/bash
# List Pipeline Runs
# Shows recent pipeline runs sorted by modification time

# List pipeline runs
# Usage: list_runs [count] [--all]
# Default: shows last 10 runs
list_runs() {
  local count=${1:-10}
  local show_all=${2:-""}
  local run_root="${PROJECT_ROOT:-.}/.claude/pipeline-runs"
  local lock_dir="${PROJECT_ROOT:-.}/.claude/locks"

  if [ ! -d "$run_root" ]; then
    echo "No pipeline runs found."
    return 0
  fi

  # Get directories sorted by modification time (most recent first)
  local dirs
  dirs=$(ls -1dt "$run_root"/*/ 2>/dev/null | head -n "$count")

  if [ -z "$dirs" ]; then
    echo "No pipeline runs found."
    return 0
  fi

  echo "Recent pipeline runs:"
  echo ""

  # Header
  printf "  %-20s %-10s %-12s %s\n" "SESSION" "STATUS" "AGE" "STAGE"
  printf "  %-20s %-10s %-12s %s\n" "-------" "------" "---" "-----"

  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    [ ! -d "$dir" ] && continue

    local session_name
    session_name=$(basename "$dir")
    local state_file="$dir/state.json"
    local lock_file="$lock_dir/${session_name}.lock"

    local run_status="unknown"
    local run_type=""
    local iterations=""
    local stage_name=""
    local started_at=""

    if [ -f "$state_file" ]; then
      run_status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null)
      run_type=$(jq -r '.type // ""' "$state_file" 2>/dev/null)
      iterations=$(jq -r '.iteration // 0' "$state_file" 2>/dev/null)
      started_at=$(jq -r '.started_at // ""' "$state_file" 2>/dev/null)

      # Get stage name from history or stages array
      stage_name=$(jq -r '.history[-1].stage // .stages[-1].name // ""' "$state_file" 2>/dev/null)
      if [ -z "$stage_name" ] || [ "$stage_name" = "null" ]; then
        stage_name=""
      fi
    fi

    # Determine actual status - check if "running" sessions have a live PID
    if [ "$run_status" = "running" ]; then
      if [ -f "$lock_file" ]; then
        local pid
        pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
          run_status="crashed"
        fi
      else
        # No lock file but status is running = crashed
        run_status="crashed"
      fi
    fi

    # Calculate age from directory modification time
    local age
    age=$(_format_age "$dir")

    # Build stage display
    local stage_display=""
    if [ -n "$stage_name" ] && [ "$stage_name" != "null" ]; then
      if [ -n "$iterations" ] && [ "$iterations" != "0" ] && [ "$iterations" != "null" ]; then
        local iter_label="iter"
        [ "$iterations" != "1" ] && iter_label="iters"
        stage_display="${stage_name} (${iterations} ${iter_label})"
      else
        stage_display="$stage_name"
      fi
    elif [ "$run_type" = "pipeline" ]; then
      stage_display="(pipeline)"
    fi

    printf "  %-20s %-10s %-12s %s\n" \
      "$session_name" \
      "$run_status" \
      "$age" \
      "$stage_display"
  done <<< "$dirs"

  echo ""
}

# Format age from directory modification time
# Usage: _format_age "/path/to/dir"
_format_age() {
  local dir=$1
  local now_epoch
  local mod_epoch

  now_epoch=$(date +%s)

  # Get modification time in seconds since epoch (macOS and Linux compatible)
  if stat -f %m "$dir" >/dev/null 2>&1; then
    # macOS
    mod_epoch=$(stat -f %m "$dir")
  else
    # Linux
    mod_epoch=$(stat -c %Y "$dir")
  fi

  local elapsed=$((now_epoch - mod_epoch))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi

  _format_duration "$elapsed"
}

# Format duration in human-readable form
# Usage: _format_duration <seconds>
_format_duration() {
  local seconds=$1

  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s ago"
    return 0
  fi

  if [ "$seconds" -lt 3600 ]; then
    echo "$((seconds / 60))m ago"
    return 0
  fi

  if [ "$seconds" -lt 86400 ]; then
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    if [ "$minutes" -gt 0 ]; then
      echo "${hours}h${minutes}m ago"
    else
      echo "${hours}h ago"
    fi
    return 0
  fi

  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  if [ "$hours" -gt 0 ]; then
    echo "${days}d${hours}h ago"
  else
    echo "${days}d ago"
  fi
}
