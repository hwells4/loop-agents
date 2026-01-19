# Robot-Mode Gap Analysis: Go Engine PRD vs Agent Needs

This document compares the agent's recommendations from `.claude/pipeline-runs/go-engine-robot/robot-mode-recommendations.md` against the Go Engine PRD at `docs/plans/2026-01-15-go-engine-rewrite-prd.md`.

---

## Already Covered

| Recommendation | Where in PRD |
|----------------|--------------|
| **Basic context.json structure** (session, iteration, paths, inputs, limits) | Feature 4.2 Input System Parity, Context Schema v3 (lines 1066-1091) |
| **Template variables** (`${CTX}`, `${PROGRESS}`, `${STATUS}`, etc.) | Feature 1.2 Stage Execution Parity (line 85) |
| **`from_previous_iterations` in inputs** | Feature 4.2 explicitly adds this (lines 379-382) |
| **Parallel scope context** (`parallel_scope.scope_root`, `pipeline_root`) | Feature 4.3 Parallel Scope Isolation (lines 465-474) |
| **Commands passthrough** (`commands:` in context.json) | Feature 1.1 (line 79), Feature 4.1 CLI (line 369), Context Schema includes `commands` |
| **Agent-initiated pause** (`decision: pause`) | Feature 6.4 Pause and Resume, Hook system supports this pattern |
| **JSON output for CLI commands** | Implied but not explicit (`--json` flag not mentioned in PRD) |
| **Session locking** | Feature 2.3 Session Locking (lines 263-275) |
| **Crash recovery/resume** | Feature 2.5 Event Reconciliation (lines 287-296) |
| **Error recovery info in context** | Error Taxonomy and Retry Configuration (lines 1261-1309) includes attempt tracking |
| **Result schema** (v3 unified format) | Result Schema v3 (lines 1172-1192), Result Normalization (lines 1194-1239) |
| **Health scoring** | Feature 5.3 Health Scoring (lines 493-502) - computes score, label, consecutive errors |
| **Provider capabilities** | Provider interface includes `Capabilities()` method (lines 735-740) |
| **Hooks system** | Feature 6.1-6.4 comprehensive hook system (lines 503-686) |
| **Multi-stage position** (`stage.index`, `stage.id`) | Context Schema includes `stage: {id, index, template}` (line 1069) |
| **Iteration limits** | Context includes `limits: {max_iterations, remaining_seconds}` (line 1085) |

---

## Gaps to Address

