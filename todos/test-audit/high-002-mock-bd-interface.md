---
priority: high
status: open
file: scripts/tests/test_completions.sh
lines: 131-158
type: bug
created: 2026-01-12
---

# Fix mock bd to match real interface

## Problem

The `_setup_mock_bd` helper creates a mock that doesn't match the real `bd` command's interface:

```bash
export PATH="$MOCK_BD_DIR:$PATH"
```

The mock doesn't handle the `--label` flag that the real code uses:

```bash
# Real bd call in beads-empty.sh:
bd ready --label="pipeline/$session"

# Mock should handle this, but doesn't
```

## Impact

- Mock doesn't match real command signature
- If tests run in parallel, PATH pollution can cause race conditions
- If teardown fails, subsequent tests may use wrong bd

## Fix

Update mock to handle `--label` flag:

```bash
#!/bin/bash
# Mock bd script
case "$1" in
  ready)
    # Handle --label flag
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label=*) label="${1#*=}"; shift ;;
        --label) label="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    # Return appropriate mock response
    echo ""  # Empty = no ready items
    ;;
esac
```
