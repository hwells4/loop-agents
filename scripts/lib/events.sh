#!/bin/bash
# Event Spine Helpers
# Append-only event log utilities for events.jsonl

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

EVENTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$EVENTS_SCRIPT_DIR}"

if [ -f "$LIB_DIR/lock.sh" ]; then
  source "$LIB_DIR/lock.sh"
fi

# Build events.jsonl path for a session.
# Usage: events_file_path "$session" ["$run_root"]
events_file_path() {
  local session=$1
  local run_root=${2:-"${PROJECT_ROOT:-$(pwd)}/.claude/pipeline-runs"}

  echo "$run_root/$session/events.jsonl"
}

events_default_run_root() {
  echo "${PIPELINE_RUN_ROOT:-${PROJECT_ROOT:-$(pwd)}/.claude/pipeline-runs}"
}

_ensure_events_dir() {
  local events_file=$1
  local events_dir
  events_dir=$(dirname "$events_file")
  mkdir -p "$events_dir"
}

_warn_invalid_event_line() {
  local events_file=$1
  local invalid_idx=$2
  local total_lines=$3

  if [ "$invalid_idx" -eq "$total_lines" ]; then
    echo "Warning: Skipping truncated final event line in $events_file" >&2
  else
    echo "Warning: Skipping invalid event line in $events_file" >&2
  fi
}

# Append event to events.jsonl with an exclusive lock.
# Usage: append_event "$type" "$session" "$cursor_json" "$data_json"
_do_append_event() {
  local events_file=$1
  local event_json=$2
  printf '%s\n' "$event_json" >> "$events_file"
}

append_event() {
  local type=$1
  local session=$2
  local cursor_json=$3
  local data_json=${4:-"{}"}

  local events_file
  events_file=$(events_file_path "$session")
  _ensure_events_dir "$events_file"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  if [ -z "$cursor_json" ] || [ "$cursor_json" = "null" ]; then
    cursor_json="null"
  fi
  if [ -z "$data_json" ] || [ "$data_json" = "null" ]; then
    data_json="{}"
  fi

  local event_json
  if ! event_json=$(jq -c -n \
    --arg ts "$timestamp" \
    --arg type "$type" \
    --arg session "$session" \
    --argjson cursor "$cursor_json" \
    --argjson data "$data_json" \
    '{ts: $ts, type: $type, session: $session, cursor: $cursor, data: $data}'); then
    echo "Error: Failed to build event JSON" >&2
    return 1
  fi

  if type with_exclusive_file_lock &>/dev/null; then
    with_exclusive_file_lock "$events_file" _do_append_event "$events_file" "$event_json"
  else
    _do_append_event "$events_file" "$event_json"
  fi
}

# Read events.jsonl as a JSON array.
# Usage: read_events_file "$events_file"
read_events_file() {
  local events_file=$1
  _ensure_events_dir "$events_file"

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
    _warn_invalid_event_line "$events_file" "$invalid_idx" "$total_lines"
  fi

  if [ "$valid_count" -eq 0 ]; then
    echo "[]"
  else
    jq -s '.' "$tmp_file"
  fi

  rm -f "$tmp_file"
}

# Read events.jsonl as a JSON array.
# Usage: read_events "$session"
read_events() {
  local session=$1
  local events_file
  events_file=$(events_file_path "$session")
  read_events_file "$events_file"
}

# Return the most recent event, optionally filtered by type.
# Usage: last_event "$session" ["$type"]
last_event() {
  local session=$1
  local type=${2:-""}

  local events_json
  events_json=$(read_events "$session")

  if [ -z "$type" ]; then
    echo "$events_json" | jq -c '.[-1] // null'
  else
    echo "$events_json" | jq -c --arg type "$type" '[.[] | select(.type == $type)] | last // null'
  fi
}

# Read events starting from an offset (count of events already processed).
# Usage: tail_events "$session" "$offset"
tail_events() {
  local session=$1
  local offset=${2:-0}
  if [ "$offset" -lt 0 ]; then
    offset=0
  fi

  local events_file
  events_file=$(events_file_path "$session")
  _ensure_events_dir "$events_file"

  if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
    echo "[]"
    return 0
  fi

  local start_line=$((offset + 1))
  local tmp_file
  tmp_file=$(mktemp)
  local total_lines=0
  local invalid_idx=0
  local invalid_count=0
  local valid_count=0
  local line=""

  while IFS= read -r line || [ -n "$line" ]; do
    total_lines=$((total_lines + 1))
    if [ "$total_lines" -lt "$start_line" ]; then
      continue
    fi

    if echo "$line" | jq -e '.' >/dev/null 2>&1; then
      printf '%s\n' "$line" >> "$tmp_file"
      valid_count=$((valid_count + 1))
    else
      invalid_idx=$total_lines
      invalid_count=$((invalid_count + 1))
    fi
  done < "$events_file"

  if [ "$invalid_count" -gt 0 ]; then
    _warn_invalid_event_line "$events_file" "$invalid_idx" "$total_lines"
  fi

  if [ "$valid_count" -eq 0 ]; then
    echo "[]"
  else
    jq -s '.' "$tmp_file"
  fi

  rm -f "$tmp_file"
}

