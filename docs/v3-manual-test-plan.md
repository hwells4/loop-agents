# v3 Engine Manual Test Plan

Track manual validation of the v3 core engine before merge.

## Test Matrix

| # | Test | Command | Status | Notes |
|---|------|---------|--------|-------|
| 1 | Compile dry-run | `./scripts/run.sh dry-run pipeline refine.yaml test-dry` | ✅ | Validated 2 nodes |
| 2 | Basic fixed loop | `./scripts/run.sh ralph test-docs 2` | ✅ | Completed in 1 iter, agent stopped on empty queue |
| 3 | Judgment termination | `./scripts/run.sh loop improve-plan test-judge 5` | ⬜ | |
| 4 | Multi-stage pipeline | `./scripts/run.sh pipeline refine.yaml test-pipeline` | ⬜ | |
| 5 | Parallel block | `./scripts/run.sh pipeline dual-analyze.yaml test-parallel` | ⬜ | |
| 6 | Resume/crash recovery | Kill mid-run, then `--resume` | ⬜ | |

## Status Legend

- ⬜ Not started
- 🟡 In progress
- ✅ Passed
- ❌ Failed

## Test Details

### 1. Compile Dry-Run
Validates YAML parsing, stage resolution, and plan generation without execution.

**Expected:** Clean compilation, plan.json output shown

---

### 2. Basic Fixed Loop
Runs ralph stage for exactly 3 iterations.

**Validates:**
- Iteration counting
- State.json updates
- Progress file accumulation
- Fixed termination

**Expected:** Completes after iteration 3

---

### 3. Judgment Termination
Runs improve-plan with plateau detection.

**Validates:**
- Judge module invocation
- Consensus counting
- Early termination on plateau

**Expected:** Stops when 2 consecutive agents say "stop" (or hits max 5)

---

### 4. Multi-Stage Pipeline
Runs refine.yaml (plan refinement → task refinement).

**Validates:**
- Stage chaining
- Input passing between nodes
- Output collection

**Expected:** Both stages complete, outputs flow correctly

---

### 5. Parallel Block
Runs dual-analyze.yaml with multiple providers.

**Validates:**
- Concurrent provider execution
- Isolated contexts per provider
- Manifest aggregation

**Expected:** Both providers complete, outputs merged

**Prerequisites:** Codex CLI configured (or modify to use claude twice)

---

### 6. Resume/Crash Recovery
Manually kill a running session, then resume.

**Steps:**
1. Start: `./scripts/run.sh ralph test-resume 10`
2. After 2-3 iterations, kill: `tmux kill-session -t pipeline-test-resume`
3. Resume: `./scripts/run.sh ralph test-resume 10 --resume`

**Validates:**
- Event log integrity
- Iteration pickup from correct point
- State recovery

**Expected:** Resumes from last completed iteration

---

## Issues Found

| Test | Issue | Severity | Resolution |
|------|-------|----------|------------|
| | | | |

## Sign-off

- [ ] All tests passing
- [ ] Ready for merge
