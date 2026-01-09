---
name: create-tasks
description: Generate beads from a PRD for autonomous execution. Use when user says "generate tasks", "break this down", "create stories", or has a PRD they want to execute.
---

## MANDATORY TOOL USAGE

**ALL clarifying questions MUST use the `AskUserQuestion` tool.**

Never output questions as text. If you need information, invoke `AskUserQuestion`.

## What This Skill Produces

Beads tagged with `loop/{session-name}` that an agent can execute autonomously:

```bash
bd create --title="Story title" --type=task --priority=2 --add-label="loop/{session}"
```

## Process

### 1. Find the PRD

Check for PRDs in the project:
```bash
ls -la docs/plans/*.md 2>/dev/null || echo "No plans found"
```

If multiple exist, use `AskUserQuestion` to ask which one.

If no PRD exists, ask:
```yaml
question: "No PRD found. How would you like to proceed?"
header: "PRD"
options:
  - label: "Create a PRD first"
    description: "I'll help you write one"
  - label: "Describe the feature now"
    description: "I'll ask clarifying questions"
  - label: "Point me to a file"
    description: "I have a plan somewhere else"
```

If they choose to create a PRD, invoke `/loop-agents:prd`.

### 2. Analyze the PRD

Read the PRD and identify:
- All features that need to be built
- Acceptance criteria from the PRD
- Technical approach / integrations
- Test strategy mentioned

### 3. Phase 1: Generate Story List

Break the PRD into stories. Each story should be:
- **Small enough** for one agent session (~15-60 min of work)
- **Self-contained** - can be implemented and verified independently
- **Verifiable** - has clear done criteria

Present the story list and use `AskUserQuestion`:
```yaml
question: "Does this story breakdown look right?"
header: "Stories"
options:
  - label: "Yes, looks good"
    description: "Proceed to generate beads"
  - label: "Add more stories"
    description: "I want to add something"
  - label: "Adjust these"
    description: "Let me suggest changes"
```

### 4. Phase 2: Generate Acceptance Criteria

For each story, generate acceptance criteria that:
- Are specific and verifiable
- Include test cases where applicable
- An agent can objectively determine pass/fail

**Good criteria:**
```
- Function validates email format
- Rejects 'invalid' (no @ symbol)
- Rejects 'user@' (no domain)
- Accepts 'user@domain.com'
- Tests pass
```

**Bad criteria:**
```
- Email validation works well
- Tests are written
- Code is clean
```

### 5. Ask About Session Name

```yaml
question: "What should we call this session? (used for tagging beads)"
header: "Session"
options:
  - label: "{suggested-slug}"
    description: "Based on the PRD name"
  - label: "Let me name it"
    description: "I'll type a custom name"
```

### 6. Initialize Beads (if needed)

```bash
# Check if beads is initialized
bd list 2>/dev/null || bd init
```

### 7. Create Beads

For each story:
```bash
bd create \
  --title="Story title" \
  --type=task \
  --priority=2 \
  --add-label="loop/{session-name}" \
  --description="Description here" \
  --acceptance="- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests pass"
```

**Dependencies:** Only add when story B literally cannot start without story A complete:
```bash
bd dep add {story-b-id} {story-a-id}
```

The agent will use judgment to pick the logical next task. Don't over-specify dependencies.

### 8. Confirm Output

```
✅ Created {N} beads for session: {session-name}

View beads:    bd list --label=loop/{session-name}
Ready to work: bd ready --label=loop/{session-name}

Next steps:
- Refine beads: /loop-agents:refine
- Launch work loop: /loop-agents:loop
```

**IMPORTANT:** The session name must be clearly outputted so other commands can use it.

## Story Sizing Guidelines

**Too big:**
- Touches more than 3-4 files
- Requires multiple unrelated changes
- Can't describe in one sentence

**Too small:**
- Just "create a file"
- Can't be meaningfully tested
- Is a sub-step of something else

**Just right:**
- Clear deliverable
- 15-60 minutes of work
- Testable outcome

## Success Criteria

- [ ] Found or created PRD to work from
- [ ] Story list approved by user
- [ ] Every acceptance criterion is verifiable
- [ ] Beads created with `loop/{session}` label
- [ ] Dependencies only where truly required
- [ ] Session name clearly communicated
