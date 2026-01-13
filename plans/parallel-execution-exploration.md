# Parallel Execution in Agent Pipelines: Design Exploration

## Problem Statement

We want to run AI providers (Claude, Codex, Gemini) in parallel within pipelines. The goal is to get multiple perspectives, compare approaches, or let providers fully develop solutions independently before synthesizing results.

**Core tension:** Parallel agents can't see each other during execution, so they can't coordinate or reach consensus. Any synthesis must happen in a subsequent sequential stage.

---

## Use Cases

### Use Case 1: Simple Comparison
Run the same prompt on multiple providers, compare outputs.
```
Stage 1: Run "brainstorm" on Claude + Codex (parallel)
Stage 2: Claude synthesizes both outputs
```

### Use Case 2: Independent Evolution
Each provider develops its own solution through multiple iterations, then merge.
```
Stage 1: Plan prompt on Claude + Codex (parallel)
Stage 2: Each provider iterates on ITS OWN plan 5x with plateau (parallel)
Stage 3: Claude receives both final plans, synthesizes best approach
```

### Use Case 3: Complex Multi-Phase Pipeline
The user's concrete goal:
```
Stage 1: Planning prompt - Claude + Codex (parallel, 1 iteration each)
Stage 2: Iteration loop - Each provider refines its own plan (parallel, 5 iterations, plateau)
Stage 3: Elegance synthesis - Claude receives both, creates unified plan (2 iterations, plateau)
Stage 4: Refine beads - Claude refines tasks (8 iterations, plateau)
Stage 5: Work loop - Claude implements until queue empty
```

### Use Case 4: Repeated Pipeline Execution
Run an entire pipeline multiple times as a unit:
```
Pipeline "bug-cycle": code-review → elegant-fix → implement
Meta-pipeline: Run bug-cycle 5 times
```

### Use Case 5: Parallel in the Middle
Sequential start, parallel middle, sequential end:
```
Stage 1: Initial analysis (single provider)
Stage 2: Deep dive - Claude + Codex explore different aspects (parallel)
Stage 3: Synthesis (single provider)
Stage 4: Implementation (single provider)
```

---

## Design Approaches

### Approach A: Stage-Level `providers:` (Comparison Mode)

**Concept:** A stage can specify multiple providers. All run the same iteration in parallel.

```yaml
stages:
  - name: brainstorm
    providers: [claude, codex]
    termination:
      type: fixed
      iterations: 3
```

**Execution:**
- Iteration 1: Claude runs, Codex runs (parallel)
- Iteration 2: Claude runs, Codex runs (parallel)
- Iteration 3: Claude runs, Codex runs (parallel)
- Each iteration waits for all providers before continuing

**Directory structure:**
```
stage-00-brainstorm/
└── iterations/
    ├── 001/
    │   ├── claude/output.md
    │   └── codex/output.md
    ├── 002/
    │   ├── claude/output.md
    │   └── codex/output.md
    └── 003/
        ├── claude/output.md
        └── codex/output.md
```

