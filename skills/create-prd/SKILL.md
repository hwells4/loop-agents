---
name: create-prd
description: Generate PRDs through adaptive questioning. Use when user says "PRD", "spec", "plan a feature", "what should we build", or describes a project/feature they want to build.
---

## MANDATORY TOOL USAGE

**ALL clarifying questions MUST use the `AskUserQuestion` tool.**

Never output questions as text. If you need information, invoke `AskUserQuestion`.

## What This Skill Produces

A technical spec saved to `docs/plans/` that gives an AI coding agent enough context to:
1. Understand what we're building and why
2. Break it into beads
3. Execute without coming back for clarification

This is NOT a traditional enterprise PRD. It's a planning document for execution.

## Process

### 1. Receive Input

User describes what they want to build. Could be:
- A full project ("CRM with AI agents and 4 integrations")
- A feature ("Add Stripe billing to the app")
- A vague idea ("Something to track customer calls")

### 2. Gather Existing Context (Quick)

Before asking questions, quickly check for relevant context:
```bash
# Check for existing plans
ls docs/plans/*.md 2>/dev/null || echo "No existing plans"

# Check for project structure
ls -la src/ app/ lib/ 2>/dev/null | head -10
```

This takes 30 seconds, not a full discovery phase.

### 3. Adaptive Questioning

**The core principle:** Keep asking questions until YOU are confident you can write a spec that an AI coding agent could use to build this without coming back for clarification.

**How to ask:**
- Use `AskUserQuestion` with 2-4 questions per round
- Group related questions together
- Provide options where helpful (A/B/C format)
- Adapt based on answers—don't follow a script

**What you need to understand:**
- What does success look like?
- Who uses this and what do they do?
- What are the key capabilities?
- What are the technical constraints/integrations?
- What's explicitly OUT of scope?
- What could go wrong? (edge cases)

**When to stop:** When you can confidently fill every section without guessing.

### 4. Write the PRD

Use the structure in `references/template.md`.

Key sections:
- Overview (what + why)
- User Stories (who does what)
- Features (grouped logically, with acceptance criteria)
- Technical Approach (how it works, integrations)
- Test Strategy (what needs testing, key scenarios)
- Edge Cases (what could go wrong)
- Open Questions (unknowns to resolve)

### 5. Save to Project

Create the plans directory if needed and save:

```bash
mkdir -p docs/plans
```

Save to: `docs/plans/{YYYY-MM-DD}-{project-slug}-prd.md`

Frontmatter:
```yaml
---
date: {YYYY-MM-DD}
type: prd
status: draft
project: {project-slug}
---
```

### 6. Confirm Output

Tell the user:
```
✅ PRD saved to: docs/plans/{filename}

Next steps:
- Review and refine: /loop-agents:refine
- Generate tasks: /loop-agents:create-tasks
- Or run full workflow: /loop-agents:loop
```

## Success Criteria

- [ ] Used `AskUserQuestion` for ALL clarifying questions
- [ ] Stopped questioning when confident (not when checklist complete)
- [ ] All template sections filled without guessing
- [ ] Acceptance criteria are specific enough to test
- [ ] Saved to `docs/plans/` with correct frontmatter
- [ ] An AI coding agent could build from this without asking follow-ups
