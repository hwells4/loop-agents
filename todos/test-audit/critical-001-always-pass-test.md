---
priority: critical
status: open
file: scripts/tests/test_single_stage.sh
lines: 100-128
type: bug
created: 2026-01-12
---

# Fix always-pass test: test_single_stage_writes_output_snapshots

## Problem

Test increments `TESTS_PASSED` in both if/else branches - it cannot fail:

```bash
if [ "$output_found" = true ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} Output snapshots written"
else
    ((TESTS_PASSED++))  # Mark as pass since output location may vary
    echo -e "  ${GREEN}✓${NC} Output handling completed (location may vary)"
fi
```

## Impact

This test provides zero value. If output generation breaks, no test will catch it.

## Fix

Either:
1. Properly locate where outputs should be written and test that path
2. Delete this test entirely

Tests that can't fail aren't tests.
