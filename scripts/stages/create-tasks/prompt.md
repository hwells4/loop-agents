# Create Tasks from Plan

Read context from: ${CTX}
Progress file: ${PROGRESS}
Session: ${SESSION_NAME}

${CONTEXT}

## Your Task

You are breaking down a technical plan into executable beads (tasks).

### Step 1: Load the Plan

```bash
# Read initial inputs (CLI --input flags)
jq -r '.inputs.from_initial[]? // empty' ${CTX} | while read file; do
  echo "=== Plan from initial input: $file ==="
  cat "$file"
done

# Read outputs from previous stages (multi-stage pipelines)
jq -r '.inputs.from_stage | to_entries[]? | .value[]? // empty' ${CTX} | while read file; do
  echo "=== Plan from previous stage: $file ==="
  cat "$file"
done

# Read outputs from parallel blocks (multi-provider analysis)
jq -r '.inputs.from_parallel | to_entries[]? | .value[]? // empty' ${CTX} | while read file; do
  echo "=== Plan from parallel provider: $file ==="
  cat "$file"
done

# Fallback to filesystem search if no inputs found
if ! jq -e '.inputs | ((.from_initial | length > 0) or (.from_stage | length > 0) or (.from_parallel | length > 0))' ${CTX} > /dev/null 2>&1; then
  echo "No inputs found, searching filesystem..."
  cat plans/*.md docs/plans/*.md 2>/dev/null | head -200
fi
```

### Step 2: Analyze the Plan

Identify:
- All features/components that need to be built
- Implementation phases mentioned
- Dependencies between components
- Test requirements

### Step 3: Break Down into Beads

Create beads that are:
- **Small enough** for one agent session (~15-60 min of work)
- **Self-contained** - can be implemented and verified independently
- **Verifiable** - has clear done criteria

**Good bead sizing:**
- Touches 1-6 files
- Clear single deliverable
- Testable outcome

### Step 4: Create the Beads

```bash
# Initialize beads if needed
bd list 2>/dev/null || bd init

# Create each bead
bd create \
  --title="Clear action verb + what" \
  --type=task \
  --priority=2 \
  --labels="pipeline/${SESSION_NAME}" \
  --description="What needs to be done" \
  --acceptance="- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests pass"
```

**For dependencies** (only when B literally cannot start without A):
```bash
bd dep add {story-b-id} {story-a-id}
```

### Step 5: Update Progress

Write to progress file:
```
## Initial Task Breakdown

Created N beads from plan:
- [List of beads created]
- [Key dependencies established]
```

### Step 6: Write Result

```bash
cat > ${RESULT} << 'EOF'
{
  "summary": "Created initial beads from plan",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "artifacts": {
    "outputs": [],
    "paths": []
  },
  "signals": {
    "plateau_suspected": false,
    "risk": "low",
    "notes": "Tasks created, ready for refinement"
  }
}
EOF
```
