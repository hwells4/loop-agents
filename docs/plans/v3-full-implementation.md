# Final Features v2: Event-Sourced Pipeline Engine

**Status:** Planning
**Author:** Harrison Wells
**Date:** 2026-01-14
**Revision:** 2.1

---

## Executive Summary

This plan defines a significant architectural evolution: replacing the current state.json snapshot model with an event-sourced architecture using events.jsonl as the single source of truth. The key insight is that event sourcing provides determinism, debuggability, and correct resume semantics that the current model cannot guarantee.

**Key Changes from v1:**
- events.jsonl replaces state.json as authoritative (state.json becomes a derived cache)
- plan.json compilation eliminates repeated YAML parsing
- Engine-owned termination replaces worker-controlled decisions
- Minimal template library replaces full marketplace (deferred scope)

---

## Decisions Locked In

* **events.jsonl becomes the single spine** for runtime truth, observability, and resume correctness
* **Pipelines compile to a deterministic executable JSON plan** before anything runs
* **Every pipeline node is a runnable unit** with `runs` defaulting to 1
* **One recursive primitive** runs both stages and nested pipelines, eliminating a separate “cycles” feature
* **Termination is engine-owned**; workers produce results and signals, not control-plane decisions
* **Hooks remain, with fewer lifecycle points** and strict idempotency via the event log
* **Marketplace is deferred**; replace with a minimal local template library that is structurally extendable later
* **Progress compaction deferred**
* **Capability permission model deferred** but explicitly reserved in schema and architecture
* **Dependency discipline enforced** (notably `yq`)

---

# Part 0: Target Architecture

## Runtime artifacts

Session directory becomes a deterministic execution record:

```
.claude/pipeline-runs/{session}/
├── plan.json                 # compiled executable plan (authoritative)
├── state.json                # cursor snapshot (cache), derived from events
├── events.jsonl              # append-only spine (authoritative)
├── artifacts/
│   ├── node-{node_path}/
│   │   ├── run-0001/
│   │   │   ├── iteration-0001/
│   │   │   │   ├── ctx.json
│   │   │   │   ├── progress.md
│   │   │   │   ├── result.json
│   │   │   │   └── worker.log
│   │   │   └── output.json   # engine-aggregated node output for this run
│   └── ...
└── locks/
    └── session.lock
```

Authoritative truth is `events.jsonl` + `plan.json`. `state.json` is a snapshot cache for speed.

## Core runtime principles

* **Compile once, execute many**: YAML is resolved/validated/merged once into `plan.json`. Runtime reads JSON only. Recompilation triggers when source YAML mtime > plan.json mtime, or via explicit `--recompile` flag.
* **Event-sourced execution**: every significant effect is an event. Resume replays or fast-forwards using the event stream.
* **Idempotent hooks**: hooks never re-fire on resume unless forced.
* **One executor**: `run_node` executes a node, regardless of whether it is a stage or nested pipeline.

---

# Part 1: Executable plan compilation

## Purpose

* Determinism and debuggability
* Faster runtime by eliminating repeated YAML parsing
* A single place to validate schema, defaults, merges, and precedence

## Inputs

* Pipeline YAML (entrypoint)
* Stage YAMLs referenced by the pipeline
* Global config (minimal for now; hooks and template roots)
* Template library roots

## Output: `plan.json`

Minimal shape:

```json
{
  "version": 1,
  "session": {
    "name": "bug-hunt",
    "created_at": "2026-01-14T00:00:00Z"
  },
  "dependencies": {
    "jq": true,
    "yq": true,
    "tmux": true,
    "bd": true
  },
  "hooks": {
    "points": ["on_session_start","on_iteration_complete","on_node_complete","on_session_complete","on_error"],
    "actions": { "...": [] }
  },
  "nodes": [
    {
      "path": "0",
      "id": "plan",
      "kind": "stage",
      "ref": "improve-plan",
      "termination": { "type": "fixed", "max": 5 },
      "provider": { "type": "claude_code", "model": "default" },
      "inputs": {}
    },
    {
      "path": "1",
      "id": "work",
      "kind": "stage",
      "ref": "ralph",
      "termination": { "type": "queue", "command": "bd ready ..." },
      "provider": { "type": "claude_code", "model": "default" },
      "inputs": {}
    }
  ],
  "future": {
    "capabilities": { "enabled": false }
  }
}
```

