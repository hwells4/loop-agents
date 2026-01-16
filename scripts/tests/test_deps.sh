#!/bin/bash
# Tests for dependency checks (scripts/lib/deps.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/deps.sh"

_write_stub() {
  local dir=$1
  local name=$2
  local body=$3

  printf '%s\n' "#!/bin/bash" "$body" > "$dir/$name"
  chmod +x "$dir/$name"
}

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

#-------------------------------------------------------------------------------
# jq version tests
#-------------------------------------------------------------------------------

test_check_jq_version_accepts_1_6() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "jq" 'echo "jq-1.6"'

  _with_path "$mock_dir" check_jq_version >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "0" "$result" "jq 1.6+ passes"
}

test_check_jq_version_rejects_old() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "jq" 'echo "jq-1.5"'

  _with_path "$mock_dir" check_jq_version >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "1" "$result" "jq 1.5 fails"
}

test_check_jq_version_missing() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _with_path "$mock_dir" check_jq_version >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "1" "$result" "missing jq fails"
}

#-------------------------------------------------------------------------------
# yq version tests
#-------------------------------------------------------------------------------

test_check_yq_version_accepts_v4() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "yq" 'echo "yq (https://github.com/mikefarah/yq/) version 4.30.8"'

  _with_path "$mock_dir" check_yq_version >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "0" "$result" "yq v4 passes"
}

test_check_yq_version_rejects_python() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "yq" 'echo "yq 3.2.1"'

  _with_path "$mock_dir" check_yq_version >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "1" "$result" "yq v3 fails"
}

#-------------------------------------------------------------------------------
# check_deps tests
#-------------------------------------------------------------------------------

test_check_deps_requires_tmux() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "jq" 'echo "jq-1.6"'
  _write_stub "$mock_dir" "yq" 'echo "yq (https://github.com/mikefarah/yq/) version 4.30.8"'

  DEPS_CHECKED_BASE=""
  _with_path "$mock_dir" check_deps --require-tmux >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "1" "$result" "require tmux fails when missing"
}

test_check_deps_requires_bd() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "jq" 'echo "jq-1.6"'
  _write_stub "$mock_dir" "yq" 'echo "yq (https://github.com/mikefarah/yq/) version 4.30.8"'

  DEPS_CHECKED_BASE=""
  _with_path "$mock_dir" check_deps --require-bd >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "1" "$result" "require bd fails when missing"
}

test_check_deps_all_required() {
  local mock_dir
  mock_dir=$(mktemp -d)

  _write_stub "$mock_dir" "jq" 'echo "jq-1.6"'
  _write_stub "$mock_dir" "yq" 'echo "yq (https://github.com/mikefarah/yq/) version 4.30.8"'
  _write_stub "$mock_dir" "tmux" 'exit 0'
  _write_stub "$mock_dir" "bd" 'exit 0'

  DEPS_CHECKED_BASE=""
  _with_path "$mock_dir" check_deps --require-tmux --require-bd >/dev/null 2>&1
  local result=$?

  rm -rf "$mock_dir"

  assert_eq "0" "$result" "all required deps pass"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Dependency Checks"
echo "==============================================================="
echo ""

run_test "jq 1.6 passes" test_check_jq_version_accepts_1_6
run_test "jq 1.5 fails" test_check_jq_version_rejects_old
run_test "jq missing fails" test_check_jq_version_missing
run_test "yq v4 passes" test_check_yq_version_accepts_v4
run_test "yq v3 fails" test_check_yq_version_rejects_python
run_test "require tmux fails without tmux" test_check_deps_requires_tmux
run_test "require bd fails without bd" test_check_deps_requires_bd
run_test "all required deps pass" test_check_deps_all_required

test_summary
