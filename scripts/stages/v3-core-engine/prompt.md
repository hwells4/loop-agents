# v3 Core Engine Agent Instructions

Read context from: ${CTX}
Progress file: ${PROGRESS}

${CONTEXT}

## Scope

You are implementing the **v3 event-sourced pipeline engine** - phases 1-6 only.
This is the **core engine** without hooks or library features (those come later).

**Your scope:**
- Phase 1: Foundation (util.sh, unified executor, subshell fixes)
- Phase 2: Node Executor (runtime.sh, paths.sh, nodes: syntax)
- Phase 3: Termination (deciders.sh, judge.sh, result.json)
- Phase 4: Parallel (integrate parallel.sh with event spine)
- Phase 5: Observability (status/tail commands)
- Phase 6: Testing (comprehensive test suite)

**NOT in scope (save for later):**
- Phase 7: Hooks (hook_ctx.sh, gate, spawn, idempotency)
- Phase 8: Library (library.sh, CLI, resolve.sh updates)

## Your Task

1. Read `${PROGRESS}` (check Codebase Patterns first)

2. **Read the implementation plan:**
   ```bash
   cat docs/plans/v3-full-implementation.md
   ```

3. Check remaining tasks (phases 1-6 only):
   ```bash
   bd ready --label=pipeline/v3 --label-any=phase/1-foundation,phase/2-node-executor,phase/3-termination,phase/4-parallel,phase/5-observability,phase/6-testing
   ```

4. Pick highest priority task

5. Claim it:
   ```bash
   bd update <bead-id> --status=in_progress
   ```

6. **Read the bead details before implementing:**
   ```bash
   bd show <bead-id>
   ```

7. Implement that ONE task following the v3 plan

8. **Run tests after every change:**
   ```bash
   # REQUIRED: Run the test suite - DO NOT skip this
   ./scripts/tests/run_tests.sh

   # If the test runner path changed, find it:
   # find scripts -name "run_tests.sh" -o -name "*_test.sh" | head -5

   # Also run lint validation
   ./scripts/run.sh lint
   ```

   **IMPORTANT:** All tests must pass before closing a bead. If tests fail, fix them before proceeding.

9. Commit: `feat(v3): [bead-id] - [Title]`

10. Close the task:
    ```bash
    bd close <bead-id>
    ```

11. Append learnings to progress file

## Progress Format

APPEND to ${PROGRESS}:

```markdown
## [Date] - [bead-id]
- What was implemented
- Files changed
- **Learnings:**
  - Patterns discovered
  - Gotchas encountered
---
```

## Codebase Patterns

Add reusable patterns to the TOP of progress file:

```markdown
## Codebase Patterns
- [Pattern]: [How to use it]
- [Pattern]: [How to use it]
```

## Key v3 Architecture Principles

1. **events.jsonl is authoritative** - state.json is a derived cache
2. **Compile once, execute many** - plan.json from YAML before runtime
3. **Atomic writes everywhere** - temp file + mv for JSON files
4. **No subshell pipeline bugs** - use `while read ... done < <(cmd)` not `cmd | while read`
5. **Engine-owned termination** - workers produce results, engine decides

## Implementation Reference

Key files to create/modify (from v3 plan):
- `scripts/lib/compile.sh` - YAML to plan.json
- `scripts/lib/events.sh` - Append-only event logging
- `scripts/lib/state.sh` - State snapshot from events
- `scripts/lib/runtime.sh` - Unified node executor
- `scripts/lib/paths.sh` - Deterministic artifact paths
- `scripts/lib/deciders.sh` - fixed, queue, judgment
- `scripts/lib/judge.sh` - Judge prompt for judgment termination

## Stop Condition

If queue is empty (all phases 1-6 beads complete):
```bash
bd ready --label=pipeline/v3 --label-any=phase/1-foundation,phase/2-node-executor,phase/3-termination,phase/4-parallel,phase/5-observability,phase/6-testing
# Returns nothing = done
```

Write to `${RESULT}`:

```json
{
  "summary": "Queue empty - core engine ready, hooks/library phases can proceed",
  "work": {"items_completed": [], "files_touched": []},
  "artifacts": {"outputs": [], "paths": []},
  "signals": {"plateau_suspected": true, "risk": "low", "notes": "All v3 core engine tasks complete (phases 1-6)"}
}
```

Otherwise, set `"signals.plateau_suspected": false` and end normally.