## Schema changes for pipeline YAML

Keep authoring YAML simple; compilation normalizes.

### Pipeline YAML shape

Use `nodes:` for pipeline definitions:

```yaml
name: bug-hunt
description: Discover → design → fix

nodes:
  - id: discover
    stage: bug-discovery
    runs: 3

  - id: design
    stage: elegance
    runs: 2

  - id: fix
    stage: ralph
    runs:
      type: queue
      command: "bd ready --label=bugs"
```

### Nested pipeline node

This is the unified “cycles” primitive.

```yaml
nodes:
  - id: harden
    pipeline: bug-hunt
    runs: 5
```

Compilation resolves `pipeline: bug-hunt` into its referenced YAML, compiles it to an embedded subplan, and produces a node that executes that subplan 5 times.

## Implementation files

```
scripts/lib/
├── compile.sh          # compile pipeline YAML → plan.json
├── resolve.sh          # resolve stage/pipeline refs using roots and precedence
├── validate.sh         # schema validation for pipeline + stage configs
└── deps.sh             # dependency checks with versions
```

## Deterministic resolution rules

* Stage resolution precedence: **user overrides > template library > built-in**
* Pipeline resolution precedence: same
* Merge strategy during compilation:

  * Stage defaults (provider, termination defaults, prompt template path)
  * Node overrides in pipeline YAML
  * Global hooks and per-pipeline/per-stage hooks merged into final plan hooks

## Dependency discipline

* README updated: `yq` required (v4, Go-based - NOT the Python-based v3)
* `scripts/lib/deps.sh` enforces:

  * `jq` present (1.6+)
  * `yq` present and v4+ (detect via `yq --version`, provide install instructions if wrong)
  * `tmux` present if tmux mode used
  * `bd` present if queue termination is used

**Cross-platform lock handling:**

| Platform | Lock Implementation |
|----------|---------------------|
| Linux | `flock` (util-linux, typically pre-installed) |
| macOS | `flock` via Homebrew (`brew install flock`) or fallback to `shlock` |
| CI/CD | `--no-lock` flag for single-process runs where locking is unnecessary |

The `deps.sh` script auto-detects platform and selects appropriate lock mechanism.

## Compilation Error Handling

When compilation fails, provide actionable errors:

```json
{
  "error": "compilation_failed",
  "phase": "stage_resolution",
  "message": "Stage 'improve-plan' not found",
  "searched": [
    "~/.config/agent-pipelines/stages/improve-plan",
    "scripts/library/stages/improve-plan",
    "scripts/stages/improve-plan"
  ],
  "suggestion": "Run 'library list' to see available stages"
}
```

Compilation must be **idempotent**: compiling the same inputs always produces identical `plan.json`. This enables caching and deterministic testing.

---

# Part 2: Event Spine

## Purpose

Single source of truth for:

* monitoring
* debugging
* idempotency
* resume
* test assertions

## File: `events.jsonl`

Each line is a JSON object.

### Required fields

* `ts` ISO 8601
* `type` event type
* `session`
* `cursor` stable cursor object

Cursor object shape:

```json
{
  "node_path": "1.0.2",
  "node_run": 1,
  "iteration": 5
}
```

### Core event types

* `session_start`
* `plan_compiled`
* `node_start`
* `node_run_start` (run index inside node when `runs > 1`)
* `iteration_start`
* `worker_complete`
* `iteration_complete`
* `hook_start`
* `hook_complete`
* `node_complete`
* `session_complete`
* `error`

### Example events

