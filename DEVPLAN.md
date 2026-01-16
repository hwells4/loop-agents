# Agent Pipelines v3 Development Plan

**Status:** Active Development
**Target:** Event-sourced pipeline engine with deterministic execution
**Plan:** `docs/plans/v3-full-implementation.md`

---

## Phase Overview

| Phase | Branch | Deliverables | Status |
|-------|--------|--------------|--------|
| 0 | `feature/v3-event-spine` | compile.sh, events.sh, deps.sh, lock.sh | ✅ Complete |
| 1 | `feature/v3-foundation` | util.sh, unified executor, subshell fixes | ⏳ Pending |
| 2 | `feature/v3-node-executor` | runtime.sh, paths.sh, nodes: syntax | ⏳ Pending |
| 3 | `feature/v3-termination` | deciders.sh, judge.sh, result.json | ⏳ Pending |
| 4 | `feature/v3-parallel` | Integrate parallel.sh with event spine | ⏳ Pending |
| 5 | `feature/v3-observability` | status/tail commands with events | ⏳ Pending |
| 6 | `feature/v3-testing` | Comprehensive test suite | ⏳ Pending |
| — | — | **Core engine rebuilt** | — |
| 7 | `feature/v3-hooks` | hook_ctx.sh, gate, spawn, idempotency | ⏳ Pending |
| 8 | `feature/v3-library` | library.sh, CLI, resolve.sh | ⏳ Pending |

---

## Branch Strategy

```
main (stable)
│
└── dev/v3 (integration hub)
    │
    ├── feature/v3-event-spine      ← Phase 0 ✅ COMPLETE
    ├── feature/v3-foundation       ← Phase 1 (NEXT)
    ├── feature/v3-node-executor    ← Phase 2
    ├── feature/v3-termination      ← Phase 3
    ├── feature/v3-parallel         ← Phase 4
    ├── feature/v3-observability    ← Phase 5
    ├── feature/v3-testing          ← Phase 6
    ├── feature/v3-hooks            ← Phase 7
    └── feature/v3-library          ← Phase 8
```

### Workflow

1. Work on feature branches
2. PR feature → dev/v3 when phase complete
3. Test integration on dev/v3
4. PR dev/v3 → main when stable

---

## Phase 0: Event Spine ✅ COMPLETE

**Goal:** Replace state.json snapshot with event-sourced architecture

- [x] `scripts/lib/compile.sh` - YAML → plan.json
- [x] `scripts/lib/events.sh` - Append-only event logging
- [x] `scripts/lib/deps.sh` - Dependency checks (jq, yq v4, tmux, bd)
- [x] `scripts/lib/lock.sh` - flock-based session locking
- [x] Update `scripts/engine.sh` to use compiled plans

---

## Phase 1: Foundation

**Goal:** Clean up core infrastructure before building new features

### Beads
- `loop-agents-8od` - Create scripts/lib/util.sh with common helpers
- `loop-agents-2lq` - Unify run_stage and run_pipeline into single executor
- `loop-agents-i6f` - Eliminate subshell pipeline bugs in core modules

---

## Phase 2: Node Executor

**Goal:** Unified execution model for stages and nested pipelines

### Beads
- `loop-agents-2c4` - Create scripts/lib/runtime.sh with unified node executor
- `loop-agents-edc` - Create scripts/lib/paths.sh for deterministic artifact paths
- `loop-agents-olt` - Update pipeline YAML schema to use 'nodes:' syntax

### Dependencies
- Requires Phase 1 (unified executor foundation)

---

## Phase 3: Termination

**Goal:** Workers produce results, engine decides termination

### Beads
- `loop-agents-o82` - Create scripts/lib/deciders.sh for engine-owned termination
- `loop-agents-20t` - Create scripts/lib/judge.sh for judgment termination
- `loop-agents-9wm` - Define result.json schema and update worker prompts

### Dependencies
- Requires Phase 2 (node executor)

---

## Phase 4: Parallel

**Goal:** Integrate parallel execution with event spine

### Beads
- `loop-agents-c3c` - Integrate parallel.sh with event spine

### Dependencies
- Requires Phase 3 (termination)

---

## Phase 5: Observability

**Goal:** Event-based status and monitoring commands

### Beads
- `loop-agents-sro` - Add 'status' and 'tail' commands with event-based output

### Dependencies
- Requires Phase 4 (parallel integration)

---

## Phase 6: Testing

**Goal:** Comprehensive test coverage for event-sourced engine

### Beads
- `loop-agents-8gw` - Create comprehensive test suite for event-sourced engine

### Dependencies
- Requires Phase 5 (observability)

---

## — Core Engine Rebuilt —

At this point the core engine is complete. Phases 7-8 add features on top.

---

## Phase 7: Hooks

**Goal:** Event-based hooks with idempotency

### Beads
- `loop-agents-yq1` - Create scripts/lib/hook_ctx.sh for hook context generation
- `loop-agents-27c` - Implement gate action type for hooks
- `loop-agents-ipa` - Implement spawn action that reuses node executor
- `loop-agents-p4i` - Update scripts/lib/hooks.sh with event-based idempotency

### Dependencies
- Requires Phase 6 (core engine complete)

---

## Phase 8: Library

**Goal:** Local catalog of stages and pipelines

### Beads
- `loop-agents-630` - Create scripts/lib/library.sh for template library
- `loop-agents-n9q` - Add 'library' CLI command
- `loop-agents-8z7` - Update resolve.sh to include library root

### Dependencies
- Requires Phase 7 (hooks)

---

## Quick Reference

```bash
# View beads for a phase
bd list --label=phase/1-foundation

# Start next phase
git checkout dev/v3
git checkout -b feature/v3-foundation

# Run tests
./scripts/tests/run_tests.sh

# After completing phase
git checkout dev/v3
git merge feature/v3-foundation
git push
```
