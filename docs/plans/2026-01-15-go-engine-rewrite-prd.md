---
date: 2026-01-15
type: prd
status: draft
project: go-engine-rewrite
---

## Overview

**What we're building:** A Go-based rewrite of the Agent Pipelines engine that preserves existing pipeline/stage formats and output artifacts while improving reliability, concurrency safety, and cross-OS portability.

**Why:** The current Bash/jq/yq/tmux-based engine has concurrency hazards (events/state races), portability limitations (Windows, locked-down environments), and operational complexity. A single static Go binary reduces dependencies, simplifies installability, and enables safer parallel execution at scale.

**Scope:** Project-level PRD for a full engine rewrite. Preserve user-facing behavior and file formats for backward compatibility.

---

## User Stories

- As a developer, I want to run the same pipelines on macOS, Linux, or Windows without installing Bash tooling, so that setup is minimal.
- As an operator, I want parallel blocks to run without corrupting events or state, so that resumes and status views are trustworthy.
- As a pipeline author, I want existing stage/pipeline YAML and prompts to keep working, so that I do not need to rewrite content.
- As a CI user, I want deterministic outputs (`plan.json`, `context.json`, `events.jsonl`) so that test fixtures remain stable.
- As a platform engineer, I want to run multiple sessions concurrently without lock contention or data loss, so that workflows scale.

---

## Features

### Engine Parity

#### Feature 1.1: Pipeline Compilation Parity
**Description:** Compile pipeline YAML into `plan.json` identical in structure to the Bash engine.

**Acceptance Criteria:**
- [ ] Given an existing pipeline YAML, when compiled, then `plan.json` matches the current schema (v1) and structure.
- [ ] Given deprecated `stages:` usage, when compiled, then a warning is emitted and output is equivalent to `nodes:`.
- [ ] Given CLI overrides (provider/model/context), when compiled, then `plan.json` reflects overrides and `recompile` semantics match current behavior.

#### Feature 1.2: Stage Execution Parity
**Description:** Run stage iterations with the same prompt resolution and context generation behavior.

**Acceptance Criteria:**
- [ ] Given a stage YAML and prompt, when run, then output is written to the same `.claude/pipeline-runs/<session>/...` paths as today.
- [ ] Given a completion strategy, when run, then iteration termination matches current completion logic.
- [ ] Given failures from provider execution, when run, then state is marked failed with the same fields and resume guidance.

### Concurrency and Parallel Safety

#### Feature 2.1: Event Log Writer
**Description:** Append-only `events.jsonl` writer with file locking and buffering to prevent race conditions.

**Acceptance Criteria:**
- [ ] Given concurrent event emissions from parallel providers, when events are appended, then no events are lost or corrupted.
- [ ] Given a crashed writer, when resumed, then existing events remain intact and new events append correctly.
- [ ] Given large sessions, when appending events, then write cost is O(1) per event.

#### Feature 2.2: Parallel Block Execution
**Description:** Run parallel providers in goroutines with isolated state directories and a deterministic completion manifest.

**Acceptance Criteria:**
- [ ] Given a parallel block, when run, then provider stages run concurrently and produce isolated state.
- [ ] Given partial provider failure, when run, then block status is failed and manifest is not written.
- [ ] Given resume with completed providers, when run, then completed providers are skipped and incomplete providers re-run.

### Portability and Installability

#### Feature 3.1: Single Binary CLI
**Description:** Provide a static binary with no runtime dependency on jq/yq/tmux.

**Acceptance Criteria:**
- [ ] Given macOS/Linux/Windows, when running the binary, then pipelines execute without Bash tools.
- [ ] Given missing provider CLIs, when executing a provider, then the error message is explicit and actionable.
- [ ] Given no tmux, when running with `--foreground`, then sessions still execute cleanly.

### Compatibility Layer

#### Feature 4.1: CLI Compatibility Wrapper
**Description:** Optional wrapper script to map existing `scripts/run.sh` usage to the Go binary.

**Acceptance Criteria:**
- [ ] Given `./scripts/run.sh loop ralph auth 25`, when invoked, then the Go binary is executed with equivalent behavior.
- [ ] Given `./scripts/run.sh status <session>`, when invoked, then results match the Go binary.

---

## Technical Approach

**Architecture:**
- `cmd/agent-pipelines`: CLI entry point.
- `engine`: session lifecycle, stage execution, completion checks.
- `plan`: YAML parsing and `plan.json` compilation.
- `context`: context manifest generation and input resolution.
- `state`: atomic state updates and resume logic.
- `events`: locked append-only JSONL writer with tail/read helpers.
- `providers`: Claude/Codex adapters (CLI shell-out initially).
- `parallel`: goroutine-based parallel block orchestration.

**Data Flow:**
1. Parse pipeline YAML to `plan.json`.
2. Initialize run directory and `state.json`.
3. For each stage, generate `context.json` per iteration.
4. Execute provider CLI, write `result.json`/`status.json`.
5. Emit events and update state atomically.
6. On completion, write manifests and final state.

**Integrations:**
- Provider CLIs (Claude, Codex) via shell-out initially.
- Optional bd CLI usage only if configured (no hard dependency).

**Key Technical Decisions:**
- Preserve file formats and paths to minimize migration cost.
- Centralized event writer with file locks to prevent concurrency bugs.
- Atomic file writes for all stateful files.

**Constraints:**
- No breaking changes to pipeline/stage YAML in initial release.
- Must support concurrent sessions safely.

---

## Test Strategy

**Unit Tests:**
- Plan compilation (YAML -> plan.json)
- Completion strategies (fixed, judgment, queue)
- Event writer (append/read/tail with concurrency)
- State updates (atomicity, resume logic)

**Integration Tests:**
- Single-stage pipeline run
- Multi-stage pipeline run
- Parallel block execution with resume
- CLI compatibility wrapper

**E2E Scenarios:**
1. Single-stage loop: run N iterations with fixed completion.
2. Multi-stage pipeline: run sequential stages with context inputs.
3. Parallel block: two providers run concurrently and complete.

**Edge Cases to Test:**
- Simultaneous event writes from multiple providers
- Crash during iteration (resume from iteration_completed + 1)
- Missing provider CLI
- Windows path handling and file locks

---

## Out of Scope

- Provider SDK integration (API-based calls) in v1.
- New YAML schema or prompt format changes.
- UI or web dashboard.
- Multi-node distributed execution.

---

## Open Questions

- [ ] Should the Go binary fully replace `scripts/run.sh` or coexist behind a wrapper?
- [ ] Do we keep `.claude/` layout exactly or version it for the Go engine?
- [ ] Should we ship built-in completion strategies only, or preserve the plugin directory pattern?
- [ ] How should Windows file locking be handled in environments without POSIX locks?

---

## Notes

- Existing plans: `docs/plans/loop-architecture-v3.md`, `docs/plans/queue-provider-abstraction.md`.
- Current engine entrypoints: `scripts/run.sh`, `scripts/engine.sh`.
