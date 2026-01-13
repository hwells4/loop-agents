# Create Tasks

Read context from: ${CTX}
Progress file: ${PROGRESS}
Session: ${SESSION_NAME}

## Your Task

Generate beads (tasks) from the plan document. These beads will be executed autonomously by a work agent.

### Step 1: Load Context

Read progress and find inputs:
```bash
cat ${PROGRESS}
cat ${CTX} | jq -r '.inputs // empty'
```

Find plan files:
```bash
ls -la plans/*.md 2>/dev/null
ls -la docs/plans/*.md 2>/dev/null
```

Read the plan that was refined in previous stages.

### Step 2: Analyze the Plan

Read the plan thoroughly and identify:
- All features/changes that need to be built
- Acceptance criteria (explicit or implied)
- Technical approach and integrations
- Testing requirements

### Step 3: Generate Stories

Break the plan into stories. Each story should be:
- **Small enough** for one agent session (~15-60 min of work)
- **Self-contained** - can be implemented and verified independently
- **Verifiable** - has clear done criteria

**Sizing guidelines:**
- Too big: Touches more than 3-4 files, requires multiple unrelated changes
- Too small: Just "create a file", can't be meaningfully tested
- Just right: Clear deliverable, 15-60 minutes of work, testable outcome

### Step 4: Create Beads

Initialize beads if needed:
```bash
bd list 2>/dev/null || bd init
```

For each story, create a bead:
```bash
bd create \
  --title="Story title" \
  --type=task \
  --priority=2 \
  --labels="pipeline/${SESSION_NAME}" \
  --description="What needs to be done" \
  --acceptance="- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests pass"
```

**Dependencies:** Only add when story B literally cannot start without story A complete:
```bash
bd dep add {story-b-id} {story-a-id}
```

Don't over-specify dependencies. The work agent uses judgment to pick logical next tasks.

### Step 5: Update Progress

Append to progress file:
```
## Tasks Created

Created {N} beads for session: ${SESSION_NAME}

Stories:
1. {bead-id}: {title}
2. {bead-id}: {title}
...

View: bd list --label=pipeline/${SESSION_NAME}
```

### Step 6: Write Status

Write your status to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Tasks created successfully",
  "summary": "Created N beads from the plan, tagged with pipeline/${SESSION_NAME}",
  "work": {
    "items_completed": ["Created N beads"],
    "files_touched": []
  },
  "errors": []
}
```

Use `"decision": "error"` only if something prevented task creation.
