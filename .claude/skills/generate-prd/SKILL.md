---
name: prd
description: Generate PRDs through adaptive questioning. Use when user says "PRD", "spec", "plan a feature", "what should we build", or describes a project/feature they want to build. Works for both full project PRDs and feature-level specs.
context_budget:
  skill_md: 200
  max_references: 2
  sub_agent_limit: 300
---

## MANDATORY TOOL USAGE

**ALL clarifying questions MUST use the `AskUserQuestion` tool.**

Never output questions as text in your response. If you need information from the user, invoke `AskUserQuestion`. This is non-negotiable.

## What This Skill Produces

A technical spec that gives an AI coding agent enough context to:
1. Understand what we're building and why
2. Break it into Linear issues
3. Execute without coming back for clarification

This is NOT a traditional enterprise PRD for stakeholder alignment. It's a planning document for execution.

## Process

### 1. Receive Input

User describes what they want to build. Could be:
- A full project ("CRM with AI agents and 4 integrations")
- A feature ("Add Stripe billing to the app")
- A vague idea ("Something to track customer calls")

### 2. Gather Existing Context (Quick)

Before asking questions, quickly check for relevant context:
```
- brain/entities/ for client/stakeholder info
- brain/calls/ for relevant discussions
- Linear for related projects/issues
```

This takes 30 seconds, not a full discovery phase. Just grep for obvious matches.

### 3. Adaptive Questioning

**The core principle:** Keep asking questions until YOU are confident you can write a spec that an AI coding agent could use to build this without coming back for clarification.

That's the bar. Not a checklist.

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

**When to stop:** When you can confidently fill every section of the output template without guessing.

Some projects need 1 round. Some need 5. Use your judgment.

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

### 5. Save to Vault

```
brain/outputs/{YYYY-MM-DD}-{project-slug}-prd.md
```

Frontmatter:
```yaml
---
date: {YYYY-MM-DD}
type: prd
status: draft
tags:
  - output/prd
  - status/draft
---
```

## Success Criteria

- [ ] Used `AskUserQuestion` for ALL clarifying questions
- [ ] Stopped questioning when confident (not when checklist complete)
- [ ] All template sections filled without guessing
- [ ] Acceptance criteria are specific enough to test
- [ ] An AI coding agent could build from this without asking follow-ups

## What This Skill Does NOT Do

- Generate Linear issues (separate step)
- Validate business case or market fit
- Require stakeholder sign-off
- Follow a rigid 34-question framework

Keep it simple. The output is a planning document, not a legal contract.
