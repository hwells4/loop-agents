---
priority: medium
status: open
files:
  - scripts/tests/*.sh
type: improvement
created: 2026-01-12
---

# Standardize assertion style across tests

## Problem

Some tests use the `assert_*` functions from test.sh, others do inline checks:

```bash
# Using framework (good)
assert_json_field "$state_file" ".iteration_completed" "3"

# Inline check (inconsistent)
if [ "$completed" -gt 0 ]; then
    ((TESTS_PASSED++))
fi
```

## Impact

- Inconsistent error messages
- Harder to maintain
- Duplicated pass/fail logic

## Fix

Standardize on using `assert_*` functions for all checks. Add new assert functions if needed:

```bash
# In test.sh
assert_gt() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Expected $actual > $expected}"
    if [ "$actual" -gt "$expected" ]; then
        return 0
    else
        echo "FAIL: $msg"
        return 1
    fi
}
```
