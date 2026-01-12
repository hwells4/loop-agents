# Loop Architecture v3: Unified Stage Model

## What This Document Is

This is the refined architecture plan for Agent Pipelines. It builds on v2 and incorporates the best ideas from the elegance review, while keeping what works.

**Goal:** Make the system so standardized that agents can create new pipelines without making mistakes, and humans can understand any stage definition at a glance.

---

## The Core Idea (Unchanged)

Agent Pipelines solves context degradation by spawning fresh Claude instances for each iteration. Each agent reads a progress file with accumulated learnings, does work, and appends what it learned.

```
┌─────────────────────────────────────────────────────────────┐
│  Each iteration = Fresh Claude                              │
│                                                             │
│  Iteration 1 → reads progress → works → appends findings    │
│  Iteration 2 → reads progress → works → appends findings    │
│  Iteration 3 → reads progress → works → appends findings    │
│                                                             │
│  Progress file grows with curated context, not raw chat     │
└─────────────────────────────────────────────────────────────┘
```

---

## Changes from v2 (Plain English)

### Change 1: One Context File Instead of Many Variables

**The problem:** v2 has 9+ template variables agents need to learn:
- `${SESSION}`, `${ITERATION}`, `${STAGE_DIR}`, `${PROGRESS}`, `${OUTPUT}`, `${STATUS}`
- `${PREVIOUS_OUTPUT_FILES}`, `${INPUT_FILES}`, `${INPUT_FILES.name}`, `${ITEM}`

That's a lot to remember. Agents (and humans) forget which one to use.

**The fix:** One JSON file called `context.json` that contains everything.

```
# Before: Agent prompt needs to know many variables
Session: ${SESSION}
Iteration: ${ITERATION}
Progress: ${PROGRESS_FILE}
Previous outputs: ${PREVIOUS_OUTPUT_FILES}

# After: Agent reads one file
Context: ${CTX}  → points to context.json which has everything
```

The `context.json` looks like:
```json
{
  "session": "auth",
  "iteration": 3,
  "stage": { "name": "improve-plan", "index": 1 },
  "paths": {
    "progress": ".claude/pipeline-runs/auth/stage-01-improve-plan/progress.md",
    "output": ".claude/pipeline-runs/auth/stage-01-improve-plan/output.md",
    "status": ".claude/pipeline-runs/auth/stage-01-improve-plan/iterations/003/status.json"
  },
  "inputs": {
    "from_previous_stage": ["stage-00-init/output.md"],
    "from_previous_iterations": ["iterations/001/output.md", "iterations/002/output.md"]
  }
}
```

**Why it's better:**
- **Reliability:** One source of truth. No confusion about which variable has what.
- **Readability:** Open `context.json` and see everything the agent knows.
- **Validation:** Easy to check if context.json is well-formed before agent runs.

We keep 4 simple path variables for convenience:
- `${CTX}` → path to context.json
- `${PROGRESS}` → path to progress file
- `${OUTPUT}` → path to write output
- `${STATUS}` → path to write status

---

### Change 2: Universal Status Format

**The problem:** v2 lets each stage define its own "am I done?" field:
```yaml
# Stage A uses:
consensus_field: plateau

# Stage B might use:
consensus_field: complete

# Stage C might use:
consensus_field: finished
```

Agents have to remember which field each stage uses. Prompts vary. Validation is hard.

**The fix:** Every agent writes the exact same status format:

```json
{
  "decision": "continue",
  "reason": "Found 3 issues, still working on fixes",
  "summary": "One paragraph of what happened this iteration",
  "work": {
    "items_completed": [],
    "files_touched": ["src/auth.ts"]
  },
  "errors": []
}
```

The `decision` field is always one of:
- `"continue"` → keep going
- `"stop"` → I think we're done
- `"error"` → something went wrong

