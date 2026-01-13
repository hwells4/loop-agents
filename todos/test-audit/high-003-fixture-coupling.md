---
priority: high
status: open
file: scripts/tests/test_mock.sh
lines: 62-80
type: bug
created: 2026-01-12
---

# Fix fixture coupling in test_get_mock_response_iteration_specific

## Problem

Test assumes `$SCRIPT_DIR/stages/improve-plan/fixtures` contains files with specific content like "Initial Review", "Refinement", "Confirmation".

If these fixtures change, the test silently breaks.

## Impact

Tightly coupled to fixture contents. Fixture changes will break tests but won't be obvious.

## Fix

Either:

1. **Document the fixture contract** - Add comments specifying required content
2. **Create dedicated test fixtures** - Separate from stage fixtures that may be modified

```bash
# Option 2: Dedicated test fixtures
TEST_FIXTURES_DIR="$SCRIPT_DIR/fixtures/test-only"
mkdir -p "$TEST_FIXTURES_DIR"
echo "Initial Review" > "$TEST_FIXTURES_DIR/response-1.md"
echo "Refinement" > "$TEST_FIXTURES_DIR/response-2.md"
```