| Recommendation | Why It Matters | Suggested PRD Addition |
|----------------|----------------|------------------------|
| **1. `position.stage_count`** - Total number of stages in pipeline | Agent needs to know if it's in final stage to adjust behavior (wind down, summarize, etc.) | Add `stage.count` to context.json schema alongside existing `stage.index` |
| **2. `position.parallel.siblings`** - Other providers in parallel block | Agent needs to understand if output will be compared/merged, affects strategy | Add `parallel.siblings[]` array with provider names to context when in parallel block |
| **3. `previous_iteration.summary`** - Pre-computed summary in context | Currently agent must parse progress file every iteration - huge token waste | Add `previous_iteration: {number, summary, plateau_suspected, files_touched, items_completed}` to context.json |
| **4. `hints.consecutive_stops`** - Consensus state for judgment termination | Critical for agent to know how many consecutive stops have occurred | Add `hints: {termination_type, consensus_required, consecutive_stops}` to context |
| **5. `capabilities.bd_available`** - Whether beads CLI is present | Prevents wasted attempts at `bd` commands that won't work | Add `capabilities: {bd_available, sandboxed, available_commands}` to context |
| **6. `--json` flag on ALL CLI commands** | Agent-to-agent orchestration requires machine-readable output | Explicitly require `--json` flag on `status`, `list`, `tail`, `lint` commands with JSON schema |
| **7. Work queue pre-computation** in context | Agent shouldn't need to shell out to `bd ready` every iteration | Add `work_queue: {source, total, completed, items[]}` to context for beads-enabled stages |
| **8. Verification results** in context | Engine could run tests/lint after iteration and report results | Add optional `verify:` stage config with results in context.json |
| **9. Budget tracking** | Long sessions may have token/cost limits agent should respect | Add `budget: {enabled, used, remaining, at_warning}` to context when configured |
| **10. `session_health` in context** - computed health metrics | Agent should adapt behavior when session is struggling | Expose health score/label in context.json (already computed in Feature 5.3) |
| **11. Semi-structured progress format** | Progress files are freeform markdown - hard to parse | Define optional `<!-- meta: {...} -->` HTML comment format for iteration blocks |
| **12. Token-efficient context mode** | Production runs may want minimal context to save tokens | Add `--context-mode compact` flag or `context.include/exclude` in stage.yaml |
| **13. Watchdog/timeout awareness** | Codex has timeout - agent should know when to checkpoint | Add `execution: {timeout_seconds, elapsed_seconds, should_checkpoint_soon}` |
| **14. Judge feedback in context** | Agent never sees judge's evaluation - could learn from it | Add `judge.last_evaluation: {decision, confidence, feedback, suggestions}` to context |
| **15. `template_vars` in context** - Self-documenting variable paths | Agent shouldn't need to remember/lookup variable names | Add `template_vars: {CTX, PROGRESS, STATUS, RESULT, ...}` to context.json |
| **16. Progress metrics/velocity** | Quantitative measure of productivity across iterations | Add `progress_metrics: {items_per_iteration, trending, predicted_completion}` |
| **17. Introspection CLI commands** | Agent needs to query system state during execution | Add `inspect`, `beads`, `health`, `touched-files` subcommands with `--json` |
| **18. Machine-readable prompt metadata** | Prompt frontmatter with success criteria, tool hints, termination guidance | Define optional YAML frontmatter spec for prompt.md files |

---

## Conflicts

| Agent Wants | PRD Says | Resolution |
|-------------|----------|------------|
| **Single canonical result schema** - Agent wants ONE file to write every time | PRD supports both `status.json` (v2) and `result.json` (v3) for backward compatibility | **Recommend deprecation path**: Document v3 as canonical, emit warning on v2, remove v2 support in v2.0. Agent should only write `result.json`. |
| **`decision` in result.json** - Agent wants decision field in unified schema | PRD keeps `decision` in status.json (v2), result.json (v3) doesn't have it | **Add optional `decision` field to result.json v3**. For fixed/queue termination it's ignored; for judgment it's a signal. This is the agent's *recommendation* to the engine. |
| **Pause without ending session** - Agent wants `decision: pause` | PRD's hook system allows pause but it's hook-initiated, not agent-initiated | **Add agent-initiated pause**: If agent writes `decision: pause` in result.json, engine treats it like a hook returning `Pause`. Add to Feature 6.4. |
| **Absolute paths everywhere** | PRD context.json uses relative paths in examples | **Clarify**: All paths in context.json MUST be absolute. Update schema examples. |
| **Pattern hints for parallel blocks** - debate, consensus, parallel-explore | PRD doesn't define collaboration patterns | **Defer to v2**: Pattern detection is complex. For v1, add `parallel.mode: string` to YAML that agents can read, but don't auto-detect. |

---

## Top 5 Changes to Make

### 1. Enhanced context.json with Previous Iteration Summary
**Impact: Massive token savings**

Add to context.json schema:
```json
{
  "previous_iteration": {
    "number": 2,
    "summary": "Refactored auth module, added tests",
    "plateau_suspected": false,
    "files_touched": ["src/auth.ts"],
    "items_completed": ["auth-001"]
  }
}
```

This prevents agents from parsing the progress file every iteration. The engine already reads `result.json` from the previous iteration - just copy the relevant fields into context.

**PRD Change:** Add to Context Schema (v3) section around line 1088.

---

### 2. Add `--json` Flag to All CLI Commands
**Impact: Enables agent-to-agent orchestration**

