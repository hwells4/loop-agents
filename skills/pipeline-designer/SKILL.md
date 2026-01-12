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

OUTPUT: Confirmed architecture spec
```

**CRITICAL:** Cannot proceed to confirmation without spawning the `pipeline-architect` subagent. Defined at `.claude/agents/pipeline-architect.md`.

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
    model: opus | sonnet | haiku | gpt-5.2-codex
    inputs: [stage-names]

rationale: |
  Why this architecture fits the use case.
```

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

This skill uses the `pipeline-architect` subagent defined at `.claude/agents/pipeline-architect.md`.

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
- [ ] On yes: spec saved and pipeline-creator invoked