**Limitations:**
- Fixed termination only (who judges plateau when agents can't see each other?)
- All providers share iteration count
- Each provider sees combined outputs from previous iteration (or just its own?)

**Solves:** Use Case 1

**Does NOT solve:** Use Cases 2, 3 (need independent iteration counts)

---

### Approach B: Stage-Level `providers:` with `independent: true`

**Concept:** Each provider runs its own iteration loop independently within the stage.

```yaml
stages:
  - name: iterate
    providers: [claude, codex]
    termination:
      type: judgment
      consensus: 2
      max: 5
      independent: true  # Each provider runs its own loop
```

**Execution:**
- Claude spawns, runs iterations 1→2→3 (plateaus)
- Codex spawns, runs iterations 1→2→3→4→5 (hits max)
- Stage completes when ALL providers finish
- Next stage receives both final outputs

**Directory structure:**
```
stage-00-iterate/
├── claude/
│   ├── state.json
│   └── iterations/001/, 002/, 003/
└── codex/
    ├── state.json
    └── iterations/001/, 002/, 003/, 004/, 005/
```

**Problem:** Multi-stage dependencies get complicated.

```yaml
stages:
  - name: plan
    providers: [claude, codex]
    termination: { type: fixed, iterations: 1, independent: true }

  - name: iterate
    providers: [claude, codex]
    termination: { type: judgment, consensus: 2, max: 5, independent: true }
    inputs:
      from: plan  # Which plan? Claude's iterate needs Claude's plan...
```

The `inputs` become ambiguous. Need implicit routing: "Claude's iterate gets Claude's plan output."

**Solves:** Use Cases 1, 2 (with implicit routing)

**Complexity:** Medium. Implicit routing rules feel magical.

---

### Approach C: Pipeline-Level `providers:`

**Concept:** Run the entire pipeline independently per provider. Cleaner than stage-level for multi-stage parallel work.

```yaml
name: parallel-refine
providers: [claude, codex]

stages:
  - name: plan
    termination: { type: fixed, iterations: 1 }
  - name: iterate
    termination: { type: judgment, consensus: 2, max: 5 }

synthesis:
  - name: compare
    provider: claude
```

**Execution:**
- Claude runs: plan → iterate (plateaus at 3)
- Codex runs: plan → iterate (plateaus at 5)
- Both complete
- Synthesis runs: compare stage receives both outputs

**Directory structure:**
```
pipeline-run/
├── providers/
│   ├── claude/
│   │   ├── stage-00-plan/
│   │   └── stage-01-iterate/
│   └── codex/
│       ├── stage-00-plan/
│       └── stage-01-iterate/
└── synthesis/
    └── stage-00-compare/
```

**Limitation:** Parallel must be at the start. Can't do sequential → parallel → sequential.

**Solves:** Use Cases 1, 2

**Does NOT solve:** Use Case 5 (parallel in the middle)

---

### Approach D: Pipeline-Level with `converge_at:`

**Concept:** Specify where parallel execution merges back to sequential.

```yaml
name: dual-refine
providers: [claude, codex]
converge_at: elegance  # Parallel until this stage

stages:
  - name: plan           # Parallel
  - name: iterate        # Parallel
  - name: elegance       # Convergence point, receives both outputs
    provider: claude
  - name: refine-beads   # Sequential
    provider: claude
  - name: work           # Sequential
    provider: claude
```

**Limitation:** Still assumes parallel at the start. What about parallel in the middle?

**Solves:** Use Case 3

**Does NOT solve:** Use Case 5

---

### Approach E: Explicit Parallel Blocks

**Concept:** Mark sections of the pipeline as parallel with explicit syntax.

```yaml
stages:
  - name: initial-analysis
    provider: claude

  - parallel:
      providers: [claude, codex]
      stages:
        - name: deep-dive
          termination: { type: judgment, consensus: 2, max: 5 }

  - name: synthesis
    provider: claude
    inputs:
      from: deep-dive  # Gets outputs from all providers

  - name: implement
    provider: claude
```

**Execution:**
```
initial-analysis (Claude)
        ↓
   ┌────┴────┐
   ↓         ↓
deep-dive  deep-dive
(Claude)   (Codex)
   ↓         ↓
   └────┬────┘
        ↓
   synthesis (Claude, sees both)
        ↓
   implement (Claude)
```

**Pros:**
- Parallel can be anywhere in the pipeline
- Explicit, no magic
- Clear scoping

**Cons:**
- More verbose syntax
- Nested structure in YAML

**Solves:** Use Cases 1, 2, 3, 5

---

### Approach F: Tracks (Original Plan)

**Concept:** Separate `tracks:` concept for independent iteration loops.

```yaml
stages:
  - name: planning
    tracks:
      - provider: claude
        loop: improve-plan
        termination: { type: judgment, consensus: 2, max: 5 }
      - provider: codex
        loop: improve-plan
        termination: { type: judgment, consensus: 2, max: 5 }
```

**Problems identified:**
- `loop:` reference is underspecified (what does it reference?)
- Two parallel concepts (`providers:` vs `tracks:`) with different semantics
- Verbose

**Recommendation:** Collapse into one concept (Approach B or E)

---

### Approach G: Nested Pipelines

**Concept:** Pipelines can reference other pipelines as units.

```yaml
# sub-pipeline: develop-plan.yaml
name: develop-plan
stages:
  - name: plan
    termination: { type: fixed, iterations: 1 }
  - name: iterate
    termination: { type: judgment, consensus: 2, max: 5 }
```

```yaml
# meta-pipeline: parallel-develop.yaml
name: parallel-develop

parallel:
  - pipeline: develop-plan.yaml
    provider: claude
  - pipeline: develop-plan.yaml
    provider: codex

stages:
  - name: synthesize
    provider: claude
    inputs:
      from_parallel: true
```

**Pros:**
- Maximum composability
- Pipelines are reusable units
- Can run different pipelines in parallel (not just same pipeline on different providers)

**Cons:**
- Most complex to implement
- Need to manage nested state
- Recursive depth concerns

**Solves:** All use cases, including Use Case 4 (repeated pipeline execution)

---

### Approach H: Hooks as Composition

**Concept:** Don't build nested pipelines into the schema. Use hooks to invoke sub-pipelines.

```yaml
stages:
  - name: parallel-develop
    hook: ./hooks/run-parallel-pipelines.sh
    # Hook spawns: ./scripts/run.sh pipeline develop-plan.yaml --provider claude &
    #              ./scripts/run.sh pipeline develop-plan.yaml --provider codex &
    # Waits, collects outputs, writes to stage output
```

**Pros:**
- No schema changes needed
- Maximum flexibility
- Hooks are already planned

**Cons:**
- Less declarative
- Error handling in hooks is harder
- User has to write shell scripts

**Solves:** All use cases (with effort)

---

## Comparison Matrix

| Approach | Use Case 1 | Use Case 2 | Use Case 3 | Use Case 4 | Use Case 5 | Complexity |
|----------|------------|------------|------------|------------|------------|------------|
| A: Stage `providers:` | ✅ | ❌ | ❌ | ❌ | ❌ | Low |
| B: Stage `providers:` + `independent` | ✅ | ⚠️ | ⚠️ | ❌ | ⚠️ | Medium |
| C: Pipeline `providers:` | ✅ | ✅ | ❌ | ❌ | ❌ | Low |
| D: Pipeline + `converge_at:` | ✅ | ✅ | ✅ | ❌ | ❌ | Medium |
| E: Explicit `parallel:` blocks | ✅ | ✅ | ✅ | ❌ | ✅ | Medium |
| F: Tracks (original) | ✅ | ✅ | ⚠️ | ❌ | ⚠️ | High |
| G: Nested pipelines | ✅ | ✅ | ✅ | ✅ | ✅ | High |
| H: Hooks | ✅ | ✅ | ✅ | ✅ | ✅ | Medium* |

*Hooks are medium complexity to implement but require user effort to use.

---

## Design Principles to Choose By

### Principle 1: One Parallelism Primitive
Don't have `providers:`, `tracks:`, AND nested pipelines. Pick one and make it powerful.

### Principle 2: Explicit Over Implicit
If Claude's stage 2 needs Claude's stage 1 output (not Codex's), that should be explicit, not magic routing.

### Principle 3: Parallel Execution is for Comparison, Not Consensus
Agents running simultaneously can't coordinate. Synthesis always happens in a subsequent sequential stage.

### Principle 4: Composability is Valuable
Being able to run "this pipeline as a unit" enables powerful patterns.

### Principle 5: Start Simple, Extend Later
Ship the minimal feature that solves real problems. Add complexity when use cases demand it.

---

## Recommendation Tiers

### Tier 1: Ship Now (Solves 80% of cases)
**Approach E: Explicit `parallel:` blocks**

```yaml
stages:
  - name: setup
    provider: claude

  - parallel:
      providers: [claude, codex]
      stages:
        - name: plan
          termination: { type: fixed, iterations: 1 }
        - name: iterate
          termination: { type: judgment, consensus: 2, max: 5 }

  - name: synthesize
    provider: claude
    inputs:
      from_parallel: [plan, iterate]  # or just "from: iterate" for final outputs
```

**Why:**
- Parallel can be anywhere (start, middle, end)
- Explicit scoping (no magic)
- Single concept to understand
- Reasonable implementation complexity (~100 lines)

### Tier 2: Add Later (If Use Case 4 proves real)
**Approach G: Nested pipelines**

Only if users actually need to run "pipeline X as a repeatable unit multiple times."

### Tier 3: Available Now (Escape hatch)
**Approach H: Hooks**

Users who need maximum flexibility can write hooks today without waiting for schema features.

---

## Open Questions

1. **Input routing in parallel blocks:** When a parallel block has multiple stages, does stage 2 see stage 1's output from the same provider only, or all providers?
   - **Proposal:** Same provider only. Cross-provider visibility only happens at synthesis.

2. **Failure handling:** If one provider fails mid-parallel, do we:
   - Fail the whole parallel block?
   - Let other providers continue and report partial results?
   - **Proposal v1:** Fail the whole block. Add `fail_policy` later if needed.

3. **Progress files in parallel:** Each provider needs its own progress file, or shared?
   - **Proposal:** Each provider gets isolated progress file within its directory.

4. **Termination in parallel blocks:** Can different stages within a parallel block have different termination types?
   - **Proposal:** Yes. Each stage in the block has its own termination config.

5. **Nested parallel blocks:** Can you have `parallel:` inside `parallel:`?
   - **Proposal v1:** No. Single level of parallelism only.

---

## Next Steps

1. **Decide on approach** - Recommend Approach E (explicit parallel blocks)
2. **Write detailed implementation spec** for chosen approach
3. **Implement** in ~100-150 lines of bash
4. **Test** with user's concrete Use Case 3 pipeline
5. **Document** new schema in CLAUDE.md

---

## Appendix: User's Target Pipeline (Use Case 3)

With Approach E (explicit parallel blocks):

```yaml
name: dual-refine-and-implement
description: Compare Claude and Codex planning, synthesize, then implement

stages:
  - parallel:
      providers: [claude, codex]
      stages:
        - name: plan
          prompt: prompts/planning.md
          termination:
            type: fixed
            iterations: 1

        - name: iterate
          prompt: stages/improve-plan/prompt.md
          termination:
            type: judgment
            consensus: 2
            max: 5

  - name: elegance
    provider: claude
    prompt: stages/elegance/prompt.md
    inputs:
      from_parallel: iterate  # Gets both providers' final iterate outputs
    termination:
      type: judgment
      consensus: 2
      max: 2

  - name: refine-beads
    provider: claude
    prompt: stages/refine-beads/prompt.md
    termination:
      type: judgment
      consensus: 2
      max: 8

  - name: work
    provider: claude
    prompt: stages/work/prompt.md
    termination:
      type: queue
```

**Execution timeline:**
```
┌─────────────────────────────────────────────────────────────┐
│  parallel: providers: [claude, codex]                       │
│                                                             │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  Claude          │         │  Codex           │         │
│  │  plan (1x)       │         │  plan (1x)       │         │
│  │      ↓           │         │      ↓           │         │
│  │  iterate (3x)    │         │  iterate (5x)    │         │
│  │  [plateaued]     │         │  [hit max]       │         │
│  └──────────────────┘         └──────────────────┘         │
│                                                             │
│  Wait for all providers to complete...                      │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  elegance (Claude, 2x plateau)                              │
│  - Sees: Claude's iterate output + Codex's iterate output   │
│  - Synthesizes best approach                                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  refine-beads (Claude, 8x plateau)                          │
│  - Creates/refines implementation tasks                     │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  work (Claude, until queue empty)                           │
│  - Implements all tasks                                     │
└─────────────────────────────────────────────────────────────┘
```