```json
{"ts":"...","type":"plan_compiled","session":"bug-hunt","plan_sha":"..."}
{"ts":"...","type":"iteration_start","session":"bug-hunt","cursor":{"node_path":"0","node_run":1,"iteration":1},"provider":{"type":"claude_code"}}
{"ts":"...","type":"worker_complete","session":"bug-hunt","cursor":{"node_path":"0","node_run":1,"iteration":1},"result_path":".../result.json","exit_code":0}
{"ts":"...","type":"hook_complete","session":"bug-hunt","cursor":{"node_path":"0","node_run":1,"iteration":1},"hook_point":"on_iteration_complete","action_id":"tests","status":"failed"}
```

## State snapshot

`state.json` is a cache derived from events:

* last cursor
* last plan sha
* last processed event offset
* last error pointer

Resume algorithm:

1. Acquire flock on `session.lock`
2. Read `plan.json` (fail if missing or malformed)
3. Read `state.json` if present for fast cursor lookup
4. If `state.json.event_offset` < actual events.jsonl length:
   - Tail events from offset to end
   - Rebuild cursor from events (reconciliation)
5. Identify resume point:
   - Find last `iteration_complete` or `node_complete` event
   - Resume from next iteration/node
6. For each hook that should have fired at current cursor:
   - Check if `hook_complete` event exists for (hook_point, action_id, cursor)
   - Skip if found (idempotency)
7. Continue execution from cursor

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| `events.jsonl` corrupted (truncated JSON) | Discard incomplete final line, log warning |
| `plan.json` missing | Fail with clear error: "Recompile required" |
| `state.json` missing | Rebuild from events (slow but correct) |
| Lock held by dead process | Stale lock detection via PID check |
| Iteration started but no complete event | Retry that iteration |
| Disk full during event append | Fail gracefully, emit error to stderr, release lock |
| Concurrent write attempts to `events.jsonl` | Prevented by session lock; second writer fails fast |
| Event timestamp out of order | Log warning but accept (clock skew possible) |
| Concurrent append attempts | Session lock prevents this; if lock bypassed, last-write-wins with warning |
| Event file exceeds 100MB | Archive older events to `events.{timestamp}.jsonl`, start fresh |

## Event Ordering Guarantees

Events are written atomically (write to temp file, then rename). The engine guarantees:

1. `iteration_start` always precedes `worker_complete` for same cursor
2. `hook_start` always precedes `hook_complete` for same hook invocation
3. `node_start` precedes all events within that node
4. No event is written until the action it describes has fully completed

This enables correct replay without re-executing completed work.

## Implementation Files

```
scripts/lib/
├── events.sh           # append_event, read_events, last_event, render_status
├── state.sh            # write_snapshot, load_snapshot, reconcile_with_events
└── locks.sh            # flock-based session lock
```

---

# Part 3: One recursive node executor

## Purpose

Eliminate separate “cycles” machinery and separate “spawn” runtime logic.
One executor runs:

* a stage node
* a pipeline node
* any nested composition

## Node semantics

* `runs` defaults to 1
* A node run executes:

  * for stage: a stage loop driven by the node’s termination settings
  * for pipeline: executes the referenced subplan once
* If `runs > 1`, repeat node run N times with separate run directories

## Termination settings

Termination is attached to the node in `plan.json`, regardless of whether it originated in stage.yaml defaults or pipeline overrides.

Supported termination types in v1 runtime:

* `fixed`: `max`
* `queue`: `command`

Judgment exists, but implemented as engine-owned decider (next section).

## Directory mapping

Node path provides stable artifact placement:

* `node_path: "1.0"` maps to `artifacts/node-1.0/`

Node run index maps:

* `run-0001`, `run-0002`

Iteration index maps:

* `iteration-0001`, `iteration-0002`

## Implementation files

```
scripts/lib/
├── runtime.sh          # run_session(plan), run_node(node), run_stage(node), run_pipeline(node)
└── paths.sh            # deterministic artifact path helpers
```

---

# Part 4: Engine-owned termination and judges

## Purpose

Stop delegating control flow to worker prompts.
Workers produce outputs; the engine decides whether to continue.

## Worker contract

Workers write a `result.json` file.

