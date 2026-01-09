# Workflow: Refine Beads

Iteratively improve beads using the bead-refiner Opus subagent. Run 6+ times for complex plans.

## Prerequisites
- Beads already created from markdown plan
- `bd` tool available
- AGENTS.md exists in project root

## Steps

### 1. Check Current State
```bash
bd list --status=open
bd stats
```

Count open beads. If zero, inform user they need to create beads first.

### 2. Spawn Bead Refiner Agent

Read the full prompt from `references/sub-agents.md#bead_refiner`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Refine beads iteration",
  prompt="""
Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the `bd` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.

YOUR TASK:
1. Read AGENTS.md first (critical context)
2. Run `bd list --status=open` to see all beads
3. For each bead, run `bd show <id>` and ask:
   - Does this make sense?
   - Is it optimal?
   - Could we improve it for users?
   - Does it have proper dependencies?
   - Does it include test coverage requirements?
4. Update beads using `bd update <id> --body="..."` for improvements
5. Add any missing beads for tests/e2e scripts
6. Add dependencies with `bd dep add <bead> <depends-on>`

OUTPUT:
Return a summary of:
- Beads reviewed
- Changes made
- New beads added
- Whether you see opportunities for further refinement (plateau detection)

Maximum: 2,000 words output. Keep reasoning internal.
"""
)
```

### 3. Process Results

Wait for agent to complete. Display summary to user.

### 4. Offer Iteration

Present to user:

```
BEAD REFINEMENT COMPLETE (Iteration {N})

Changes: {summary from agent}

Options:
[1] Run again (Recommended - iteration {N+1} typically finds more improvements)
[2] Done refining - ready for implementation
[3] Start fresh session (recommended if improvements are plateauing)
```

If user chooses [1], go back to Step 2.
If user chooses [3], suggest running `/plan-refinery context` in new session.

## Plateau Detection

Watch for these signs in agent output:
- "No significant changes needed"
- "Minor adjustments only"
- Same beads getting tweaked repeatedly

When detected, suggest moving to implementation or starting fresh session.

## Success Criteria
- [ ] Beads exist before running
- [ ] Opus agent spawned with full prompt
- [ ] Agent used `bd` tools (not direct file edits)
- [ ] Summary returned to orchestrator
- [ ] User offered iteration option
- [ ] Features preserved (no oversimplification)
