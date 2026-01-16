# Bead Refinement Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

${CONTEXT}

---

Reread AGENTS dot md so it's still fresh in your mind. Now read ALL of PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md. Then check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? We want a comprehensive and granular set of beads for all this with tasks, subtasks, and dependency structure overlaid, with detailed comments so that the whole thing is totally self-contained and self-documenting (including relevant background, reasoning/justification, considerations, etc.-- anything we'd want our "future self" to know about the goals and intentions and thought process and how it serves the over-arching goals of the project.). The beads should be so detailed that we never need to consult back to the original markdown plan document. Does it accurately reflect ALL of the markdown plan file in a comprehensive way? If changes are warranted then revise the beads or create new ones or close invalid or inapplicable ones. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the `bd` tool to create and modify the beads and to add the dependencies to beads.

---

## Engine Integration

### Load Context

```bash
# Read progress file
cat ${PROGRESS}

# Read AGENTS.md
cat AGENTS.md 2>/dev/null || echo "No AGENTS.md"

# Read the optimization plan
cat docs/PLAN_FOR_ADVANCED_OPTIMIZATIONS_ROUND_1__OPUS.md 2>/dev/null

# Read inputs from previous stages
jq -r '.inputs.from_stage | to_entries[]? | .value[]?' ${CTX} 2>/dev/null | while read file; do
  echo "=== Previous stage: $file ==="
  cat "$file"
done
```

### Review Existing Beads

```bash
bd list --label=pipeline/${SESSION_NAME}
bd ready --label=pipeline/${SESSION_NAME}
```

### Update Progress

Append a summary of bead changes to `${PROGRESS}`.

### Write Status

**If more refinement needed:**
```json
{
  "decision": "continue",
  "reason": "More beads need refinement or plan not fully captured",
  "summary": "Reviewed N beads, created M new ones, still need to cover X areas",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**If beads are comprehensive:**
```json
{
  "decision": "stop",
  "reason": "Beads comprehensively cover the optimization plan",
  "summary": "All plan items captured in self-documenting beads with tests",
  "work": {"items_completed": ["bead-refinement"], "files_touched": []},
  "errors": []
}
```
