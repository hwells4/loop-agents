#!/bin/bash
# Tests for lock helpers (scripts/lib/lock.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/lock.sh"

_with_path() {
  local new_path=$1
  shift
  local old_path=$PATH

  export PATH="$new_path"
  "$@"
  local result=$?
  export PATH="$old_path"

  return $result
}

_reset_lock_state() {
  LOCK_FD=""
  LOCK_SESSION=""
  LOCK_TOOL=""
}

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

_spawn_lock_holder() {
  local lock_dir=$1
  local session=$2
  local ready_file=$3
  local sleep_seconds=${4:-5}

  SCRIPT_DIR="$SCRIPT_DIR" \
  LOCKS_DIR_OVERRIDE="$lock_dir" \
  SESSION_NAME="$session" \
  READY_FILE="$ready_file" \
  SLEEP_SECONDS="$sleep_seconds" \
    bash -s <<'CHILD' >/dev/null 2>&1 &
source "$SCRIPT_DIR/lib/lock.sh"
LOCKS_DIR="$LOCKS_DIR_OVERRIDE"
detect_flock() { echo "noclobber"; }
acquire_lock "$SESSION_NAME" >/dev/null 2>&1

touch "$READY_FILE"
sleep "$SLEEP_SECONDS"
CHILD

  echo $!
}

#-------------------------------------------------------------------------------
# Lock acquisition tests
#-------------------------------------------------------------------------------

test_acquire_lock_creates_file() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "alpha" >/dev/null 2>&1
  local result=$?

  eval "$original_detect"

  local lock_file="$LOCKS_DIR/alpha.lock"
  assert_eq "0" "$result" "acquire_lock succeeds"
  assert_file_exists "$lock_file" "lock file created"

  release_lock "alpha"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

test_acquire_lock_writes_json() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "bravo" >/dev/null 2>&1
  local result=$?

  eval "$original_detect"

  local lock_file="$LOCKS_DIR/bravo.lock"
  assert_eq "0" "$result" "acquire_lock succeeds"
  assert_json_field "$lock_file" ".session" "bravo" "metadata session recorded"
  assert_json_field "$lock_file" ".pid" "$$" "metadata pid recorded"
  assert_json_field_exists "$lock_file" ".started_at" "metadata start time recorded"

  release_lock "bravo"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

test_acquire_lock_conflict() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local ready_file="$tmp/ready"
  local child_pid
  child_pid=$(_spawn_lock_holder "$LOCKS_DIR" "conflict" "$ready_file" 10)

  if ! _wait_for_file "$ready_file"; then
    kill "$child_pid" >/dev/null 2>&1
    wait "$child_pid" >/dev/null 2>&1
    assert_file_exists "$ready_file" "child process acquired lock"
    LOCKS_DIR="$previous_locks_dir"
    cleanup_test_dir "$tmp"
    return
  fi

  local stderr_file="$tmp/stderr"
  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "conflict" 2> "$stderr_file"
  local result=$?

  eval "$original_detect"

  local stderr
  stderr=$(cat "$stderr_file")

  if [ "$result" -eq 0 ]; then
    release_lock "conflict"
  fi

  assert_eq "1" "$result" "second acquire fails"
  assert_contains "$stderr" "already running" "conflict emits error"

  kill "$child_pid" >/dev/null 2>&1
  wait "$child_pid" >/dev/null 2>&1

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# Lock release and stale cleanup tests
#-------------------------------------------------------------------------------

test_release_lock_removes_file() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "release" >/dev/null 2>&1
  eval "$original_detect"

  local lock_file="$LOCKS_DIR/release.lock"
  release_lock "release"

  assert_file_not_exists "$lock_file" "release_lock removes lock file"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