**Why it's better:**
- **Reliability:** Every prompt uses identical instructions. No variation.
- **Readability:** Look at any status.json and immediately understand it.
- **Validation:** Check `decision` is valid enum. Done.

Judgment termination becomes: "2 consecutive iterations wrote `decision: stop`"

No more `consensus_field` configuration. No more stage-specific naming.

---

### Change 3: Engine Handles Output History

**The problem:** v2 makes every stage define how outputs are saved:
```yaml
output:
  mode: single        # Overwrite each iteration
  # or
  mode: per-iteration # Save each iteration separately
```

This leaks an implementation detail into every stage definition. Agents building stages have to decide this upfront.

**The fix:** Agent always writes to `${OUTPUT}`. Engine automatically saves history.

```
Agent writes to: output.md (same path every iteration)
Engine saves to: iterations/001/output.md, iterations/002/output.md, etc.
```

The stage config only says WHERE the output goes, not HOW it's versioned:
```yaml
output: docs/plan-${SESSION}.md   # Tracked in repo
# or
output: .claude                    # Internal only
```

**Why it's better:**
- **Reliability:** Agent can't misconfigure output mode. Engine handles it.
- **Readability:** Stage config is simpler. One line instead of a block.
- **Both patterns work:** "Refine in place" and "accumulate alternatives" just work.

---

### Change 4: Keep Progress File (With Better Contract)

**Your concern was valid.** Agents need to learn from each other. If we replace progress with a "handoff" that gets overwritten, mistakes from 3 iterations ago get forgotten.

**The decision:** Keep the append-only progress file exactly as designed.

```markdown
## Iteration 1
- Reviewed auth module, found 3 issues
- Fixed rate limiting bug
- TODO: Session expiry still needs work

## Iteration 2
- Addressed session expiry
- Found new issue: token refresh logic is wrong
- TODO: Fix token refresh

## Iteration 3
- Fixed token refresh
- All tests passing
- Ready for review
```

Every entry preserved. Next agent reads everything. Mistakes don't repeat.

**The contract (enforced by prompts):**
1. Read the entire progress file
2. Append a concise section for your iteration
3. Keep entries tight (3-5 bullet points)
4. Call out unresolved issues clearly

**Why bloat isn't a real problem:**
- Each iteration adds ~100-200 tokens when written concisely
- 50 iterations = ~10k tokens = small fraction of context window
- The value of not repeating mistakes far outweighs the cost

---

### Change 5: Explicit Input Selection

**The problem:** v2 has `${INPUT_FILES}` which implicitly means "all outputs from previous stage."

For a synthesis stage that needs 5 idea files, that's right.
For a refinement stage that only needs the latest version, that's wrong (it gets 5 files when it needs 1).

**The fix:** Stages explicitly say what they want:

```yaml
# In pipeline.yaml
stages:
  - id: ideas
    template: idea-generator
    max_iterations: 5

  - id: synthesize
    template: synthesizer
    inputs:
      from: ideas
      select: all        # Get all 5 idea files

  - id: refine
    template: refiner
    inputs:
      from: synthesize
      select: latest     # Get only the most recent output
```

**Why it's better:**
- **Reliability:** No accidental context bloat from getting files you don't need.
- **Readability:** Pipeline config shows exactly what flows where.
- **Explicit > Implicit:** You know what you're getting.

Default is `select: latest` because that's correct most of the time.

---

### Change 6: Fail Fast, Resume Smart

**The problem:** v2 has `max_failures: 3` with retry logic. But if Claude Code is failing, something is fundamentally wrong. Retrying blindly doesn't help.

**The fix:** Fail immediately. Write clear state. Let an agent investigate and resume.

```yaml
# No failure counters. Just guardrails for runaway sessions.
guardrails:
  max_iterations: 50
  max_runtime_seconds: 7200
```

When something fails:
1. Engine writes failure state to `state.json` with error details
2. Session stops immediately
3. Next time an agent checks sessions, it sees the failure
4. Agent can investigate (read logs, check state) and resume when ready

