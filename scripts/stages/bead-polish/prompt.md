# Bead Polish Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

${CONTEXT}

---

Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Use ultrathink.

---

## Engine Integration

### Load Context

```bash
# Read progress file
cat ${PROGRESS}

# Read inputs from previous stages
jq -r '.inputs.from_stage | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== Previous stage: $file ==="
  cat "$file"
done
```

### Review Beads

```bash
bd list --label=pipeline/${SESSION_NAME}
bd ready --label=pipeline/${SESSION_NAME}
```

### Update Progress

Append a summary of polish changes to `${PROGRESS}`.

### Write Status

**If more polish needed:**
```json
{
  "decision": "continue",
  "reason": "Found issues that need correction",
  "summary": "Reviewed beads, found N issues to address",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**If beads are ready:**
```json
{
  "decision": "stop",
  "reason": "Beads are polished and ready for implementation",
  "summary": "All beads validated, tests comprehensive, ready to implement",
  "work": {"items_completed": ["bead-polish"], "files_touched": []},
  "errors": []
}
```