### `result.json` minimal schema

```json
{
  "summary": "what changed",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "artifacts": {
    "outputs": [],
    "paths": []
  },
  "signals": {
    "plateau_suspected": false,
    "risk": "low",
    "notes": ""
  }
}
```

## Deciders

Deciders are engine functions that return `continue|stop`.

### Fixed decider

* stop when `iteration == max`

### Queue decider

* stop when queue command returns empty

### Judgment decider

Judgment becomes a judge invocation, not a second worker pass.

* The engine calls a **judge prompt** with read-only context:

  * latest `result.json`
  * node output so far
  * progress.md
  * termination criteria
* Judge returns a small JSON:

```json
{ "stop": true, "reason": "plateau", "confidence": 0.82 }
```

**Judgment policy (v1):**

* stop when judge returns `stop=true` for **two consecutive iterations** (two separate Claude invocations, each reaching the same conclusion independently)
* max iteration cap still applies if provided
* min_iterations must complete before judgment begins (default: 2)
* worker `signals.plateau_suspected: true` counts as advisory input to judge, not a control decision

**Judge execution model:**

* implemented as a special internal stage runner:

  * provider can be configured independently (default: Claude Haiku for cost efficiency)
  * judge writes `judge.json` into iteration dir
  * engine appends `judgment` event to events.jsonl

**Judge prompt location:** `scripts/prompts/judge.md` (built-in) or `~/.config/agent-pipelines/prompts/judge.md` (user override)

**Judge prompt template:**

```markdown
You are evaluating whether a pipeline stage should stop.

## Context
- Stage: ${STAGE_NAME}
- Iteration: ${ITERATION}
- Goal: ${TERMINATION_CRITERIA}

## Latest Work
${RESULT_JSON}

## Progress So Far
${PROGRESS_MD}

## Your Task
Determine if the goal has been achieved or if further iterations would be unproductive.

Output exactly:
```json
{ "stop": true/false, "reason": "...", "confidence": 0.0-1.0 }
```

**Important:**
- stop=true means "goal achieved OR no further progress possible"
- stop=false means "meaningful work remains AND progress is being made"
- confidence is your certainty in the decision
```

**Judge failure handling:**

| Scenario | Behavior |
|----------|----------|
| Judge returns invalid JSON | Treat as `stop: false`, log warning, increment `judge_failures` counter |
| Judge invocation fails | Retry once, then treat as `stop: false` |
| Confidence < 0.5 | Treat as `stop: false` (require high confidence to stop) |
| Three consecutive judge failures | Emit `judge_unreliable` event, fall back to fixed max termination |
| Judge timeout (> 60s) | Treat as failure, apply retry logic |

## Implementation Files

```
scripts/lib/
├── deciders.sh         # fixed, queue, judgment logic
└── judge.sh            # judge prompt rendering + invocation + parsing
```

---

# Part 5: Hooks, rebuilt around events and idempotency

## Goals

* Integrations and gates without destabilizing runtime
* Zero duplicate effects on resume
* Minimal lifecycle points to avoid hook spam

## Hook points in v1

* `on_session_start`
* `on_iteration_complete`
* `on_node_complete` (replaces stage_complete and pipeline_complete distinctions)
* `on_session_complete`
* `on_error`

`on_iteration_start` remains a reserved point, not enabled by default.

## Hook Context

Replace env-var explosion with a single file path:

* `HOOK_CTX=/.../hook_ctx.json`

**Complete hook_ctx.json schema:**