Every command that outputs human-readable text must also support `--json`:
- `agent-pipelines status <session> --json`
- `agent-pipelines list --json`
- `agent-pipelines tail <session> --json`
- `agent-pipelines lint <target> --json`

Define JSON schemas for each command's output.

**PRD Change:** Add new acceptance criteria to Feature 4.1 CLI Compatibility.

---

### 3. Expose Health and Hints in context.json
**Impact: Agents adapt behavior to session state**

Add to context.json:
```json
{
  "health": {
    "score": 0.85,
    "label": "ok",
    "consecutive_errors": 0,
    "plateau_iterations": 1
  },
  "hints": {
    "termination_type": "judgment",
    "consensus_required": 2,
    "consecutive_stops": 1
  }
}
```

Health is already computed (Feature 5.3). Just expose it in context. Hints tell the agent when to signal stop.

**PRD Change:** Expand Context Schema to include `health` and `hints` objects.

---

### 4. Add Agent-Initiated Pause via Result Decision
**Impact: Critical for safety and human-in-the-loop**

Allow agents to write `"decision": "pause"` in result.json:
```json
{
  "summary": "Found security vulnerability",
  "decision": "pause",
  "reason": "Human review required before proceeding",
  "requires_human": {
    "type": "security_review",
    "context": "See findings in output.md"
  }
}
```

Engine behavior:
1. Sees `decision: pause` in result.json
2. Sets `state.status = "paused"`
3. Releases lock
4. Emits `session_paused` event
5. Exits cleanly

Resume with `--resume --context "Approved"`.

**PRD Change:** Add to Feature 6.4 Pause and Resume, and update Result Schema v3.

---

### 5. Add Position Awareness with Stage Count and Parallel Context
**Impact: Agents know where they are in the workflow**

Add to context.json:
```json
{
  "position": {
    "stage": {
      "id": "improve-plan",
      "index": 1,
      "count": 3,
      "template": "improve-plan"
    },
    "run": {
      "index": 2,
      "count": 5
    },
    "iteration": {
      "current": 3,
      "max": 25
    },
    "parallel": {
      "enabled": true,
      "provider": "claude",
      "siblings": ["codex"],
      "block_id": "dual-refine"
    }
  }
}
```

This tells agents:
- How many stages exist (not just which one they're in)
- How many runs of this stage (for multi-run nodes)
- Who else is running in parallel

**PRD Change:** Replace flat stage/iteration fields in Context Schema with nested `position` object.

---

## Secondary Changes (Nice to Have)

| Change | Effort | Value |
|--------|--------|-------|
| Work queue pre-computation | Medium | High for beads users |
| Token-efficient context mode | Medium | High for production |
| Watchdog awareness in context | Low | Medium for Codex |
| Semi-structured progress format | Low | Medium |
| Judge feedback in context | Low | Medium |
| Introspection CLI commands | Medium | Medium |
| Machine-readable prompt frontmatter | Low | Medium |
| Progress metrics/velocity | Medium | Low |
| Budget tracking | Medium | Low |
| Verification command results | High | Low |

---

## Implementation Notes

### Backward Compatibility
All additions to context.json are additive. Existing agents that don't use new fields continue to work.

### Agent Bill of Rights Compliance
After these changes, the PRD will satisfy:
- [x] Right to Full Context
- [x] Right to Consistent Schemas
- [x] Right to Pause
- [x] Right to Machine-Readable Output
- [x] Right to Position Awareness
- [x] Right to Capability Discovery
- [x] Right to Health Visibility
- [ ] Right to Efficient Operation (partial - defer compact mode to v1.1)
- [x] Right to Recovery Information
- [ ] Right to Introspection (partial - defer some commands to v1.1)

### Testing Agent Experience
Add acceptance test: **Agent operates without documentation**
- Give agent only `context.json` and result.json schema
- Agent should be able to:
  - Understand iteration number and position
  - Know where to read/write files
  - Signal stop/continue appropriately
  - Understand termination context

---

*Analysis completed by Claude, reviewing what Claude needs from this system.*
