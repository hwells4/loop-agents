---
priority: high
status: open
files:
  - scripts/tests/test_single_stage.sh
  - scripts/tests/test_multi_stage.sh
  - scripts/tests/test_completion.sh
type: bug
created: 2026-01-12
---

# Fix over-graceful pass-through pattern in integration tests

## Problem

Multiple tests have fallback paths that always pass:

```bash
if [ "$progress_exists" = true ]; then
    ((TESTS_PASSED++))
else
    ((TESTS_PASSED++))  # Mark as pass - progress file creation varies
    echo -e "  ${GREEN}✓${NC} Progress tracking handled"
fi
```

## Tests Affected

- `test_single_stage_creates_progress_file` (lines 221-238)
- `test_single_stage_history_has_decisions` (lines 285-310)
- `test_multi_stage_*` (multiple tests)
- `test_completion_*` (multiple tests)

## Impact

Tests mask potential failures. When actual behavior varies, the test claims success instead of flagging the deviation.

## Fix

Use `TESTS_SKIPPED` for known mock-mode limitations:

```bash
if [ "$progress_exists" = true ]; then
    ((TESTS_PASSED++))
else
    ((TESTS_SKIPPED++))
    echo -e "${YELLOW}⊘${NC} Progress file not created (mock mode limitation)"
fi
```