```json
{
  "session": {
    "name": "bug-hunt",
    "started_at": "2026-01-14T10:00:00Z"
  },
  "cursor": {
    "node_path": "1.0",
    "node_run": 2,
    "iteration": 5
  },
  "node": {
    "id": "fix",
    "kind": "stage",
    "ref": "ralph"
  },
  "paths": {
    "session_dir": ".claude/pipeline-runs/bug-hunt",
    "node_dir": ".claude/pipeline-runs/bug-hunt/artifacts/node-1.0",
    "iteration_dir": ".claude/pipeline-runs/bug-hunt/artifacts/node-1.0/run-0002/iteration-0005",
    "result": ".../result.json",
    "progress": ".../progress.md"
  },
  "result": {
    "summary": "Fixed authentication bug",
    "work": { "items_completed": ["auth-fix"], "files_touched": ["src/auth.ts"] }
  },
  "previous_hooks": {
    "tests": { "status": "success", "exit_code": 0 },
    "lint": { "status": "failed", "exit_code": 1, "error": "ESLint found 3 errors" }
  },
  "plan": {
    "name": "bug-hunt",
    "total_nodes": 3
  }
}
```

**Environment variables also available:**

| Variable | Value |
|----------|-------|
| `HOOK_CTX` | Path to hook_ctx.json |
| `SESSION` | Session name |
| `ITERATION` | Current iteration |

## Conditions

Replace `eval` with jq expressions over `hook_ctx.json`.

Example:

```yaml
when: '.cursor.iteration % 10 == 0 and .node.id == "fix"'
```

Runtime evaluation:

```bash
jq -e "$when" "$HOOK_CTX" >/dev/null
```

## Actions in v1

* `shell`
* `webhook`
* `spawn` (thin wrapper over the same node executor)
* `gate` (replaces callback servers)

### Gate action

Supported modes:

* `file`: wait until a file exists and optionally matches content
* `command`: wait until a command returns exit 0
* `queue`: wait until a queue condition is met via command

Example:

```yaml
- id: approval
  type: gate
  mode: file
  path: ".claude/approvals/${SESSION}.approved"
  timeout: 86400
  on_timeout: abort
```

**Gate timeout behavior:**

| `on_timeout` | Behavior |
|--------------|----------|
| `abort` | Fail the pipeline, emit `error` event, cleanup gracefully |
| `continue` | Log warning, proceed with pipeline, set `gate_status: timeout` in hook result |
| `skip` | Skip remaining hooks at this point, continue pipeline |

**Cleanup on abort:**

1. Emit `gate_timeout` event with gate details
2. Emit `session_complete` event with `reason: gate_timeout`
3. Release session lock
4. Exit with code 124 (timeout)

## Hook Action Ordering

When multiple actions are defined for a single hook point:

1. Actions execute **sequentially** in definition order (not parallel)
2. Each action completes before the next starts
3. If an action fails and `on_failure: abort`, remaining actions are skipped
4. If `on_failure: continue` (default), subsequent actions still run
5. Hook-level `parallel: true` can override to run all actions concurrently (advanced use)

## Idempotency Rule

An action is uniquely identified by:

* `hook_point`
* `action_id`
* `cursor` (node_path, node_run, iteration)

Before running an action, the engine checks `events.jsonl` for an existing `hook_complete` for that key.

* If found, skip
* If not found, execute and append `hook_start` and `hook_complete`

## Implementation files

```
scripts/lib/
├── hooks.sh            # execute_hooks(hook_point, hook_ctx_path)
└── hook_ctx.sh         # build_hook_ctx from plan + cursor + artifacts + events
```

---

# Part 6: Minimal template library (marketplace deferred)

## Goals

* Provide a “catalog of templates” without remote installs, gists, PR automation, or import logic
* Maintain extendable structure for a future marketplace

## Directory layout

```
scripts/
├── stages/                 # built-in
├── pipelines/              # built-in
└── library/                # shipped templates, treated as community pack
    ├── stages/
    └── pipelines/

~/.config/agent-pipelines/
├── stages/                 # user overrides
└── pipelines/
```

## CLI

Add `library` command, strictly local:

* `library list`
* `library info <name>`
* `library fork <name> <new_name>` into user config

No remote import, no create-from-prompt, no contribute flow in this launch plan.

## Resolution order

* user > library > built-in

This keeps the extension path while deleting the heavy machinery.

## Fork Semantics

When forking a stage:

