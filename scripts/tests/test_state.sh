#!/bin/bash
# Tests for state snapshot reconciliation (scripts/lib/state.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/state.sh"

#-------------------------------------------------------------------------------
# Snapshot Load Tests
#-------------------------------------------------------------------------------

test_load_snapshot_marks_stale() {
  local tmp
  tmp=$(create_test_dir "state-stale")

  local state_file="$tmp/state.json"
  local events_file="$tmp/events.jsonl"

  jq -n '{event_offset: 1}' > "$state_file"
  printf '%s\n' \
    '{"ts":"t1","type":"session_start","session":"state-test","cursor":null,"data":{}}' \
    '{"ts":"t2","type":"iteration_start","session":"state-test","cursor":{"node_path":"0","node_run":1,"iteration":1},"data":{}}' \
    > "$events_file"

  load_snapshot "$state_file" "$events_file" >/dev/null

  assert_eq "true" "$SNAPSHOT_STALE" "snapshot marked stale when offset lags"
  assert_eq "1" "$SNAPSHOT_EVENT_OFFSET" "snapshot offset preserved"
  assert_eq "2" "$SNAPSHOT_EVENT_COUNT" "snapshot event count matches"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Snapshot Reconcile Tests
#-------------------------------------------------------------------------------

test_reconcile_with_events_updates_state() {
  local tmp
  tmp=$(create_test_dir "state-reconcile")

  local state_file="$tmp/state.json"
  local events_file="$tmp/events.jsonl"

  printf '%s\n' \
    '{"ts":"2026-01-15T00:00:00Z","type":"session_start","session":"state-test","cursor":null,"data":{}}' \
    '{"ts":"2026-01-15T00:00:01Z","type":"iteration_start","session":"state-test","cursor":{"node_path":"1","node_run":1,"iteration":1},"data":{}}' \
    '{"ts":"2026-01-15T00:00:02Z","type":"iteration_complete","session":"state-test","cursor":{"node_path":"1","node_run":1,"iteration":1},"data":{}}' \
    '{"ts":"2026-01-15T00:00:03Z","type":"session_complete","session":"state-test","cursor":{"node_path":"1","node_run":1,"iteration":1},"data":{}}' \
    > "$events_file"

  reconcile_with_events "$state_file" "$events_file" "state-test" "loop"

  assert_file_exists "$state_file" "state snapshot written"
  assert_json_field "$state_file" ".status" "complete" "session marked complete"
  assert_json_field "$state_file" ".iteration" "1" "iteration captured from cursor"
  assert_json_field "$state_file" ".iteration_completed" "1" "iteration completion recorded"
  assert_json_field "$state_file" ".current_stage" "1" "current stage derived from node path"
  assert_json_field "$state_file" ".event_offset" "4" "event offset updated"

  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  State Snapshots"
echo "==============================================================="
echo ""

run_test "load_snapshot marks stale" test_load_snapshot_marks_stale
run_test "reconcile_with_events updates state" test_reconcile_with_events_updates_state

test_summary
