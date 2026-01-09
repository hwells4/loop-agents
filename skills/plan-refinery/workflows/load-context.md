# Workflow: Load Context

Load project context fresh in a new Claude Code session. Breaks out of local optima.

## When to Use
- Starting a brand new CC session
- After context has been compacted
- When previous refinement iterations are plateauing
- Before doing a fresh bead review

## Steps

### 1. Verify Fresh Session

Check if this is appropriate:
- Is this a new session? (ideal)
- Has context been compacted? (good)
- Are we stuck in local optima? (good reason)

### 2. Spawn Context Loader Agent

Read the full prompt from `references/sub-agents.md#context_loader`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Load project context",
  prompt="""
First read ALL of the AGENTS.md file and README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code, and technical architecture and purpose of the project. Use ultrathink.

YOUR TASK:
1. Read AGENTS.md completely - understand the project's agent workflow
2. Read README.md completely - understand the project purpose
3. Explore the codebase structure:
   - Run `ls -la` at root
   - Identify key directories and their purposes
   - Read main entry points and core modules
4. Understand technical architecture:
   - What frameworks/languages are used?
   - What are the key abstractions?
   - How do components interact?
5. Build mental model of the project

OUTPUT:
Return a structured summary:
- Project purpose (1-2 sentences)
- Technical stack
- Key components and their roles
- Architecture overview
- Important patterns observed
- Areas that may need attention based on code structure

Maximum: 2,000 words output. Deep understanding stays internal.
"""
)
```

### 3. Process Results

Display the context summary to user. This establishes shared understanding.

### 4. Suggest Next Step

```
PROJECT CONTEXT LOADED

{context summary from agent}

Recommended next step:
→ Run `/plan-refinery review` to review beads with fresh perspective
```

## Notes

- This is a CONTEXT LOADING step, not a refinement step
- The actual bead review happens in the post-context-reviewer workflow
- The value is in breaking out of local optima with fresh eyes
- Agent's deep understanding stays in its context, summary comes back

## Success Criteria
- [ ] Opus agent spawned with full prompt
- [ ] Agent read AGENTS.md and README.md
- [ ] Agent explored codebase structure
- [ ] Summary returned to orchestrator
- [ ] User directed to review workflow next