1. Copy all files from source to `~/.config/agent-pipelines/stages/<new_name>/`
2. Update `name` field in stage.yaml
3. Add `forked_from` metadata: `{ "source": "elegance", "timestamp": "..." }`
4. **Do not rewrite prompt template variables** - they remain generic (`${CTX}`, `${PROGRESS}`)
5. If `stage.yaml` has custom `prompt:` path, copy that file too and update path to be relative
6. User can then customize prompt.md as needed

**Fork validation:** After fork, run `./scripts/run.sh lint stage <new_name>` to verify the fork is valid.

## Implementation files

```
scripts/lib/
└── library.sh          # list/info/fork + uses resolve.sh
```

---

# Part 7: Parallel Provider Integration

## Existing Implementation

The current codebase has `scripts/lib/parallel.sh` which provides parallel provider execution. This must be integrated with the event spine.

## Event Flow for Parallel Blocks

```
node_start (path: "1", kind: "parallel")
├── parallel_provider_start (provider: "claude")
│   ├── iteration_start (provider: "claude", iteration: 1)
│   ├── worker_complete (provider: "claude", iteration: 1)
│   └── ...
├── parallel_provider_complete (provider: "claude")
├── parallel_provider_complete (provider: "codex")
└── node_complete (path: "1")
```

## Extended Cursor for Parallel Blocks

```json
{ "node_path": "1", "node_run": 1, "provider": "claude", "iteration": 5 }
```

The `provider` field is only present for events within a parallel block.

## Resume within Parallel Block

1. Check which providers completed (have `parallel_provider_complete` event)
2. Skip completed providers
3. For incomplete providers, find last `iteration_complete` and resume
4. Wait for all providers before emitting `node_complete`

### Parallel Resume Edge Cases

| Scenario | Behavior |
|----------|----------|
| One provider crashed mid-iteration | Resume that provider from last `iteration_start`; other completed providers remain skipped |
| All providers crashed at different points | Resume each independently; no cross-provider state sharing |
| Provider completed but outputs corrupted | Re-run provider from scratch (treat as incomplete) |
| Parallel block itself crashed before any provider started | Re-run entire block from scratch |
| Some providers never started | Start missing providers while skipping completed ones |
| Provider hangs indefinitely | Per-provider timeout (default: 30 min); emit `provider_timeout` event, treat as failure |

### Parallel Block Failure Modes

**Fail-fast vs fail-slow:**
```yaml
parallel:
  providers: [claude, codex]
  failure_mode: fail_slow  # Default: continue other providers even if one fails
  # fail_fast: abort all providers immediately on first failure
```

**Provider-specific retry:**
```yaml
parallel:
  providers:
    - name: claude
      retries: 2
    - name: codex
      retries: 0  # No retries for this provider
```

---

# Part 8: Refactor Notes to Eliminate Known Shell Failure Classes

These are implementation requirements, not optional niceties.

## Subshell pipeline bugs

Eliminate patterns like:

* `... | while read ...; do ...; done`

Replace with:

* `while read ...; do ...; done < <(command)`

Apply systematically across hooks, library listing, stage discovery, and compilation.

## Atomic writes everywhere

Write JSON files with:

* `tmp="$(mktemp ...)" ; write ; mv "$tmp" "$final"`

Applies to:

* plan.json
* state.json
* ctx.json
* result.json (engine can enforce by writing wrapper file then moving)
* output.json
* any synthesized hook_ctx.json

## Session lock

Use `flock` on a lock file for:

* entire run
* resume
* state snapshot updates

Parallel provider work remains per-iteration isolated; shared state updates remain locked.

**Locking in parallel blocks:**
- Main session holds master lock on `session.lock`
- Each parallel provider runs as a child process, does NOT acquire separate locks
- Event appends use atomic write (temp file + rename), no locking needed
- State snapshot updates are engine-owned, happen after parallel block completes

---

# Implementation roadmap

## Phase 1: Event spine + compilation

Deliverables

* `plan.json` compilation for existing pipelines and stages
* `events.jsonl` append-only logging for session, node, iteration, errors
* `state.json` snapshot cache derived from events
* dependency checks including `yq`

Files