# Count valid events in events.jsonl.
# Usage: count_events "$session"
count_events() {
  local session=$1
  local events_file
  events_file=$(events_file_path "$session")
  _ensure_events_dir "$events_file"

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
    _warn_invalid_event_line "$events_file" "$invalid_idx" "$total_lines"
  fi

  echo "$valid_count"
}

#-------------------------------------------------------------------------------
# Observability helpers (status/tail)
#-------------------------------------------------------------------------------

events_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

events_int_or_default() {
  local value=$1
  local fallback=$2
  if events_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

events_parse_epoch() {
  local ts=$1
  if [ -z "$ts" ] || [ "$ts" = "null" ]; then
    return 0
  fi

  local epoch
  epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null)
  if [ -z "$epoch" ]; then
    epoch=$(date -d "$ts" "+%s" 2>/dev/null)
  fi

  if [ -n "$epoch" ]; then
    echo "$epoch"
  fi
}

events_now_epoch() {
  if [ -n "${EVENTS_NOW_EPOCH:-}" ]; then
    echo "$EVENTS_NOW_EPOCH"
  else
    date -u "+%s"
  fi
}

events_elapsed_seconds() {
  local ts=$1
  local epoch
  epoch=$(events_parse_epoch "$ts")
  if [ -z "$epoch" ]; then
    echo ""
    return 0
  fi

  local now_epoch
  now_epoch=$(events_now_epoch)
  local elapsed=$((now_epoch - epoch))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi
  echo "$elapsed"
}

events_format_duration() {
  local seconds=$1
  seconds=$(events_int_or_default "$seconds" 0)
  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s"
    return 0
  fi
  if [ "$seconds" -lt 3600 ]; then
    echo "$((seconds / 60))m"
    return 0
  fi
  if [ "$seconds" -lt 86400 ]; then
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    echo "${hours}h${minutes}m"
    return 0
  fi
  local days=$((seconds / 86400))
  local hours=$(((seconds % 86400) / 3600))
  echo "${days}d${hours}h"
}

events_relative_time() {
  local ts=$1
  local elapsed
  elapsed=$(events_elapsed_seconds "$ts")
  if [ -z "$elapsed" ]; then
    echo ""
    return 0
  fi
  echo "$(events_format_duration "$elapsed") ago"
}

events_time_of_day() {
  local ts=$1
  if [ -z "$ts" ] || [ "$ts" = "null" ]; then
    echo "??:??:??"
    return 0
  fi

  local time_part="${ts#*T}"
  time_part="${time_part%Z}"
  time_part="${time_part%%.*}"
  if [ -n "$time_part" ] && [ "$time_part" != "$ts" ]; then
    echo "$time_part"
    return 0
  fi

  local epoch
  epoch=$(events_parse_epoch "$ts")
  if [ -n "$epoch" ]; then
    date -u -d "@$epoch" "+%H:%M:%S" 2>/dev/null || date -u -r "$epoch" "+%H:%M:%S"
    return 0
  fi

  echo "??:??:??"
}

events_last_cursor_event() {
  local events_json=$1
  if [ -z "$events_json" ] || [ "$events_json" = "[]" ]; then
    echo "null"
    return 0
  fi

  echo "$events_json" | jq -c \
    '[.[] | select(.cursor != null and .cursor.node_path != null and .type != "session_start" and .type != "session_complete")] | reverse | .[0] // null'
}

