# feat: Add Integration Tests for Pipeline Engine Code Path Parity

## Overview

Add integration tests that catch "function exists but isn't called" bugs by verifying that both `run_stage()` and `run_pipeline()` call the same required helper functions (like `mark_iteration_started`, `mark_iteration_completed`).

**Problem:** Unit tests pass because state tracking functions work correctly, but they don't catch when a code path forgets to call them. The bug where `run_pipeline()` never called iteration tracking was invisible to existing tests.

**Solution:** Add spy/call-tracking to the test framework and write contract tests that verify both code paths call required functions.

---

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Test Execution                           │
├─────────────────────────────────────────────────────────────┤
│  test_code_path_parity.sh                                   │
│    ├── test_run_stage_calls_iteration_tracking()            │
│    ├── test_run_pipeline_calls_iteration_tracking()         │
│    └── test_both_paths_have_same_call_pattern()             │
├─────────────────────────────────────────────────────────────┤
│  lib/spy.sh (NEW)                                           │
│    ├── spy_function "fn_name"     # Wrap function           │
│    ├── get_spy_calls "fn_name"    # Get call log            │
│    ├── assert_called "fn_name"    # Verify called           │
│    ├── assert_call_count "fn" N   # Verify call count       │
│    └── reset_spies                # Clear between tests     │
├─────────────────────────────────────────────────────────────┤
│  lib/mock.sh (existing)                                     │
│    └── Mock Claude execution to avoid API calls             │
├─────────────────────────────────────────────────────────────┤
│  lib/test.sh (existing)                                     │
│    └── Test framework, assertions, isolation                │
└─────────────────────────────────────────────────────────────┘
```

### Spy Mechanism

Use Bash function wrappers that record calls before invoking the real function:

```bash
# spy.sh pattern
spy_function() {
  local fn_name=$1

  # Save original
  eval "_original_${fn_name}=\$(declare -f $fn_name | tail -n +2)"

  # Replace with spy wrapper
  eval "
    ${fn_name}() {
      SPY_CALLS[\"\$fn_name\"]=\"\${SPY_CALLS[\$fn_name]:-}|\$*\"
      _original_${fn_name} \"\$@\"
    }
  "
}
```

---

## Acceptance Criteria

### Functional Requirements

- [ ] Spy framework can wrap any bash function and track calls
- [ ] Spy captures function name and arguments for each call
- [ ] Contract tests verify `run_stage()` calls iteration tracking functions
- [ ] Contract tests verify `run_pipeline()` calls iteration tracking functions
- [ ] Tests run in mock mode (no Claude API calls)
- [ ] Tests use isolated directories (no interference with real sessions)
- [ ] Tests clean up after themselves

### Quality Gates

- [ ] All existing tests still pass
- [ ] New tests catch the original bug (verify by temporarily removing the fix)
- [ ] Tests run in < 30 seconds total
- [ ] Tests work in CI environment (no interactive prompts)

---

## Implementation Phases

### Phase 1: Add Spy Framework

Create `scripts/lib/spy.sh` with call tracking capabilities.

**Files:**
- `scripts/lib/spy.sh` (new)

```bash
#!/bin/bash
# Spy framework for tracking function calls in tests

declare -A SPY_CALLS
declare -A SPY_ORIGINALS

# Wrap a function to track calls
# Usage: spy_function "mark_iteration_started"
spy_function() {
  local fn_name=$1

  # Check function exists
  if ! declare -f "$fn_name" > /dev/null 2>&1; then
    echo "Warning: Cannot spy on undefined function: $fn_name" >&2
    return 1
  fi

  # Save original implementation
  SPY_ORIGINALS[$fn_name]=$(declare -f "$fn_name")

  # Initialize call log
  SPY_CALLS[$fn_name]=""

  # Create wrapper
  eval "
    ${fn_name}() {
      # Log the call with arguments
      if [ -z \"\${SPY_CALLS[$fn_name]}\" ]; then
        SPY_CALLS[$fn_name]=\"\$*\"
      else
        SPY_CALLS[$fn_name]=\"\${SPY_CALLS[$fn_name]}||\$*\"
      fi
      # Call original
      ${SPY_ORIGINALS[$fn_name]}
    }
  "
}

# Get all calls to a spied function
# Usage: calls=$(get_spy_calls "mark_iteration_started")
get_spy_calls() {
  local fn_name=$1
  echo "${SPY_CALLS[$fn_name]:-}"
}

# Get call count for a spied function
# Usage: count=$(get_spy_call_count "mark_iteration_started")
get_spy_call_count() {
  local fn_name=$1
  local calls="${SPY_CALLS[$fn_name]:-}"

  if [ -z "$calls" ]; then
    echo "0"
  else
    echo "$calls" | tr '|' '\n' | grep -c . || echo "0"
  fi
}

# Assert a function was called at least once
# Usage: assert_spy_called "mark_iteration_started" "Should track iteration start"
assert_spy_called() {
  local fn_name=$1
  local message=${2:-"$fn_name should have been called"}
  local count=$(get_spy_call_count "$fn_name")

  if [ "$count" -gt 0 ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message (called $count times)"
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected: $fn_name to be called"
    echo "    Actual: never called"
  fi
}

# Assert a function was called exactly N times
# Usage: assert_spy_call_count "mark_iteration_started" 3 "Should track 3 iterations"
assert_spy_call_count() {
  local fn_name=$1
  local expected=$2
  local message=${3:-"$fn_name should be called $expected times"}
  local actual=$(get_spy_call_count "$fn_name")

  if [ "$actual" -eq "$expected" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message"
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected: $expected calls"
    echo "    Actual: $actual calls"
    echo "    Call log: ${SPY_CALLS[$fn_name]:-<empty>}"
  fi
}

# Reset all spies between tests
reset_spies() {
  # Restore original functions
  for fn_name in "${!SPY_ORIGINALS[@]}"; do
    eval "${SPY_ORIGINALS[$fn_name]}"
  done

  SPY_CALLS=()
  SPY_ORIGINALS=()
}
```

**Effort:** ~1 hour

---

### Phase 2: Add Contract Tests for run_stage()

Create test that verifies `run_stage()` calls required state tracking functions.

**Files:**
- `scripts/tests/test_code_path_parity.sh` (new)

```bash
#!/bin/bash
# Contract tests verifying code path parity between run_stage and run_pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/spy.sh"
source "$SCRIPT_DIR/lib/mock.sh"
source "$SCRIPT_DIR/lib/state.sh"

#-------------------------------------------------------------------------------
# Test Helpers
#-------------------------------------------------------------------------------

_setup_test_environment() {
  local test_dir=$1
  local session=$2

  # Create minimal stage config
  mkdir -p "$test_dir/stages/test-stage"
  cat > "$test_dir/stages/test-stage/stage.yaml" << 'EOF'
name: test-stage
description: Minimal stage for testing
termination:
  type: fixed
delay: 0
EOF

  cat > "$test_dir/stages/test-stage/prompt.md" << 'EOF'
Test prompt. Write status to ${STATUS}.
EOF

  # Create fixtures
  mkdir -p "$test_dir/stages/test-stage/fixtures"
  echo "Mock response" > "$test_dir/stages/test-stage/fixtures/default.txt"
  cat > "$test_dir/stages/test-stage/fixtures/status.json" << 'EOF'
{"decision": "continue", "reason": "test", "summary": "test", "work": {}, "errors": []}
EOF

  # Enable mock mode
  enable_mock_mode "$test_dir/stages/test-stage/fixtures"
}

#-------------------------------------------------------------------------------
# Contract Tests: run_stage
#-------------------------------------------------------------------------------

test_run_stage_calls_mark_iteration_started() {
  local test_dir=$(create_test_dir "stage-started")
  _setup_test_environment "$test_dir" "test-session"

  # Spy on state tracking functions
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  # Run single iteration via run_stage
  local run_dir="$test_dir/.claude/pipeline-runs/test-session"
  mkdir -p "$run_dir"

  # Source engine and run (in subshell to isolate)
  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_stage "test-stage" "test-session" 1 "$run_dir" 0 1 2>/dev/null
  )

  # Verify
  assert_spy_called "mark_iteration_started" "run_stage should call mark_iteration_started"

  # Cleanup
  reset_spies
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

test_run_stage_calls_mark_iteration_completed() {
  local test_dir=$(create_test_dir "stage-completed")
  _setup_test_environment "$test_dir" "test-session"

  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  local run_dir="$test_dir/.claude/pipeline-runs/test-session"
  mkdir -p "$run_dir"

  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_stage "test-stage" "test-session" 1 "$run_dir" 0 1 2>/dev/null
  )

  assert_spy_called "mark_iteration_completed" "run_stage should call mark_iteration_completed"

  reset_spies
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Contract Tests: run_pipeline
#-------------------------------------------------------------------------------

test_run_pipeline_calls_mark_iteration_started() {
  local test_dir=$(create_test_dir "pipeline-started")
  _setup_test_environment "$test_dir" "test-session"

  # Create minimal pipeline config
  cat > "$test_dir/test-pipeline.yaml" << 'EOF'
name: test-pipeline
stages:
  - name: stage1
    loop: test-stage
    runs: 1
EOF

  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_pipeline "$test_dir/test-pipeline.yaml" "test-session" 2>/dev/null
  )

  assert_spy_called "mark_iteration_started" "run_pipeline should call mark_iteration_started"

  reset_spies
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

test_run_pipeline_calls_mark_iteration_completed() {
  local test_dir=$(create_test_dir "pipeline-completed")
  _setup_test_environment "$test_dir" "test-session"

  cat > "$test_dir/test-pipeline.yaml" << 'EOF'
name: test-pipeline
stages:
  - name: stage1
    loop: test-stage
    runs: 1
EOF

  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_pipeline "$test_dir/test-pipeline.yaml" "test-session" 2>/dev/null
  )

  assert_spy_called "mark_iteration_completed" "run_pipeline should call mark_iteration_completed"

  reset_spies
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Parity Tests: Both paths should behave the same
#-------------------------------------------------------------------------------

test_both_paths_call_same_state_functions() {
  local test_dir=$(create_test_dir "parity")
  _setup_test_environment "$test_dir" "test-session"

  cat > "$test_dir/test-pipeline.yaml" << 'EOF'
name: test-pipeline
stages:
  - name: stage1
    loop: test-stage
    runs: 2
EOF

  # Run via run_stage (2 iterations)
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  local run_dir="$test_dir/.claude/pipeline-runs/stage-session"
  mkdir -p "$run_dir"

  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_stage "test-stage" "stage-session" 2 "$run_dir" 0 1 2>/dev/null
  )

  local stage_started_count=$(get_spy_call_count "mark_iteration_started")
  local stage_completed_count=$(get_spy_call_count "mark_iteration_completed")

  reset_spies

  # Run via run_pipeline (2 iterations)
  spy_function "mark_iteration_started"
  spy_function "mark_iteration_completed"

  (
    source "$SCRIPT_DIR/engine.sh"
    MOCK_MODE=true
    run_pipeline "$test_dir/test-pipeline.yaml" "pipeline-session" 2>/dev/null
  )

  local pipeline_started_count=$(get_spy_call_count "mark_iteration_started")
  local pipeline_completed_count=$(get_spy_call_count "mark_iteration_completed")

  # Both paths should have same call counts
  assert_eq "$stage_started_count" "$pipeline_started_count" \
    "Both paths should call mark_iteration_started same number of times"
  assert_eq "$stage_completed_count" "$pipeline_completed_count" \
    "Both paths should call mark_iteration_completed same number of times"

  reset_spies
  disable_mock_mode
  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Code Path Parity Tests"
echo "==============================================================="
echo ""

run_test "run_stage calls mark_iteration_started" test_run_stage_calls_mark_iteration_started
run_test "run_stage calls mark_iteration_completed" test_run_stage_calls_mark_iteration_completed
run_test "run_pipeline calls mark_iteration_started" test_run_pipeline_calls_mark_iteration_started
run_test "run_pipeline calls mark_iteration_completed" test_run_pipeline_calls_mark_iteration_completed
run_test "both paths call same state functions" test_both_paths_call_same_state_functions

test_summary
```

**Effort:** ~2 hours

---

### Phase 3: Verify Tests Catch the Bug

Temporarily revert the fix to confirm tests fail, then restore.

**Steps:**
1. Remove `mark_iteration_started/completed` calls from `run_pipeline()`
2. Run tests - should FAIL
3. Restore the calls
4. Run tests - should PASS

```bash
# Test that tests catch the bug
./scripts/run.sh test code_path_parity  # Should pass (fix is in place)

# Temporarily break it
sed -i '' '/mark_iteration_started.*state_file.*iteration/d' scripts/engine.sh
./scripts/run.sh test code_path_parity  # Should FAIL

# Restore
git checkout scripts/engine.sh
./scripts/run.sh test code_path_parity  # Should pass again
```

**Effort:** ~30 minutes

---

### Phase 4: Add to Test Runner

Ensure new tests run as part of `./scripts/run.sh test`.

**Files:**
- `scripts/run.sh` (modify test discovery if needed)

The test runner already auto-discovers `test_*.sh` files, so this should work automatically.

**Effort:** ~15 minutes

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Tests catch missing calls bug | Yes (verified by Phase 3) |
| Test runtime | < 30 seconds |
| False positive rate | 0 (tests pass on correct code) |
| Code coverage of state tracking calls | 100% of entry points |

---

## Dependencies & Risks

### Dependencies
- Existing test framework (`lib/test.sh`)
- Existing mock system (`lib/mock.sh`)
- Bash 4.0+ for associative arrays

### Risks

| Risk | Mitigation |
|------|------------|
| Spy wrapper changes function behavior | Test spy framework independently first |
| Mock mode doesn't simulate real execution accurately | Run integration tests in both mock and real modes periodically |
| Tests become brittle on refactors | Keep contract tests at call-level, not argument-level |

---

## Future Considerations

1. **Expand to other code paths:** Resume mode, force mode, multi-provider execution
2. **Add call sequence verification:** Not just "was called" but "called in correct order"
3. **Add coverage reporting:** Track which functions are tested
4. **CI integration:** Run tests on every PR

---

## References

### Internal
- `scripts/lib/test.sh` - Test framework
- `scripts/lib/mock.sh` - Mock execution system
- `scripts/lib/state.sh` - State tracking functions
- `scripts/engine.sh:187,292` - run_stage iteration tracking
- `scripts/engine.sh:500,549` - run_pipeline iteration tracking
- `docs/bug-report-pipeline-execution-2026-01-12.md` - Original bug report

### External
- [BATS Testing Framework](https://bats-core.readthedocs.io/en/stable/)
- [Bash Function Mocking Patterns](https://advancedweb.hu/how-to-mock-in-bash-tests/)
