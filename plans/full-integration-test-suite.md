# Plan: Full Integration Test Suite for Pipeline Engine

## Overview

Create an integration test suite that exercises the pipeline engine end-to-end with mocked Claude execution. This test suite would have caught all 5 bugs discovered during `design-refine.yaml` execution.

**Problem Statement:** The existing test suite has ~230 passing unit tests but zero integration tests. Individual functions work correctly in isolation, but the orchestration layer (`engine.sh` lines 376-538) is never tested as an integrated system.

## Proposed Solution

Create a mocked integration test harness that:
1. Overrides `execute_agent` to return fixture-based responses
2. Runs the actual engine loop end-to-end
3. Verifies state transitions, output artifacts, and completion behavior

### Architecture

```
scripts/tests/
├── test_integration_harness.sh    # Shared harness for mocking execute_agent
├── test_integration_single.sh     # Single-stage pipeline e2e tests
├── test_integration_multi.sh      # Multi-stage pipeline e2e tests
├── test_integration_resume.sh     # Resume/crash recovery tests
├── test_bug_regression.sh         # Specific regression tests for 5 bugs
└── fixtures/
    └── integration/
        ├── continue-3.json        # 3 iterations, all continue
        ├── stop-at-2.json         # Stop decision at iteration 2
        ├── crash-at-2.json        # Simulated crash at iteration 2
        └── multi-stage-3.json     # 3-stage pipeline fixture set
```

## Technical Approach

### Phase 1: Integration Test Harness

Create `test_integration_harness.sh` that provides:

```bash
# Override execute_agent after sourcing provider.sh
# This is the key mock point that enables testing without calling Claude

_mock_execute_agent() {
  local provider=$1
  local prompt=$2
  local model=$3
  local output_file=$4

  # Get iteration from global tracker
  local iteration=${MOCK_CURRENT_ITERATION:-1}

  # Return fixture-based response
  local response=$(get_mock_response "$iteration")
  echo "$response"
  [ -n "$output_file" ] && echo "$response" > "$output_file"

  # Write mock status.json if STATUS_FILE is set
  if [ -n "${MOCK_STATUS_FILE:-}" ]; then
    write_mock_status "$MOCK_STATUS_FILE" "$iteration"
  fi

  # Simulate failure if configured
  if [ "${MOCK_FAIL_AT:-0}" -eq "$iteration" ]; then
    return 1
  fi

  return 0
}

setup_integration_test() {
  local test_dir=$1
  local fixture_set=$2

  # Create temp directory structure
  export PROJECT_ROOT="$test_dir"
  export STAGES_DIR="$test_dir/stages"

  # Enable mock mode with fixtures
  enable_mock_mode "$SCRIPT_DIR/fixtures/integration/$fixture_set"

  # Override execute_agent
  execute_agent() { _mock_execute_agent "$@"; }
  export -f execute_agent
}
```

**Key insight:** Functions override PATH commands in bash, so defining `execute_agent` after sourcing `provider.sh` intercepts all calls.

### Phase 2: Single-Stage Integration Tests

`test_integration_single.sh` verifies:

| Test | What It Verifies | Bug Prevented |
|------|------------------|---------------|
| `test_single_stage_completes_3_iterations` | Engine runs to max iterations | - |
| `test_single_stage_stops_on_agent_decision` | Agent "stop" triggers completion | - |
| `test_single_stage_state_updates_each_iteration` | iteration/iteration_completed increment | Bug 4 |
| `test_single_stage_creates_iteration_dirs` | iterations/001, 002, 003 created | - |
| `test_single_stage_writes_output_snapshots` | output.md saved per iteration | - |
| `test_single_stage_handles_agent_crash` | Exit code != 0 marks failed | - |
| `test_single_stage_default_model_is_opus` | load_stage defaults to opus | Bug 1 |

### Phase 3: Multi-Stage Integration Tests

`test_integration_multi.sh` verifies:

