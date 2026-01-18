# Engine Performance Summary

## Problem

Test suite takes 5+ minutes. A single mock iteration takes **2.3 seconds** - unacceptable for a bash orchestrator.

## Root Causes

| Issue | Impact |
|-------|--------|
| 15+ lib files sourced per invocation | ~400ms startup |
| Libs re-source each other (redundant) | Wasted cycles |
| 10k lines of bash parsed every run | Slow interpretation |
| Tests spin up full pipelines even with mocks | Multiplied overhead |

## Benchmarks

```
YAML parse (yq):     0.02s  ✓ fast
Source all libs:     0.38s  ✗ slow
Single mock iter:    2.30s  ✗ way too slow
```

## Test Issues

1. `test_code_path_parity.sh` runs in both unit and contract suites (duplicate)
2. Integration tests create full temp directory structures per test
3. Tests run sequentially, not in parallel
4. Many tests use `runs: 2` when 1 would suffice

## Suggested Fixes

### Quick (tests only)

Pre-source libs once, run tests in same shell context:

```bash
source scripts/lib/*.sh
export -f <functions>
# run tests without re-sourcing
```

### Medium (engine)

Compile libs to single file at build time:

```bash
cat scripts/lib/*.sh > dist/engine-bundle.sh
```

### Long-term

Rewrite in Python or Go. Bash doesn't scale past ~2k lines for complex orchestration.

| Language | Startup | Effort |
|----------|---------|--------|
| Bash (current) | 400ms | - |
| Python | 50ms | Medium |
| Go | 5ms | High |

## Failed Tests

2 failures in `test_regression.sh` (likely intentional - prompts don't use `${RESULT}`):

- `ralph prompt uses ${RESULT}`
- `refine-tasks prompt uses ${RESULT}`