* `scripts/lib/compile.sh`
* `scripts/lib/events.sh`
* `scripts/lib/state.sh`
* `scripts/lib/deps.sh`
* `scripts/lib/locks.sh`
* wire into `scripts/engine.sh`

Tests

* compile fixture produces stable plan.json
* events written in correct order for a mock run
* resume replays correctly without duplicating events

### Phase 1 Test Cases (Detailed)

**Compilation tests (`scripts/tests/unit/compile_test.sh`):**
```bash
test_compile_single_stage_produces_valid_plan
test_compile_multi_stage_pipeline_resolves_all_refs
test_compile_fails_on_missing_stage_ref
test_compile_fails_on_circular_pipeline_refs
test_compile_is_idempotent  # Same inputs → identical outputs
test_compile_merges_stage_defaults_with_node_overrides
test_compile_includes_dependency_versions
```

**Event spine tests (`scripts/tests/unit/events_test.sh`):**
```bash
test_append_event_atomically_writes
test_append_event_handles_disk_full_gracefully
test_read_events_skips_truncated_final_line
test_last_event_returns_most_recent
test_events_include_required_fields  # ts, type, session, cursor
```

**State reconciliation tests (`scripts/tests/unit/state_test.sh`):**
```bash
test_state_derived_from_events_matches_snapshot
test_state_rebuild_handles_missing_state_json
test_state_reconcile_detects_stale_offset
test_state_cursor_advances_correctly_across_nodes
```

## Phase 2: One recursive node executor with runs

Deliverables

* `nodes:` pipeline authoring supported
* nested `pipeline:` nodes supported with `runs: N`
* unified artifact directory layout keyed by node_path/run/iteration

Files

* `scripts/lib/runtime.sh`
* `scripts/lib/paths.sh`
* update `engine.sh` to call runtime over plan.json

Tests

* nested pipeline runs N times produce deterministic directories
* state cursor increments correctly across node boundaries and nested boundaries

## Phase 3: Engine-owned termination + judgment judge

Deliverables

* deciders: fixed and queue fully engine-owned
* judgment uses judge invocation and "two consecutive stops" rule
* worker decision ignored as control-plane
* `result.json` parsing and validation

Files

* `scripts/lib/deciders.sh`
* `scripts/lib/judge.sh`
* update built-in stage prompts to write `result.json` (or allow engine wrapper)

Tests

* fixed terminates exactly at max
* queue terminates when command empty
* judgment terminates only after two consecutive judge stops

## Phase 4: Hooks rebuilt on events + jq conditions + gate

Deliverables

* hook points limited set
* hook_ctx.json per hook invocation
* jq `when` evaluation
* idempotency keyed by (hook_point, action_id, cursor)
* `gate` action (file + command modes)
* spawn action reuses node executor

Files

* `scripts/lib/hooks.sh`
* `scripts/lib/hook_ctx.sh`

Tests

* hooks do not re-fire on resume
* conditions correctly filter execution
* gate blocks and records outcome; on timeout obeys policy
* spawn produces events and correct child artifact placement without corrupting parent cursor

## Phase 5: Minimal template library

Deliverables

* `scripts/library/` roots recognized
* `library list/info/fork` command
* resolution precedence user > library > built-in

Files

* `scripts/lib/library.sh`
* update `resolve.sh` to include library root

Tests

* precedence works with same-named stage in all roots
* fork copies and rewrites name metadata deterministically

---

# Updated success criteria

## Determinism and reliability

* [ ] `plan.json` is compiled once and used as the sole execution spec
* [ ] `events.jsonl` contains a complete linear record of session execution
* [ ] resume continues from cursor without duplicated hooks or duplicated side effects
* [ ] state.json can be deleted and reconstructed from events without losing correctness
* [ ] no subshell pipeline bugs in core modules

## Node model and recursion

* [ ] every node supports `runs` default 1
* [ ] nested pipeline nodes run N times and remain isolated by run directories
* [ ] stage nodes and pipeline nodes share the same executor and event semantics

## Engine-owned termination and judges

