# Test Refactor Plan: Integration Suite Speedup

## Goals
- Cut integration test wall time by reusing single engine runs for multiple assertions.
- Keep coverage equivalent (no loss of bug regressions or feature checks).
- Preserve deterministic behavior in mock mode.

## Current Hotspots (Measured)
- `scripts/tests/integration/test_multi_stage.sh`: ~458s (runs multi-stage pipeline 10x)
- `scripts/tests/integration/test_single_stage.sh`: ~174s (runs single-stage loop 12x)
- `scripts/tests/integration/test_bug_regression.sh`: ~391s (7+ engine runs)
- `scripts/tests/integration/test_completion_strategies.sh`: ~257s (multiple runs)

## High-Impact Refactor Strategy
1. **Collapse repeated runs into shared fixtures within a file.**
   - Run a pipeline once, capture `run_dir` + `state.json`, and reuse for multiple assertions.
   - Keep separate runs only when inputs differ (e.g., `stop-at-2`, missing-stage, resume cases).

2. **Add small helper(s) in `scripts/tests/integration/harness.sh`.**
   - `run_mock_pipeline_with_output` to return both log + run dir.
   - `run_mock_engine_with_output` to return log + run dir.
   - These helpers should accept `test_dir`, `session`, and stage/pipeline path so tests can reuse the same run.

3. **Refactor the top offenders first.**
   - `test_multi_stage.sh`: reduce to 2 runs total:
     - 1 normal multi-stage run for all positive assertions.
     - 1 broken pipeline run for missing-stage error check.
   - `test_single_stage.sh`: reduce to 2 runs total:
     - 1 run for `test-continue-3` assertions.
     - 1 run for `test-stop-at-2` (stop behavior).
   - `test_bug_regression.sh`: merge checks where a single multi-stage run can validate multiple bugs.

## Detailed File-Level Plan

### `scripts/tests/integration/harness.sh`
- Add helper(s):
  - `run_mock_engine_once`: run engine, return `run_dir` + `log` (store in temp vars or write to file).
  - `run_mock_pipeline_once`: same for pipeline.
- Ensure helpers do not change semantics of existing functions.

### `scripts/tests/integration/test_multi_stage.sh`
- Current: 10 runs of the same multi-stage pipeline.
- Change: one run for all assertions that read state/dirs/history.
- Keep separate run for missing-stage error (`broken.yaml`).

### `scripts/tests/integration/test_single_stage.sh`
- Current: 12 runs of the same single-stage loop (`test-continue-3`).
- Change: one run for all assertions requiring `test-continue-3`.
- Keep a second run for `test-stop-at-2`.

### `scripts/tests/integration/test_bug_regression.sh`
- Identify overlaps:
  - Bug 6 + Bug 7 can share a single multi-stage pipeline run.
  - Bug 1 (model consistency) might reuse the same multi-stage run if output checks are compatible.
- Reduce redundant setup/teardown calls.

### `scripts/tests/integration/test_completion_strategies.sh`
- Audit for repeated runs with the same fixture and merge checks.

## Acceptance Criteria
- Integration test suite runtime reduced by at least 50% locally.
- No test coverage loss (all existing assertions still performed).
- No changes to production code paths.

## Verification
- `./scripts/tests/run_tests.sh integration`
- (Optional) Compare per-file timings before/after.

## Risks
- Over-coupling tests to a single run could hide setup bugs.
- Mitigate by keeping separate runs for distinct fixtures and for error-path tests.
