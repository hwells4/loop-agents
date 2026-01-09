---
name: create-tasks
description: Generate stories from a PRD for autonomous or assisted execution. Use when user says "generate tasks", "break this down", "create stories", or has a PRD they want to execute.
context_budget:
  skill_md: 200
  max_references: 1
---

## MANDATORY TOOL USAGE

**ALL clarifying questions MUST use the `AskUserQuestion` tool.**

Never output questions as text in your response. If you need information, invoke `AskUserQuestion`.

## What This Skill Produces

Beads tagged with `loop/{session-name}` that an agent can execute autonomously:

```bash
# Each story becomes a bead
bd create --title="US-001: Story title" --type=task --assignee=agent --label=loop/feature-name

# Body contains acceptance criteria
```

**Bead body format:**
```markdown
## Acceptance Criteria
- [ ] Criterion that can be verified
- [ ] Test: specific test case
- [ ] npm test passes
- [ ] typecheck passes
```

## Process

### 1. Find the PRD

Check `brain/outputs/` for PRDs. If multiple exist, use `AskUserQuestion` to ask which one.

If no PRD exists, ask if they want to:
- A) Create a PRD first (invoke `/prd` skill)
- B) Describe the feature now (you'll ask clarifying questions)

### 2. Analyze the PRD

Read the PRD and identify:
- All features that need to be built
- Acceptance criteria from the PRD
- Technical approach / integrations
- Test strategy mentioned

### 3. Phase 1: Generate Story List

Break the PRD into stories. Each story should be:
- **Small enough** for one agent session (one context window)
- **Self-contained** - can be implemented and verified independently
- **Verifiable** - has clear done criteria

Present the story list and use `AskUserQuestion` for approval:

```
## Stories

1. US-001: [Title]
2. US-002: [Title]
3. US-003: [Title]
...
```

```yaml
question: "Does this story breakdown look right?"
header: "Stories"
options:
  - label: "Yes, generate acceptance criteria"
    description: "Looks good, proceed to next phase"
  - label: "Add more stories"
    description: "I want to add something"
  - label: "Adjust these"
    description: "Let me suggest changes"
```

### 4. Phase 2: Generate Acceptance Criteria

For each story, generate acceptance criteria that:
- Are specific and verifiable
- Include test cases (prefix with "Test:")
- Include verification commands (npm test, typecheck, etc.)
- An agent can objectively determine pass/fail

**Good criteria:**
```
- Function validates email format using regex
- Test: rejects 'invalid' (no @ symbol)
- Test: rejects 'user@' (no domain)
- Test: accepts 'user@domain.com'
- npm test passes
- typecheck passes
```

**Bad criteria:**
```
- Email validation works well
- Tests are written
- Code is clean
```

### 5. Ask About Session and Verification

Use `AskUserQuestion` for each:

**Session name:**
```yaml
question: "What should we call this session? (used for tagging beads)"
header: "Session"
options:
  - label: "{suggested-slug}"
    description: "Based on the PRD name"
  - label: "Let me name it"
    description: "I'll type a custom name"
```

**Verification commands (optional):**

Ask what commands should run after each task:
```yaml
question: "What commands should verify each task? (leave empty for none)"
header: "Verify"
options:
  - label: "None"
    description: "No verification needed"
  - label: "Custom"
    description: "I'll specify commands"
```

If user specifies commands, save to progress file header:
```bash
# Replace the Verify: line in the progress file
sed -i '' "s/^Verify:.*/Verify: ${COMMANDS}/" .claude/loop-progress/progress-${SESSION}.txt
```

Examples: `npm test && npm run typecheck`, `pytest`, `bundle exec rspec`, or any custom commands.

### 6. Create Beads

For each story, create a bead with the `loop/{session-name}` tag:

```bash
bd create \
  --title="US-001: Story title" \
  --type=task \
  --assignee=agent \
  --label=loop/{session-name}
```

Then write the acceptance criteria to the bead body using `bd edit` or by editing the bead file directly at `.beads/beads-xxx.md`.

**Dependencies:** Only add `bd dep add` when story B literally cannot be implemented without story A being complete. The agent will use judgment to pick the most logical next task from available beads.

Example with dependency:
```bash
# Create stories
bd create --title="US-001: User model" --type=task --assignee=agent --label=loop/user-auth
bd create --title="US-002: Password hashing" --type=task --assignee=agent --label=loop/user-auth
bd create --title="US-003: Login endpoint" --type=task --assignee=agent --label=loop/user-auth

# Login truly depends on User model
bd dep add beads-003 beads-001
```

### 7. Confirm Output and Return Session Name

Show the user:
- **Session name: `{session-name}`** ← This is the key output
- Number of stories created
- List beads: `bd list --label=loop/{session-name}`

**IMPORTANT:** The session name must be clearly outputted so `/loop` can capture it for launching tmux.

Example output:
```
✅ Created 5 stories for session: user-auth

Stories: bd list --label=loop/user-auth
Ready:   bd ready --label=loop/user-auth

Session name: user-auth
```

## Story Sizing Guidelines

A story is too big if:
- It touches more than 3-4 files
- It requires multiple unrelated changes
- You can't describe it in one sentence

A story is too small if:
- It's just "create a file"
- It can't be meaningfully tested
- It's a sub-step of something else

## Success Criteria

- [ ] Found or created PRD to work from
- [ ] Generated story list and got user "Go"
- [ ] Every acceptance criterion is objectively verifiable
- [ ] Test cases are explicit (not "write tests")
- [ ] Verification commands included
- [ ] Beads created with correct tag: `loop/{session-name}`
- [ ] Dependencies added only where truly required
