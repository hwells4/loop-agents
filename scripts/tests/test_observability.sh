#!/bin/bash
# Observability helper tests (event-based status/tail)

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

_write_lock_file() {
  local root_dir=$1
  local session=$2
  local started=$3

  mkdir -p "$root_dir/.claude/locks"
  jq -n --argjson pid "$$" --arg started "$started" \
    '{pid: $pid, started_at: $started}' > "$root_dir/.claude/locks/${session}.lock"
}

#-------------------------------------------------------------------------------
# Status output tests
#-------------------------------------------------------------------------------

test_events_print_status_basic() {
  local tmp
  tmp=$(create_test_dir "events-status")
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="obs-basic"
  local run_dir
  run_dir=$(setup_test_session "$tmp" "$session")

  _write_lock_file "$tmp" "$session" "2026-01-15T10:00:00Z"

  cat > "$run_dir/events.jsonl" << 'EOF'
{"ts":"2026-01-15T10:00:00Z","type":"session_start","session":"obs-basic","cursor":{"node_path":"0","node_run":0,"iteration":0},"data":{"session":"obs-basic"}}
{"ts":"2026-01-15T10:10:00Z","type":"node_start","session":"obs-basic","cursor":{"node_path":"1","node_run":0,"iteration":0},"data":{"id":"fix","kind":"stage","path":"1"}}
{"ts":"2026-01-15T10:15:00Z","type":"iteration_start","session":"obs-basic","cursor":{"node_path":"1","node_run":2,"iteration":7},"data":{"id":"fix","provider":"claude","model":"default"}}
{"ts":"2026-01-15T10:17:00Z","type":"iteration_complete","session":"obs-basic","cursor":{"node_path":"1","node_run":2,"iteration":7},"data":{"summary":"did work","signals":{"plateau_suspected":false}}}
{"ts":"2026-01-15T10:17:10Z","type":"worker_complete","session":"obs-basic","cursor":{"node_path":"1","node_run":2,"iteration":7},"data":{"exit_code":0,"result_file":"result.json"}}
EOF

  cat > "$run_dir/plan.json" << 'EOF'
{"nodes":[{"path":"1","id":"fix","kind":"stage","ref":"ralph","runs":3}]}
EOF

  EVENTS_NOW_EPOCH=$(date -u -d "2026-01-15T10:45:00Z" "+%s")
  export EVENTS_NOW_EPOCH

  local output
  output=$(events_print_status "$session")

  assert_contains "$output" "Session: obs-basic" "prints session name"
  assert_contains "$output" "Status: running" "prints running status"
  assert_contains "$output" "Node: 1 (fix/ralph)" "prints node label"
  assert_contains "$output" "Run: 2/3" "prints run counters"
  assert_contains "$output" "Iteration: 7" "prints iteration"
  assert_contains "$output" "Last event: worker_complete" "prints last event"
  assert_contains "$output" "Health: ok" "prints health label"
  assert_contains "$output" "Errors: 0" "prints error count"
  assert_contains "$output" "Duration: 45m" "prints duration"

  unset EVENTS_NOW_EPOCH
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

test_events_print_status_warning() {
  local tmp
  tmp=$(create_test_dir "events-health")
  local previous_root=${PROJECT_ROOT:-}

  export PROJECT_ROOT="$tmp"
  local session="obs-warning"
  local run_dir
  run_dir=$(setup_test_session "$tmp" "$session")

  cat > "$run_dir/events.jsonl" << 'EOF'
{"ts":"2026-01-15T10:00:00Z","type":"session_start","session":"obs-warning","cursor":{"node_path":"0","node_run":0,"iteration":0},"data":{"session":"obs-warning"}}
{"ts":"2026-01-15T10:01:00Z","type":"iteration_complete","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":1},"data":{"summary":"","signals":{"plateau_suspected":true}}}
{"ts":"2026-01-15T10:02:00Z","type":"iteration_complete","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":2},"data":{"summary":"","signals":{"plateau_suspected":true}}}
{"ts":"2026-01-15T10:03:00Z","type":"iteration_complete","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":3},"data":{"summary":"","signals":{"plateau_suspected":true}}}
{"ts":"2026-01-15T10:04:00Z","type":"iteration_complete","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":4},"data":{"summary":"","signals":{"plateau_suspected":true}}}
{"ts":"2026-01-15T10:05:00Z","type":"iteration_complete","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"summary":"","signals":{"plateau_suspected":true}}}
{"ts":"2026-01-15T10:06:00Z","type":"error","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"message":"err-1"}}
{"ts":"2026-01-15T10:07:00Z","type":"error","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"message":"err-2"}}
{"ts":"2026-01-15T10:08:00Z","type":"error","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"message":"err-3"}}
{"ts":"2026-01-15T10:09:00Z","type":"error","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"message":"err-4"}}
{"ts":"2026-01-15T10:10:00Z","type":"error","session":"obs-warning","cursor":{"node_path":"1","node_run":1,"iteration":5},"data":{"message":"err-5"}}
EOF

  EVENTS_NOW_EPOCH=$(date -u -d "2026-01-15T10:12:00Z" "+%s")
  export EVENTS_NOW_EPOCH

  local output
  output=$(events_print_status "$session")

  assert_contains "$output" "Health: warning" "prints warning health"
  assert_contains "$output" "Warning: health below 0.30" "prints warning banner"
  assert_contains "$output" "Errors: 5" "prints error count"

  unset EVENTS_NOW_EPOCH
  cleanup_test_dir "$tmp"
  _reset_project_root "$previous_root"
}

#-------------------------------------------------------------------------------
# Event formatting tests
#-------------------------------------------------------------------------------

test_events_format_event_line_iteration_start() {
  local event_json='{"ts":"2026-01-15T10:45:01Z","type":"iteration_start","cursor":{"node_path":"1.0","node_run":2,"iteration":7},"data":{"provider":"claude","model":"haiku"}}'
  local line
  line=$(events_format_event_line "$event_json")

  assert_eq "[10:45:01] iteration_start node=1.0 run=2 iter=7 provider=claude model=haiku" "$line" \
    "formats iteration_start line"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Observability Helpers"
echo "==============================================================="
echo ""

run_test "events_print_status basic output" test_events_print_status_basic
run_test "events_print_status warning output" test_events_print_status_warning
run_test "events_format_event_line iteration_start" test_events_format_event_line_iteration_start

test_summary
