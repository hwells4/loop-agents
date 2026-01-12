---
description: Sync README with current codebase functionality
---

# /readme-sync

Analyzes the codebase and updates README.md to reflect current functionality. Finds missing features, outdated info, and under-documented areas.

**Runtime:** ~2 min per iteration

## Usage

```
/readme-sync         # 1 iteration (default)
/readme-sync 2       # 2 iterations (deeper pass)
```

## What It Does

Each iteration:
1. Compares README against actual code
2. Identifies gaps (missing, outdated, under-explained)
3. Makes direct edits to README.md
4. Logs changes to `docs/readme-updates-{session}.md`

## Termination

**Fixed iterations** - runs exactly N times (default: 1).