**Why it's better:**
- **Simpler:** No retry logic, no failure counters, no complexity.
- **Debuggable:** Agent investigates the actual problem instead of blindly retrying.
- **Resume is built in:** `./scripts/run.sh work auth 25 --resume` picks up where it left off.

The failure state looks like:
```json
{
  "status": "failed",
  "iteration": 5,
  "error": {
    "type": "agent_crash",
    "message": "Claude process exited with code 1",
    "timestamp": "2025-01-10T10:05:00Z"
  },
  "resume_from": 5
}
```

An agent reading this knows exactly what happened and can decide whether to resume or investigate first.

---

### Change 7: Configurable Consensus Count

**The problem:** v2 hardcodes "2 consecutive agents must agree" in documentation but not in schema.

**The fix:** Make it explicit in the config:

```yaml
termination:
  type: judgment
  min_iterations: 2
  consensus: 2        # How many consecutive "stop" decisions needed
```

**Why it's better:**
- **Reliability:** Schema matches documentation. No ambiguity.
- **Readability:** See the consensus requirement in the config.
- **Flexibility:** Some stages might need 3 agents to agree for critical decisions.

---

## Complete Schema (v3)

### stage.yaml

```yaml
# Identity
name: improve-plan
description: Iteratively improve a plan document
tags: [refinement, planning]    # Metadata only, doesn't affect execution

# Prompt
prompt: prompt.md               # Template file

# Termination
termination:
  type: judgment                # judgment | queue | fixed
  min_iterations: 2             # Start checking after this many
  consensus: 2                  # Consecutive "stop" decisions needed

# Output
output: docs/plan-${SESSION}.md # Where primary artifact goes
                                # Or: .claude (internal, default)

# Guardrails (safety limits for runaway sessions)
guardrails:
  max_iterations: 50            # Hard stop, default 100
  max_runtime_seconds: 7200     # 2 hour timeout, default 7200
  # No failure counters - fail fast, resume smart

# Optional
verify: []                      # Commands to run after each iteration
delay: 3                        # Seconds between iterations
model: opus                     # Override model for this stage
```

### pipeline.yaml

```yaml
name: full-ideation
description: Generate ideas, synthesize, refine

# Pipeline-level guardrails
guardrails:
  max_runtime_seconds: 14400    # 4 hours total

stages:
  # Stage 1: Generate ideas (fixed iterations)
  - id: ideas
    template: idea-generator
    max_iterations: 5
    # inputs: not needed for first stage

  # Stage 2: Synthesize all ideas into one document
  - id: synthesize
    template: synthesizer
    max_iterations: 1
    inputs:
      from: ideas
      select: all               # Get all idea files
    output: docs/plan-${SESSION}.md

  # Stage 3: Refine until consensus
  - id: refine
    template: refiner
    max_iterations: 10
    inputs:
      from: synthesize
      select: latest            # Only need the latest version
    output: docs/plan-${SESSION}.md
    verify:
      - markdownlint ${OUTPUT}
```

### context.json (Engine-Generated)

This is what the engine creates for each iteration. Agent reads it via `${CTX}`.

```json
{
  "session": "auth",
  "pipeline": "full-ideation",
  "stage": {
    "id": "refine",
    "index": 2,
    "template": "refiner"
  },
  "iteration": 3,
  "paths": {
    "session_dir": ".claude/pipeline-runs/auth",
    "stage_dir": ".claude/pipeline-runs/auth/stage-02-refine",
    "progress": ".claude/pipeline-runs/auth/stage-02-refine/progress.md",
    "output": "docs/plan-auth.md",
    "status": ".claude/pipeline-runs/auth/stage-02-refine/iterations/003/status.json"
  },
  "inputs": {
    "from_stage": {
      "synthesize": ["stage-01-synthesize/output.md"]
    },
    "from_previous_iterations": [
      "iterations/001/output.md",
      "iterations/002/output.md"
    ]
  },
  "limits": {
    "max_iterations": 10,
    "remaining_seconds": 3200
  }
}
```

