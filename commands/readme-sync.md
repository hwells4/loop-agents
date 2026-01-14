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

## Advanced Options

Override provider, model, or inject context:

```bash
# Use Codex for sync
./scripts/run.sh readme-sync my-session 2 --provider=codex

# Use specific model
./scripts/run.sh readme-sync my-session 1 --model=sonnet

# Focus sync on specific sections
./scripts/run.sh readme-sync my-session 1 --context="Update only the installation and quickstart sections"

# Pass specific docs to sync from
./scripts/run.sh readme-sync my-session 1 --input=docs/changelog.md
```

See CLAUDE.md for full list of providers, models, and options.
