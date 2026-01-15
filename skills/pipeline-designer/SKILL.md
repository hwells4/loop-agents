---
name: pipeline-designer
description: Transform user intent into validated pipeline architectures. Use when user wants to build a NEW pipeline or learn about the pipeline system.
---

## What This Skill Does

Transforms vague intent ("I want to review code until it's elegant") into a concrete, validated architecture recommendation that pipeline-creator can build.

**Philosophy:** Trust your instincts. Use your intelligence. This is not a checklist task.

## Natural Skill Detection

Trigger on:
- "I want to build a pipeline that..."
- "Create a loop/pipeline for..."
- "How should I structure an iterative workflow for..."
- "What termination strategies are available?"
- "How do pipelines work?"

## Intake

Use AskUserQuestion to route the request:

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Intent",
    "options": [
      {"label": "Build a Pipeline", "description": "Create something new - I'll help you design it"},
      {"label": "Ask Questions", "description": "Learn about the pipeline system"}
    ],
    "multiSelect": false
  }]
}
```

## Routing

| Response | Workflow |
|----------|----------|
| "Build a Pipeline" | `workflows/build.md` |
| "Ask Questions" | `workflows/questions.md` |

## Build Workflow Summary

The core workflow for designing new pipelines:

```
Step 1: UNDERSTANDING (Agent Autonomy)
├─ Converse with user
├─ Ask questions if needed (use AskUserQuestion)
├─ Infer when intent is clear
└─ Proceed when you genuinely understand

Step 2: ARCHITECTURE AGENT (Mandatory Subagent)
├─ Receives: Requirements summary
└─ Returns: Architecture recommendation in YAML

Step 3: VALIDATE & CONFIRM
├─ Review architecture
├─ Present to user
└─ Get yes/no confirmation

Step 4: LINT & DRY-RUN (Mandatory)
├─ Run: ./scripts/run.sh lint pipeline {name}
├─ Run: ./scripts/run.sh dry-run pipeline {name} preview
├─ Fix any errors before proceeding
└─ Show user the validated output

OUTPUT: Confirmed, validated architecture spec
```

**CRITICAL:** Cannot proceed to confirmation without spawning the `pipeline-architect` subagent. Defined in `agents/pipeline-architect.md`.

## Understanding Phase

Read `workflows/build.md` for full details. Key principle:

> This is not a checklist task. You have full latitude to explore and understand what the user wants. Trust your instincts. Follow the conversation where it leads. Use your intelligence to intuit what the user is trying to accomplish.

**The goal:** Develop a clear mental model of:
- What problem they're solving
- What each iteration should accomplish
- When the work should stop
- What outputs matter

**When to proceed:** When you genuinely understand—not when you've asked N questions.

## Output Format

The designer produces a confirmed spec saved to `.claude/pipeline-specs/{name}.yaml`:

```yaml
name: pipeline-name
confirmed_at: 2026-01-12T10:00:00Z

# Optional: commands passed to all stages
commands:
  test: "npm test"
  lint: "npm run lint"
  types: "npm run typecheck"

stages:
  - name: stage-name
    description: What this stage does
    exists: true | false
    termination:
      type: queue | judgment | fixed
      min_iterations: N
      consensus: N
      max_iterations: N
    provider: claude | codex
    model: opus | sonnet | haiku | gpt-5.2-codex | gpt-5.1-codex-max | gpt-5.1-codex-mini
    context: |
      Optional instructions injected into prompt as ${CONTEXT}
    inputs:
      from_initial: true         # Pass CLI --input files
      from_stage: plan           # Outputs from named stage

  # Parallel block: run multiple providers concurrently
  - name: dual-review
    parallel:
      providers: [claude, codex]
      stages:
        - name: analyze
          stage: code-review
          termination:
            type: fixed
            iterations: 1

  # Post-parallel stage: consume parallel outputs
  - name: synthesize
    stage: elegance
    inputs:
      from_parallel: analyze     # Gets outputs from all parallel providers

rationale: |
  Why this architecture fits the use case.
```

### Provider/Model Options

| Provider | Models | Best For |
|----------|--------|----------|
| **claude** | opus, sonnet, haiku | General coding, nuanced judgment |
| **codex** | gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.1-codex-mini | Code generation, agentic tasks |

### Codex Reasoning Effort

Codex supports `model_reasoning_effort` to control thinking depth:

| Level | Use Case | Latency |
|-------|----------|---------|
| `minimal` | Simple tasks | Fastest |
| `low` | Straightforward code | Fast |
| `medium` | **Recommended daily driver** | Balanced |
| `high` | Complex tasks (default) | Slower |
| `xhigh` | Maximum reasoning | Slowest |

Set via environment variable:
```bash
CODEX_REASONING_EFFORT=medium ./scripts/run.sh my-stage session 10 --provider=codex
```

**Guidance:**
- `medium` is the recommended daily driver for most tasks
- `high` is good for complex single iterations
- **`xhigh` should be reserved for 1-2 iteration tasks** (e.g., plan synthesis, task creation) where deep reasoning matters. Never use xhigh for 5+ iteration loops—the cost/latency adds up fast.

## Handoff to Pipeline Creator

On user confirmation:
1. Save spec to `.claude/pipeline-specs/{name}.yaml`
2. Automatically invoke pipeline-creator skill with the spec path
3. Pipeline-creator handles all file creation

If via `/pipeline` command, this handoff is automatic.

## Quick Reference

```bash
# List existing stages
ls scripts/stages/

# List existing pipelines
ls scripts/pipelines/*.yaml

# Check V3 system docs
cat scripts/lib/context.sh  # Context generation
cat scripts/lib/status.sh   # Status validation
```

## Subagents

This skill uses the `pipeline-architect` subagent defined in `agents/pipeline-architect.md`.

Invoke via Task tool:
```
Task(
  subagent_type="pipeline-architect",
  description="Design pipeline architecture",
  prompt="REQUIREMENTS SUMMARY:\n{summary}\n\nEXISTING STAGES:\n{stages}"
)
```

## References Index

| Reference | Purpose |
|-----------|---------|
| references/v3-system.md | V3 template variables and formats |
| references/termination.md | Termination strategy decision guide |

## Workflows Index

| Workflow | Purpose |
|----------|---------|
| build.md | Design new pipeline architecture |
| questions.md | Answer questions about the system |

## Success Criteria

- [ ] Intent correctly routed (build/edit/questions)
- [ ] For build: understanding phase gave agent genuine autonomy
- [ ] For build: architecture agent spawned (mandatory)
- [ ] Architecture presented clearly to user
- [ ] User gave explicit yes/no confirmation
- [ ] On yes: lint passed (no errors)
- [ ] On yes: dry-run shows correct config
- [ ] On yes: spec saved and pipeline-creator invoked
