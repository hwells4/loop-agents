# Agent Pipelines v3 Development Plan

**Status:** Active Development
**Target:** Event-sourced pipeline engine with deterministic execution

## Branch Strategy

```
main (stable, production-ready)
│
└── dev/v3 (integration hub)
    │
    ├── feature/v3-event-spine      ← Phase 1 (CURRENT)
    ├── feature/v3-node-executor    ← Phase 2
    ├── feature/v3-termination      ← Phase 3
    ├── feature/v3-hooks            ← Phase 4
    └── feature/v3-library          ← Phase 5
```

### Workflow

1. Work on feature branches
2. PR feature → dev/v3 when phase complete
3. Test integration on dev/v3
4. PR dev/v3 → main when stable

### Current Branch

```
feature/v3-event-spine
```

---

## Phase Overview

| Phase | Branch | Deliverables | Status |
|-------|--------|--------------|--------|
| 1 | `feature/v3-event-spine` | plan.json, events.jsonl, compile.sh | 🔄 In Progress |
| 2 | `feature/v3-node-executor` | nodes:, nested pipelines, unified run_node | ⏳ Pending |
| 3 | `feature/v3-termination` | Engine-owned termination, judgment judge | ⏳ Pending |
| 4 | `feature/v3-hooks` | Hooks on events, jq conditions, gate action | ⏳ Pending |
| 5 | `feature/v3-library` | Local template library, fork/list commands | ⏳ Pending |

---

## Phase 1: Event Spine + Compilation

**Goal:** Replace state.json snapshot with event-sourced architecture

### Deliverables

- [ ] `scripts/lib/compile.sh` - Compile pipeline YAML → plan.json
- [ ] `scripts/lib/events.sh` - Append-only event logging
- [ ] `scripts/lib/deps.sh` - Dependency checks (jq, yq v4, tmux, bd)
- [ ] `scripts/lib/locks.sh` - flock-based session locking
- [ ] Update `scripts/engine.sh` to use compiled plans

### Files to Create

```
scripts/lib/
├── compile.sh      # YAML → plan.json compiler
├── events.sh       # Event spine (append, read, tail)
├── deps.sh         # Dependency validation
└── locks.sh        # Session locking
```

### Tests

```
scripts/tests/
├── test_compile.sh     # Plan compilation tests
├── test_events.sh      # Event spine tests
└── test_deps.sh        # Dependency check tests
```

### Success Criteria

- [ ] `plan.json` compiles correctly for all built-in stages
- [ ] `events.jsonl` records all session/iteration events
- [ ] Resume reads events and continues from correct point
- [ ] `yq` v4 required and detected

---

## Phase 2: One Recursive Node Executor

**Goal:** Unified execution model for stages and nested pipelines

### Deliverables

- [ ] `scripts/lib/runtime.sh` - run_session, run_node, run_stage, run_pipeline
- [ ] `scripts/lib/paths.sh` - Deterministic artifact paths
- [ ] Support for `nodes:` in pipeline YAML
- [ ] Support for `pipeline:` node type with `runs: N`

### Dependencies

- Requires Phase 1 (plan.json, events.jsonl)

---

## Phase 3: Engine-Owned Termination

**Goal:** Workers produce results, engine decides termination

### Deliverables

- [ ] `scripts/lib/deciders.sh` - fixed, queue, judgment deciders
- [ ] `scripts/lib/judge.sh` - Judge prompt invocation
- [ ] `result.json` format (replaces status.json as authoritative)
- [ ] Worker `decision` field becomes advisory only

### Dependencies

- Requires Phase 2 (node executor)

---

## Phase 4: Hooks Rebuilt

**Goal:** Event-based hooks with idempotency

### Deliverables

- [ ] `scripts/lib/hooks.sh` - Hook execution engine
- [ ] `scripts/lib/hook_ctx.sh` - Hook context generation
- [ ] jq-based condition evaluation
- [ ] Gate action (file, command modes)
- [ ] Idempotency via event log

### Dependencies

- Requires Phase 2 (event spine for idempotency)

---

## Phase 5: Template Library

**Goal:** Local catalog of stages and pipelines

### Deliverables

- [ ] `scripts/lib/library.sh` - list/info/fork commands
- [ ] `scripts/library/` directory structure
- [ ] User override directory (`~/.config/agent-pipelines/`)
- [ ] Resolution precedence: user > library > built-in

### Dependencies

- Requires Phase 1 (resolve.sh updates)

---

## Compatibility Mode

During migration:

1. If `events.jsonl` exists → event-sourced execution
2. If only `state.json` exists → legacy execution
3. New sessions always use event-sourced

Set `AGENT_PIPELINES_LEGACY=1` to force legacy mode for rollback.

---

## Quick Reference

```bash
# Current branch
git branch --show-current

# Switch to phase work
git checkout feature/v3-event-spine

# After completing phase, merge to dev/v3
git checkout dev/v3
git merge feature/v3-event-spine
git push

# Create next phase branch from dev/v3
git checkout -b feature/v3-node-executor

# Run tests
./scripts/run.sh test

# Run lint
./scripts/run.sh lint
```