test_release_lock_only_owner() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local ready_file="$tmp/ready"
  local child_pid
  child_pid=$(_spawn_lock_holder "$LOCKS_DIR" "owner" "$ready_file" 10)

  if ! _wait_for_file "$ready_file"; then
    kill "$child_pid" >/dev/null 2>&1
    wait "$child_pid" >/dev/null 2>&1
    assert_file_exists "$ready_file" "child process acquired lock"
    LOCKS_DIR="$previous_locks_dir"
    cleanup_test_dir "$tmp"
    return
  fi

  local lock_file="$LOCKS_DIR/owner.lock"
  release_lock "owner"

  assert_file_exists "$lock_file" "release_lock skips non-owner lock"

  kill "$child_pid" >/dev/null 2>&1
  wait "$child_pid" >/dev/null 2>&1

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

test_stale_lock_detected() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local ready_file="$tmp/ready"
  local child_pid
  child_pid=$(_spawn_lock_holder "$LOCKS_DIR" "stale" "$ready_file" 30)

  if ! _wait_for_file "$ready_file"; then
    kill "$child_pid" >/dev/null 2>&1
    wait "$child_pid" >/dev/null 2>&1
    assert_file_exists "$ready_file" "child process acquired lock"
    LOCKS_DIR="$previous_locks_dir"
    cleanup_test_dir "$tmp"
    return
  fi

  kill "$child_pid" >/dev/null 2>&1
  wait "$child_pid" >/dev/null 2>&1

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "stale" >/dev/null 2>&1
  local result=$?

  eval "$original_detect"

  assert_eq "0" "$result" "stale lock cleaned up"

  release_lock "stale"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# is_locked tests
#-------------------------------------------------------------------------------

test_is_locked_true() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  local original_detect
  original_detect=$(declare -f detect_flock)
  detect_flock() { echo "noclobber"; }

  acquire_lock "locked" >/dev/null 2>&1
  eval "$original_detect"

  is_locked "locked"
  local locked=$?
  assert_eq "0" "$locked" "is_locked returns true when locked"

  release_lock "locked"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

test_is_locked_false() {
  local tmp
  tmp=$(create_test_dir "lock-test")
  local previous_locks_dir=$LOCKS_DIR
  LOCKS_DIR="$tmp/.claude/locks"
  mkdir -p "$LOCKS_DIR"
  _reset_lock_state

  is_locked "missing"
  local locked=$?
  assert_eq "1" "$locked" "is_locked returns false without lock"

  LOCKS_DIR="$previous_locks_dir"
  cleanup_test_dir "$tmp"
}

#-------------------------------------------------------------------------------
# detect_flock tests
#-------------------------------------------------------------------------------

test_detect_flock_linux() {
  local os
  os=$(uname -s)
  if [ "$os" != "Linux" ]; then
    skip_test "not running on Linux"
    return
  fi

  if command -v flock >/dev/null 2>&1; then
    local result
    result=$(detect_flock)
    assert_eq "flock" "$result" "detect_flock returns flock on Linux"
  else
    skip_test "flock not installed"
  fi
}

test_detect_flock_fallback() {
  local tmp
  tmp=$(create_test_dir "lock-test")

  local result
  result=$(_with_path "$tmp" detect_flock)

  cleanup_test_dir "$tmp"

  assert_eq "noclobber" "$result" "detect_flock falls back to noclobber"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Lock Helpers"
echo "==============================================================="
echo ""

run_test "acquire_lock creates file" test_acquire_lock_creates_file
run_test "acquire_lock writes metadata" test_acquire_lock_writes_json
run_test "acquire_lock conflict detection" test_acquire_lock_conflict
run_test "release_lock removes file" test_release_lock_removes_file
run_test "release_lock only owner" test_release_lock_only_owner
run_test "stale lock detection" test_stale_lock_detected
run_test "is_locked true" test_is_locked_true
run_test "is_locked false" test_is_locked_false
run_test "detect_flock on Linux" test_detect_flock_linux
run_test "detect_flock fallback" test_detect_flock_fallback

test_summary
