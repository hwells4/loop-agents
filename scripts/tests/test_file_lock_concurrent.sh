#!/bin/bash
# Tests for concurrent file locking with events.jsonl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/lock.sh"
source "$SCRIPT_DIR/lib/events.sh"

_wait_for_file() {
  local file=$1
  local retries=${2:-50}
  local delay=${3:-0.1}
  local count=0

  while [ ! -f "$file" ] && [ $count -lt $retries ]; do
    sleep "$delay"
    count=$((count + 1))
  done

  [ -f "$file" ]
}

_with_lock_tool() {
  local tool=$1
  shift

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "$tool"; }

  "$@"
  local result=$?

  eval "$original_detect"
  return $result
}

_hold_lock_with_ready() {
  local ready_file=$1
  local sleep_seconds=$2
  touch "$ready_file"
  sleep "$sleep_seconds"
}

_run_concurrent_appends() {
  local session=$1
  local providers=$2
  local events_per_provider=$3

  for provider_idx in $(seq 1 "$providers"); do
    (
      local provider="provider-$(printf '%02d' "$provider_idx")"
      for iter in $(seq 1 "$events_per_provider"); do
        local cursor_json
        cursor_json=$(jq -c -n --arg provider "$provider" --argjson iter "$iter" \
          '{provider: $provider, iteration: $iter}')
        local data_json
        data_json=$(jq -c -n --arg msg "event-$provider-$iter" '{message: $msg}')
        append_event "test_event" "$session" "$cursor_json" "$data_json" >/dev/null
      done
    ) &
  done

  wait
}

_assert_events_file_count() {
  local events_file=$1
  local expected=$2

  local actual
  actual=$(wc -l < "$events_file" | tr -d ' ')
  assert_eq "$expected" "$actual" "event count matches expected"
}

_assert_events_file_integrity() {
  local events_file=$1
  local expected=$2

  local parsed_count=""
  if ! parsed_count=$(jq -s 'length' "$events_file" 2>/dev/null); then
    assert_eq "0" "1" "events.jsonl lines parse as JSON"
    return
  fi

  assert_eq "$expected" "$parsed_count" "event JSON array length matches expected"
}

test_concurrent_append_event_no_data_loss() {
  local tmp
  tmp=$(create_test_dir "events-lock")
  local previous_project_root=${PROJECT_ROOT:-""}
  export PROJECT_ROOT="$tmp"

  local session="concurrent"
  _with_lock_tool "noclobber" _run_concurrent_appends "$session" 5 10

  local events_file
  events_file=$(events_file_path "$session")
  _assert_events_file_count "$events_file" "50"

  cleanup_test_dir "$tmp"
  if [ -n "$previous_project_root" ]; then
    export PROJECT_ROOT="$previous_project_root"
  else
    unset PROJECT_ROOT
  fi
}

test_events_jsonl_line_integrity() {
  local tmp
  tmp=$(create_test_dir "events-lock")
  local previous_project_root=${PROJECT_ROOT:-""}
  export PROJECT_ROOT="$tmp"

  local session="integrity"
  _with_lock_tool "noclobber" _run_concurrent_appends "$session" 4 8

  local events_file
  events_file=$(events_file_path "$session")
  _assert_events_file_integrity "$events_file" "32"

  cleanup_test_dir "$tmp"
  if [ -n "$previous_project_root" ]; then
    export PROJECT_ROOT="$previous_project_root"
  else
    unset PROJECT_ROOT
  fi
}

test_append_event_flock_serialization() {
  if ! command -v flock >/dev/null 2>&1; then
    skip_test "flock not installed"
    return
  fi

  local tmp
  tmp=$(create_test_dir "events-lock")
  local previous_project_root=${PROJECT_ROOT:-""}
  export PROJECT_ROOT="$tmp"

  local session="serialize"
  local events_file
  events_file=$(events_file_path "$session")
  _ensure_events_dir "$events_file"

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "flock"; }

  local ready_file="$tmp/ready"
  (
    with_exclusive_file_lock "$events_file" _hold_lock_with_ready "$ready_file" 3
  ) &
  local pid=$!

  if ! _wait_for_file "$ready_file"; then
    kill "$pid" >/dev/null 2>&1
    wait "$pid" >/dev/null 2>&1
    eval "$original_detect"
    assert_file_exists "$ready_file" "lock holder started"
    cleanup_test_dir "$tmp"
    return
  fi

  local start_time=$SECONDS
  append_event "serialize" "$session" "{}" "{}"
  local elapsed=$((SECONDS - start_time))

  wait "$pid" >/dev/null 2>&1
  eval "$original_detect"

  assert_gt "$elapsed" "1" "append_event waits for flock lock"

  cleanup_test_dir "$tmp"
  if [ -n "$previous_project_root" ]; then
    export PROJECT_ROOT="$previous_project_root"
  else
    unset PROJECT_ROOT
  fi
}

test_flock_vs_noclobber_consistency() {
  local tmp
  tmp=$(create_test_dir "events-lock")
  local previous_project_root=${PROJECT_ROOT:-""}
  export PROJECT_ROOT="$tmp"

  local session="consistency-noclobber"
  _with_lock_tool "noclobber" _run_concurrent_appends "$session" 3 6
  local events_file
  events_file=$(events_file_path "$session")
  _assert_events_file_count "$events_file" "18"
  _assert_events_file_integrity "$events_file" "18"

  if command -v flock >/dev/null 2>&1; then
    session="consistency-flock"
    _with_lock_tool "flock" _run_concurrent_appends "$session" 3 6
    events_file=$(events_file_path "$session")
    _assert_events_file_count "$events_file" "18"
    _assert_events_file_integrity "$events_file" "18"
  else
    skip_test "flock not installed"
  fi

  cleanup_test_dir "$tmp"
  if [ -n "$previous_project_root" ]; then
    export PROJECT_ROOT="$previous_project_root"
  else
    unset PROJECT_ROOT
  fi
}

echo ""
echo "==============================================================="
echo "  File Lock Concurrency"
echo "==============================================================="
echo ""

run_test "concurrent append_event no data loss" test_concurrent_append_event_no_data_loss
run_test "events.jsonl line integrity" test_events_jsonl_line_integrity
run_test "append_event flock serialization" test_append_event_flock_serialization
run_test "flock vs noclobber consistency" test_flock_vs_noclobber_consistency

test_summary