| Test | What It Verifies | Bug Prevented |
|------|------------------|---------------|
| `test_multi_stage_executes_all_stages` | Stages run in sequence | Bug 3 |
| `test_multi_stage_current_stage_updates` | current_stage increments | Bug 5 |
| `test_multi_stage_stage_dirs_created` | stage-00-name directories | - |
| `test_multi_stage_default_model_is_opus` | Pipeline defaults to opus | Bug 1 |
| `test_multi_stage_zero_iterations_fails` | Zero runs = explicit failure | Bug 3 |
| `test_multi_stage_state_tracks_stages_array` | stages[] status updates | - |

### Phase 4: Resume Integration Tests

`test_integration_resume.sh` verifies:

| Test | What It Verifies | Bug Prevented |
|------|------------------|---------------|
| `test_resume_single_stage_continues_from_iteration` | Resumes at iteration_completed + 1 | - |
| `test_resume_multi_stage_skips_completed_stages` | Stages 0,1 skipped if complete | Bug 5 |
| `test_resume_multi_stage_starts_at_current_stage` | Uses current_stage from state | Bug 5 |
| `test_resume_multi_stage_correct_iteration` | Within-stage iteration correct | Bug 5 |
| `test_resume_clears_error_status` | reset_for_resume works | - |

### Phase 5: Bug Regression Tests

`test_bug_regression.sh` - Specific tests that would have failed before fixes:

```bash
# Bug 1: Default model consistency
test_bug1_regression() {
  # Verify both load_stage and run_pipeline use "opus" as default
}

# Bug 2: Empty variable handling
test_bug2_regression() {
  # Call check_completion with unset MAX_ITERATIONS
  # Should not throw "integer expression expected"
}

# Bug 3: Zero iterations detection
test_bug3_regression() {
  # Run pipeline where stage_runs evaluates to 0
  # Should fail explicitly, not silently complete
}

# Bug 4: State update error handling
test_bug4_regression() {
  # Corrupt state.json, call mark_iteration_started
  # Should return error, not silently fail
}

# Bug 5: Multi-stage resume
test_bug5_regression() {
  # Create state with current_stage: 2, stages[0,1] complete
  # Resume and verify it skips to stage 2
}
```

## Acceptance Criteria

### Functional Requirements

- [ ] All tests pass with current (fixed) code
- [ ] Tests use mock execution (no actual Claude calls)
- [ ] Tests verify state.json updates during execution
- [ ] Tests verify multi-stage resume behavior
- [ ] Each of 5 bugs has a specific regression test

### Non-Functional Requirements

- [ ] Tests complete in < 30 seconds total
- [ ] Tests are isolated (no shared state between tests)
- [ ] Tests clean up temp directories on completion
- [ ] Tests can run in CI without special setup

### Quality Gates

- [ ] Running tests against pre-fix code would fail
- [ ] All existing unit tests still pass
- [ ] Test coverage includes all 12 identified user flows

## Success Metrics

1. **Bug detection:** 5/5 bugs would be caught by regression tests
2. **Flow coverage:** 10+ of 12 critical user flows tested
3. **State verification:** Tests check state.json after each iteration
4. **Execution time:** Full suite runs in < 30 seconds

## Dependencies & Prerequisites

1. **Mock harness design decision:** Override `execute_agent` at function level (not PATH manipulation)
2. **Fixture format:** Use existing `scripts/lib/mock.sh` patterns
3. **Test isolation:** Each test creates fresh temp directory

## File Structure

