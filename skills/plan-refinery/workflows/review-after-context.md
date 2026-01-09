# Workflow: Review After Context

Review beads with fresh perspective after loading context in a new session.

## Prerequisites
- Ideally: Just ran `/plan-refinery context` to load fresh context
- Beads exist from previous planning work
- New session or compacted context

## Steps

### 1. Verify Beads Exist

```bash
bd list --status=open
bd stats
```

If no beads, inform user this workflow requires existing beads.

### 2. Spawn Post-Context Reviewer Agent

Read the full prompt from `references/sub-agents.md#post_context_reviewer`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Review beads post-context",
  prompt="""
We recently transformed a markdown plan file into a bunch of new beads. I want you to very carefully review and analyze these using `bd` and `bv`.

Reread AGENTS.md so it's still fresh in your mind. Check over each bead super carefully-- are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Remember to ONLY use the `bd` tool to create and modify the beads and to add the dependencies to beads. Use ultrathink.

FRESH PERSPECTIVE CHECKLIST:
- With fresh eyes, do these beads still make sense?
- Are there assumptions baked in that should be questioned?
- Did the original planning miss anything obvious?
- Are dependencies correctly ordered?
- Is test coverage comprehensive?

YOUR TASK:
1. Read AGENTS.md first
2. Run `bd list --status=open` to see all beads
3. Run `bd blocked` to see dependency issues
4. For each bead, critically evaluate with fresh perspective
5. Make improvements using `bd update` and `bd dep add`

OUTPUT:
Return a summary of:
- Fresh observations (what looks different with clean context)
- Changes made
- Concerns or questions for the user
- Readiness assessment: Are beads ready for implementation?

Maximum: 2,000 words output.
"""
)
```

### 3. Process Results

Display the review summary, especially:
- Fresh observations (this is the value of new session)
- Changes made
- Readiness assessment

### 4. Determine Next Steps

Based on agent's readiness assessment:

**If READY:**
```
BEADS READY FOR IMPLEMENTATION

Fresh review complete. Agent assessment: Ready to implement.

Next step: Start implementation
```

**If NOT READY:**
```
BEADS NEED MORE REFINEMENT

Fresh observations:
{observations from agent}

Concerns:
{concerns from agent}

Options:
[1] Run another review pass
[2] Run standard refine workflow (/plan-refinery refine)
[3] Address concerns manually
```

## Value of Fresh Session

The key insight: Starting a new CC session gives the agent a clean context window. This means:
- No accumulated assumptions from previous work
- Fresh pattern matching on the beads
- Questions that seem obvious but were missed
- Breaking out of "local optima" in planning

## Success Criteria
- [ ] Beads exist before running
- [ ] Opus agent spawned with full prompt
- [ ] Agent used fresh perspective checklist
- [ ] Agent assessed readiness for implementation
- [ ] Summary returned with actionable next steps
- [ ] Features preserved (no oversimplification)