* [ ] fixed and queue termination do not rely on worker decisions
* [ ] judgment termination uses judge results and obeys consecutive-stop rule

## Hooks

* [ ] hook conditions use jq over hook_ctx.json
* [ ] hook actions are idempotent across resume
* [ ] gate action supports file and command waits with timeout policies
* [ ] spawn uses the same executor primitive and does not fork a second runtime

## Template library

* [ ] local catalog exists without remote import machinery
* [ ] user overrides library and built-in deterministically
* [ ] fork produces a runnable stage or pipeline immediately

## Future reserved items

* Capability permission model reserved in schema and plan.json but disabled for launch
* Remote marketplace features reserved behind the library structure but not implemented
* Cost metering per iteration (token tracking, budget caps) - reserved in event schema
* Session inheritance (context compression, fact inheritance) - reserved in plan.json schema
* Model tier strategy (Haiku/Sonnet/Opus per phase) - reserved in provider config

---

# Part 8: Observability (Minimal v1)

While a full metrics dashboard is deferred, the event spine enables basic observability out of the box.

## Event-Based Status Command

```bash
./scripts/run.sh status <session>
```

Outputs:
```
Session: bug-hunt
Status: running
Node: 1.0 (fix/ralph)
Run: 2/3
Iteration: 7
Last event: worker_complete (2m ago)
Health: ok
Errors: 0
Duration: 45m
```

## Real-Time Tailing

```bash
./scripts/run.sh tail <session>
```

Streams events.jsonl with human-readable formatting:
```
[10:45:01] iteration_start node=1.0 run=2 iter=7
[10:47:23] worker_complete exit=0 files=3
[10:47:24] hook_start point=on_iteration_complete action=tests
[10:47:45] hook_complete status=success
```

## Health Calculation

Simple health score derived from events:

```python
health = 1.0
health -= 0.1 * consecutive_errors
health -= 0.05 * (iterations_without_progress)
health = max(0.0, health)
```

Health < 0.3 triggers warning in status output.

## Deferred: Full Dashboard

A web-based dashboard with:
- Real-time session monitoring
- Historical metrics
- Cost tracking per session
- Cross-session comparison

This is explicitly out of scope for v1 but the event spine is designed to support it.

## Deferred: Cost Metering (Reserved in Event Schema)

Events may include optional `usage` block for future token tracking:

```json
{"type": "worker_complete", ..., "usage": {"input_tokens": 12500, "output_tokens": 3200}}
```

The engine does not calculate costs in v1, but preserves usage data when available from providers.

---

# Part 9: Testing Strategy

## Test Categories

| Category | Purpose | Implementation |
|----------|---------|----------------|
| Unit tests | Test individual shell functions | `scripts/tests/unit/` using bats-core |
| Integration tests | Test multi-component flows | `scripts/tests/integration/` using mock providers |
| Fixture tests | Verify plan compilation | `scripts/tests/fixtures/` with expected outputs |
| Regression tests | Prevent known bug recurrence | `scripts/tests/regression/` |

## Mock Provider

For testing, use a mock provider that:
- Returns immediately with configurable exit codes
- Writes predictable result.json content
- Logs invocations for assertion

```bash
# scripts/tests/mock_provider.sh
echo '{"summary":"mock work","work":{}}' > "$RESULT_PATH"
exit "${MOCK_EXIT_CODE:-0}"
```

## Test Fixtures

```
scripts/tests/fixtures/
├── stages/
│   ├── simple-stage/
│   └── complex-stage/
├── pipelines/
│   ├── linear-pipeline.yaml
│   ├── nested-pipeline.yaml
│   └── parallel-pipeline.yaml
└── expected/
    ├── linear-pipeline.plan.json
    └── nested-pipeline.plan.json
```

## CI Integration

```yaml
# .github/workflows/test.yml (conceptual)
test:
  - run: ./scripts/run.sh --no-lock test unit
  - run: ./scripts/run.sh --no-lock test integration
  - run: ./scripts/run.sh --no-lock test fixtures
```