events_consecutive_errors() {
  local events_json=$1
  if [ -z "$events_json" ] || [ "$events_json" = "[]" ]; then
    echo "0"
    return 0
  fi

  echo "$events_json" | jq -r \
    'reverse
     | reduce .[] as $event ({count:0, stopped:false};
         if .stopped then .
         elif ($event.type // "") == "error" then .count += 1
         else .stopped = true end)
     | .count'
}

events_iterations_without_progress() {
  local events_json=$1
  if [ -z "$events_json" ] || [ "$events_json" = "[]" ]; then
    echo "0"
    return 0
  fi

  echo "$events_json" | jq -r \
    'reverse
     | reduce .[] as $event ({count:0, stopped:false};
         if .stopped then .
         elif ($event.type // "") == "iteration_complete" then
           (if ((($event.data.signals.plateau_suspected // false) == true) or (($event.data.summary // "") | length == 0))
            then .count += 1
            else .stopped = true end)
         else . end)
     | .count'
}

events_health_score() {
  local consecutive_errors=$1
  local no_progress=$2
  consecutive_errors=$(events_int_or_default "$consecutive_errors" 0)
  no_progress=$(events_int_or_default "$no_progress" 0)

  awk -v errs="$consecutive_errors" -v stalls="$no_progress" 'BEGIN {
    score = 1.0 - (0.1 * errs) - (0.05 * stalls);
    if (score < 0) { score = 0; }
    printf "%.2f", score;
  }'
}

events_health_label() {
  local score=$1
  awk -v score="$score" 'BEGIN { if (score < 0.3) { print "warning"; } else { print "ok"; } }'
}

events_print_status() {
  local session=$1
  local run_root=${2:-"$(events_default_run_root)"}

  if [ -z "$session" ]; then
    echo "Usage: events_print_status <session>" >&2
    return 1
  fi

  local session_dir="$run_root/$session"
  local events_file="$session_dir/events.jsonl"
  local plan_file="$session_dir/plan.json"
  local lock_file="${PROJECT_ROOT:-$(pwd)}/.claude/locks/${session}.lock"

  if [ ! -f "$events_file" ]; then
    echo "No events found: $session"
    return 1
  fi

  local events_json
  events_json=$(read_events_file "$events_file")

  local last_event
  last_event=$(echo "$events_json" | jq -c '.[-1] // null')
  local last_type
  last_type=$(echo "$last_event" | jq -r '.type // "unknown"')
  local last_ts
  last_ts=$(echo "$last_event" | jq -r '.ts // ""')
  local last_age=""
  if [ -n "$last_ts" ] && [ "$last_ts" != "null" ]; then
    last_age=$(events_relative_time "$last_ts")
  fi

  local cursor_event
  cursor_event=$(events_last_cursor_event "$events_json")
  local node_path
  node_path=$(echo "$cursor_event" | jq -r '.cursor.node_path // ""')
  local node_run
  node_run=$(echo "$cursor_event" | jq -r '.cursor.node_run // 0')
  local iteration
  iteration=$(echo "$cursor_event" | jq -r '.cursor.iteration // 0')

  node_run=$(events_int_or_default "$node_run" 0)
  iteration=$(events_int_or_default "$iteration" 0)

  local node_id=""
  local node_ref=""
  local node_runs="1"
  if [ -n "$node_path" ] && [ -f "$plan_file" ]; then
    node_id=$(jq -r --arg path "$node_path" \
      '([.nodes[] | select(.path == $path)] | .[0].id // empty)' "$plan_file" 2>/dev/null)
    node_ref=$(jq -r --arg path "$node_path" \
      '([.nodes[] | select(.path == $path)] | .[0].ref // empty)' "$plan_file" 2>/dev/null)
    node_runs=$(jq -r --arg path "$node_path" \
      '([.nodes[] | select(.path == $path)] | .[0].runs // 1)' "$plan_file" 2>/dev/null)
  fi

  if [ -z "$node_id" ] || [ "$node_id" = "null" ]; then
    node_id=$(echo "$cursor_event" | jq -r '.data.id // empty')
  fi
  if [ "$node_id" = "null" ]; then
    node_id=""
  fi
  if [ "$node_ref" = "null" ]; then
    node_ref=""
  fi

  node_runs=$(events_int_or_default "$node_runs" 1)
  if [ "$node_run" -le 0 ]; then
    node_run=1
  fi

  local errors_total
  errors_total=$(echo "$events_json" | jq '[.[] | select(.type == "error")] | length')
  errors_total=$(events_int_or_default "$errors_total" 0)

  local consecutive_errors
  consecutive_errors=$(events_consecutive_errors "$events_json")
  local no_progress
  no_progress=$(events_iterations_without_progress "$events_json")
  local health_score
  health_score=$(events_health_score "$consecutive_errors" "$no_progress")
  local health_label
  health_label=$(events_health_label "$health_score")

  local status="unknown"
  if [ "$last_type" = "session_complete" ]; then
    status="complete"
  else
    if [ -f "$lock_file" ]; then
      local pid
      pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        status="running"
      else
        status="failed"
      fi
    elif [ "$errors_total" -gt 0 ]; then
      status="failed"
    fi
  fi

  local started_ts
  started_ts=$(echo "$events_json" | jq -r '[.[] | select(.type == "session_start")][0].ts // empty')
  local duration=""
  if [ -n "$started_ts" ] && [ "$started_ts" != "null" ]; then
    local elapsed
    elapsed=$(events_elapsed_seconds "$started_ts")
    if [ -n "$elapsed" ]; then
      duration=$(events_format_duration "$elapsed")
    fi
  fi

  echo "Session: $session"
  echo "Status: $status"
  if [ -n "$node_path" ]; then
    if [ -n "$node_id" ] && [ -n "$node_ref" ]; then
      echo "Node: $node_path (${node_id}/${node_ref})"
    elif [ -n "$node_id" ]; then
      echo "Node: $node_path (${node_id})"
    else
      echo "Node: $node_path"
    fi
    echo "Run: $node_run/$node_runs"
    echo "Iteration: $iteration"
  fi
  if [ -n "$last_type" ] && [ "$last_type" != "null" ]; then
    if [ -n "$last_age" ]; then
      echo "Last event: $last_type ($last_age)"
    else
      echo "Last event: $last_type"
    fi
  fi
  echo "Health: $health_label"
  if [ "$health_label" = "warning" ]; then
    echo "Warning: health below 0.30"
  fi
  echo "Errors: $errors_total"
  if [ -n "$duration" ]; then
    echo "Duration: $duration"
  fi
}

events_format_event_line() {
  local event_json=$1
  if [ -z "$event_json" ] || [ "$event_json" = "null" ]; then
    return 0
  fi

  local ts
  ts=$(echo "$event_json" | jq -r '.ts // empty')
  local time_part
  time_part=$(events_time_of_day "$ts")
  local type
  type=$(echo "$event_json" | jq -r '.type // "unknown"')
  local node_path
  node_path=$(echo "$event_json" | jq -r '.cursor.node_path // empty')
  local node_run
  node_run=$(echo "$event_json" | jq -r '.cursor.node_run // empty')
  local iteration
  iteration=$(echo "$event_json" | jq -r '.cursor.iteration // empty')
  local provider
  provider=$(echo "$event_json" | jq -r '.cursor.provider // empty')

  local details=""
  case "$type" in
    iteration_start)
      details="node=$node_path run=$node_run iter=$iteration"
      local model
      model=$(echo "$event_json" | jq -r '.data.model // empty')
      local data_provider
      data_provider=$(echo "$event_json" | jq -r '.data.provider // empty')
      if [ -n "$data_provider" ]; then
        details+=" provider=$data_provider"
      elif [ -n "$provider" ]; then
        details+=" provider=$provider"
      fi
      [ -n "$model" ] && details+=" model=$model"
      ;;
    iteration_complete)
      details="node=$node_path run=$node_run iter=$iteration"
      local summary
      summary=$(echo "$event_json" | jq -r '.data.summary // empty')
      if [ -n "$summary" ]; then
        summary=${summary//$'\n'/ }
        if [ ${#summary} -gt 80 ]; then
          summary="${summary:0:77}..."
        fi
        details+=" summary=\"${summary}\""
      fi
      ;;
    worker_complete)
      details="node=$node_path run=$node_run iter=$iteration"
      local exit_code
      exit_code=$(echo "$event_json" | jq -r '.data.exit_code // empty')
      [ -n "$exit_code" ] && details+=" exit=$exit_code"
      ;;
    node_start)
      local node_id
      node_id=$(echo "$event_json" | jq -r '.data.id // empty')
      local kind
      kind=$(echo "$event_json" | jq -r '.data.kind // empty')
      details="node=$node_path"
      [ -n "$node_id" ] && details+=" id=$node_id"
      [ -n "$kind" ] && details+=" kind=$kind"
      ;;
    node_run_start)
      details="node=$node_path run=$node_run"
      ;;
    node_complete)
      details="node=$node_path run=$node_run"
      ;;
    parallel_provider_start|parallel_provider_complete)
      details="node=$node_path"
      local data_provider
      data_provider=$(echo "$event_json" | jq -r '.data.provider // empty')
      if [ -n "$data_provider" ]; then
        details+=" provider=$data_provider"
      elif [ -n "$provider" ]; then
        details+=" provider=$provider"
      fi
      ;;
    decision)
      details="node=$node_path run=$node_run iter=$iteration"
      local decision
      decision=$(echo "$event_json" | jq -r '.data.decision // empty')
      local reason
      reason=$(echo "$event_json" | jq -r '.data.reason // empty')
      [ -n "$decision" ] && details+=" decision=$decision"
      [ -n "$reason" ] && details+=" reason=$reason"
      ;;
    hook_start|hook_complete)
      details="node=$node_path run=$node_run iter=$iteration"
      local hook_point
      hook_point=$(echo "$event_json" | jq -r '.data.hook_point // empty')
      local action_id
      action_id=$(echo "$event_json" | jq -r '.data.action_id // empty')
      [ -n "$hook_point" ] && details+=" point=$hook_point"
      [ -n "$action_id" ] && details+=" action=$action_id"
      ;;
    error)
      details="node=$node_path run=$node_run iter=$iteration"
      local message
      message=$(echo "$event_json" | jq -r '.data.message // empty')
      [ -n "$message" ] && details+=" message=\"$message\""
      ;;
  esac

  if [ -n "$details" ]; then
    echo "[$time_part] $type $details"
  else
    echo "[$time_part] $type"
  fi
}
