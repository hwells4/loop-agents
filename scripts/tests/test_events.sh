#!/bin/bash
# Tests for event spine helpers (scripts/lib/events.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/events.sh"

_reset_project_root() {
  local previous_root=$1

  if [ -n "$previous_root" ]; then
    export PROJECT_ROOT="$previous_root"
  else
    unset PROJECT_ROOT
  fi
}

#-------------------------------------------------------------------------------
# Event append/read tests
#-------------------------------------------------------------------------------

test_append_event_creates_entry() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-append"

  append_event "start" "$session" '{"step":1}' '{"ok":true}'
  local result=$?
  assert_eq "0" "$result" "append_event succeeds"

  local events_file
  events_file=$(events_file_path "$session")
  assert_file_exists "$events_file" "events.jsonl created"

  local line
  line=$(head -n 1 "$events_file")
  local type
  type=$(echo "$line" | jq -r '.type')
  local session_value
  session_value=$(echo "$line" | jq -r '.session')
  local cursor_step
  cursor_step=$(echo "$line" | jq -r '.cursor.step')
  local data_ok
  data_ok=$(echo "$line" | jq -r '.data.ok')

  assert_eq "start" "$type" "event type recorded"
  assert_eq "$session" "$session_value" "session recorded"
  assert_eq "1" "$cursor_step" "cursor recorded"
  assert_eq "true" "$data_ok" "data recorded"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_read_events_returns_empty_for_missing_file() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-empty"

  local events
  events=$(read_events "$session")

  assert_eq "[]" "$events" "missing events file returns empty array"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_read_events_skips_truncated_line() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-truncated"
  local events_file
  events_file=$(events_file_path "$session")

  mkdir -p "$(dirname "$events_file")"
  printf '%s\n' \
    '{"ts":"t","type":"start","session":"events-truncated","cursor":null,"data":{}}' \
    '{"ts":"t","type":"bad","session":"events-truncated","cursor":' \
    > "$events_file"

  local stderr_file="$tmp/stderr"
  local events
  events=$(read_events "$session" 2> "$stderr_file")
  local count
  count=$(echo "$events" | jq 'length')
  local warning
  warning=$(cat "$stderr_file")

  assert_eq "1" "$count" "truncated final line ignored"
  assert_contains "$warning" "truncated final event line" "warning emitted for truncated line"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

#-------------------------------------------------------------------------------
# Event query tests
#-------------------------------------------------------------------------------

test_tail_events_respects_offset() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-tail"

  append_event "start" "$session" '{"step":1}' '{}'
  append_event "progress" "$session" '{"step":2}' '{}'
  append_event "stop" "$session" '{"step":3}' '{}'

  local events
  events=$(tail_events "$session" 1)
  local count
  count=$(echo "$events" | jq 'length')
  local first_type
  first_type=$(echo "$events" | jq -r '.[0].type')

  assert_eq "2" "$count" "tail_events returns events after offset"
  assert_eq "progress" "$first_type" "tail_events starts at expected event"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_last_event_filters_type() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-last"

  append_event "start" "$session" '{"step":1}' '{}'
  append_event "progress" "$session" '{"step":2}' '{}'
  append_event "progress" "$session" '{"step":3}' '{}'

  local last_any
  last_any=$(last_event "$session")
  local last_any_type
  last_any_type=$(echo "$last_any" | jq -r '.type')
  local last_progress
  last_progress=$(last_event "$session" "progress")
  local last_progress_step
  last_progress_step=$(echo "$last_progress" | jq -r '.cursor.step')
  local missing_type
  missing_type=$(last_event "$session" "missing")

  assert_eq "progress" "$last_any_type" "last_event returns most recent event"
  assert_eq "3" "$last_progress_step" "last_event filters by type"
  assert_eq "null" "$missing_type" "last_event returns null for missing type"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_count_events_ignores_invalid_lines() {
  local tmp
  tmp=$(create_test_dir)
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="events-count"
  local events_file
  events_file=$(events_file_path "$session")

  mkdir -p "$(dirname "$events_file")"
  printf '%s\n' \
    '{"ts":"t","type":"start","session":"events-count","cursor":null,"data":{}}' \
    '{"ts":"t","type":"bad","session":"events-count","cursor":' \
    '{"ts":"t","type":"stop","session":"events-count","cursor":null,"data":{}}' \
    > "$events_file"

  local count
  count=$(count_events "$session" 2>/dev/null)

  assert_eq "2" "$count" "count_events ignores invalid lines"

  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Event Spine Helpers"
echo "==============================================================="
echo ""

run_test "append_event creates entry" test_append_event_creates_entry
run_test "read_events returns empty" test_read_events_returns_empty_for_missing_file
run_test "read_events skips truncated line" test_read_events_skips_truncated_line
run_test "tail_events respects offset" test_tail_events_respects_offset
run_test "last_event filters type" test_last_event_filters_type
run_test "count_events ignores invalid lines" test_count_events_ignores_invalid_lines

test_summary