```
scripts/tests/test_integration_harness.sh
├── Sources: lib/test.sh, lib/mock.sh, lib/provider.sh
├── Exports: setup_integration_test(), teardown_integration_test()
├── Overrides: execute_agent() with fixture-based mock
└── Tracks: MOCK_CURRENT_ITERATION, MOCK_STATUS_FILE

scripts/tests/test_integration_single.sh
├── Sources: test_integration_harness.sh, engine.sh functions
├── Tests: 7 single-stage e2e scenarios
└── Verifies: State updates, output creation, completion

scripts/tests/test_integration_multi.sh
├── Sources: test_integration_harness.sh, engine.sh functions
├── Tests: 6 multi-stage e2e scenarios
└── Verifies: Stage transitions, current_stage, zero-iteration detection

scripts/tests/test_integration_resume.sh
├── Sources: test_integration_harness.sh, engine.sh functions
├── Tests: 5 resume scenarios
└── Verifies: Stage skipping, iteration continuation

scripts/tests/test_bug_regression.sh
├── Sources: test_integration_harness.sh
├── Tests: 5 specific bug regression tests
└── Verifies: Each bug fix works correctly

scripts/tests/fixtures/integration/
├── continue-3/ (3 iterations, all continue)
│   ├── iteration-1.txt, status-1.json
│   ├── iteration-2.txt, status-2.json
│   └── iteration-3.txt, status-3.json
├── stop-at-2/ (stop at iteration 2)
│   ├── iteration-1.txt, status-1.json (continue)
│   └── iteration-2.txt, status-2.json (stop)
└── multi-stage-3/ (3-stage pipeline)
    ├── stage-0/ (complete after 2 iterations)
    ├── stage-1/ (complete after 1 iteration)
    └── stage-2/ (complete after 2 iterations)
```

## Implementation Notes

### How Mock Execution Works

```
Normal flow:
  engine.sh → run_stage() → execute_agent() → claude CLI → real output

Test flow:
  engine.sh → run_stage() → execute_agent() → _mock_execute_agent() → fixture output
```

The override happens because bash function lookup has priority over PATH commands. After sourcing `provider.sh`, we redefine `execute_agent` to call our mock instead.

### State Verification Pattern

```bash
test_state_updates_during_execution() {
  local test_dir=$(create_test_dir)
  setup_integration_test "$test_dir" "continue-3"

  # Run 3 iterations
  run_stage "test-stage" "test-session" 3 "$test_dir/.claude/pipeline-runs/test-session" 0 1

  # Verify state after completion
  local state_file="$test_dir/.claude/pipeline-runs/test-session/state.json"
  assert_json_field "$state_file" ".iteration" "3"
  assert_json_field "$state_file" ".iteration_completed" "3"
  assert_json_field "$state_file" ".status" "complete"

  teardown_integration_test "$test_dir"
}
```

### TDD Verification (Retroactive)

To prove tests would have caught the bugs:

```bash
# 1. Run tests with current (fixed) code - should PASS
./scripts/tests/test_bug_regression.sh
# Expected: 5 passed, 0 failed

# 2. Stash fixes
git stash

# 3. Run tests with original (buggy) code - should FAIL
./scripts/tests/test_bug_regression.sh
# Expected: 0 passed, 5 failed

# 4. Restore fixes
git stash pop
```

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Mock doesn't accurately simulate Claude | Medium | High | Validate mock behavior matches real CLI |
| Tests take too long | Low | Medium | Use minimal iterations, parallel where possible |
| Tests flaky due to timing | Low | High | No sleeps in tests, mock delays |
| State file race conditions | Low | Medium | Single-threaded test execution |

## References

### Internal References
- Test framework: `scripts/lib/test.sh`
- Mock infrastructure: `scripts/lib/mock.sh`
- Provider abstraction: `scripts/lib/provider.sh:execute_agent`
- Engine loop: `scripts/engine.sh:run_stage`, `scripts/engine.sh:run_pipeline`
- Existing fixtures: `scripts/stages/improve-plan/fixtures/`

### External References
- [Advanced Web Machinery - How to mock in Bash tests](https://advancedweb.hu/how-to-mock-in-bash-tests/)
- [Unwiredcouch - Bash Unit Testing](https://unwiredcouch.com/2016/04/13/bash-unit-testing-101.html)

### Related Work
- Bug report: `docs/bug-report-pipeline-execution-2026-01-12.md`
- Bug fixes: Current uncommitted changes to `engine.sh`, `state.sh`, `fixed-n.sh`