### status.json (Agent-Written)

Every agent writes this exact format. No variation.

```json
{
  "decision": "continue",
  "reason": "Improved clarity in section 3, but section 5 still needs work",
  "summary": "Rewrote the authentication flow section. Added sequence diagram. Fixed terminology inconsistencies. Section 5 (error handling) is still vague.",
  "work": {
    "items_completed": [],
    "files_touched": ["docs/plan-auth.md"]
  },
  "verify": {
    "ran": true,
    "passed": true
  },
  "errors": []
}
```

---

## Directory Structure (v3)

```
.claude/pipeline-runs/{session}/
  state.json                              # Pipeline state (for engine)
  stage-01-{id}/
    progress.md                           # Append-only learnings
    output.md                             # Current output (or symlink to tracked)
    iterations/
      001/
        context.json                      # What agent received
        status.json                       # What agent reported
        output.md                         # Snapshot of output after this iteration
        verify.log                        # Optional: verify command output
      002/
        ...
  stage-02-{id}/
    ...
```

**Key points:**
- Always stage directories, even for single-stage pipelines
- Iterations subdirectory captures history automatically
- Each iteration has its context and status preserved for debugging

---

## Termination Types

| Type | When It Stops | Use Case |
|------|---------------|----------|
| `queue` | External queue empty (beads) | Work stages, task processing |
| `judgment` | N consecutive agents say `decision: stop` | Refinement, improvement |
| `fixed` | Exactly N iterations complete | Ideation, exploration |

---

## Summary: What Changed from v2 to v3

| Aspect | v2 | v3 | Why Better |
|--------|----|----|------------|
| Variables | 9+ template vars | 1 context.json + 4 paths | One interface to learn |
| Status | Stage-specific `consensus_field` | Universal `decision` enum | No variation |
| Output mode | `mode: single \| per-iteration` | Engine handles automatically | Less config |
| Progress | Append-only | Append-only (kept as-is) | Learning preserved |
| Inputs | Implicit "all" | Explicit `select: latest \| all` | No surprises |
| Failures | Retry with `max_failures` | Fail fast, resume smart | Simpler, debuggable |
| Consensus | Hardcoded "2" | Configurable in schema | Explicit |

---

## Implementation Phases

### Phase 1: Context Manifest
1. Create `context.json` generator in engine
2. Update prompts to read from `${CTX}`
3. Keep old variables working as fallback during migration

### Phase 2: Universal Status
4. Define status.json schema
5. Update all prompts to write standard format
6. Update termination checks to read `decision` field

### Phase 3: Engine-Side Snapshots
7. Always save iteration outputs to `iterations/NNN/output.md`
8. Remove `output.mode` from schema
9. Stage config only specifies final output path

### Phase 4: Input Selection
10. Add `inputs.from` and `inputs.select` to pipeline schema
11. Update engine to filter inputs accordingly
12. Default to `select: latest`

### Phase 5: Fail Fast
13. Remove retry logic from engine
14. Write clear failure state with error details
15. Ensure resume reads failure state and picks up correctly

### Phase 6: Cleanup
16. Remove deprecated variables from resolve.sh
17. Update all existing stages to new schema
18. Update CLAUDE.md and skill documentation

---

## Success Criteria

1. **One context interface** - Agents read `context.json`, not multiple variables
2. **One status format** - Every agent writes identical `status.json`
3. **Automatic history** - Engine saves iteration outputs without stage config
4. **Preserved learning** - Progress file keeps all entries
5. **Explicit inputs** - Stages declare what inputs they want
6. **Fail fast, resume smart** - Failures stop immediately with clear state for debugging
7. **Schema = documentation** - No implicit behaviors; everything in config
