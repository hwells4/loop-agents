# Sub-Agent Definitions for Plan Refinery

This file defines the 7 Opus subagents used by the plan-refinery skill. Each agent runs independently to manage its own context, using Opus 4.5 with ultrathink for maximum reasoning depth.

**All agents use:** `model: "opus"` in the Task tool call.

<bead_refiner>
## Bead Refiner

**Purpose:** Iteratively review and improve beads. Run this N times (6+ for complex plans) until improvements plateau.

**When to spawn:** After initial beads are created from a markdown plan.

**Model:** Opus 4.5 with ultrathink

**Prompt:**
```
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
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Refine beads iteration",
  prompt="[Full prompt above]"
)
```

**Iteration pattern:**
Orchestrator should ask user: "Run again for more refinement? (Recommended until improvements plateau)"
</bead_refiner>

<context_loader>
## Context Loader

**Purpose:** Load project context fresh in a new Claude Code session. Breaks out of local optima by starting with clean context.

**When to spawn:** At the start of a new CC session, before reviewing beads.

**Model:** Opus 4.5 with ultrathink

**Prompt:**
```
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
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Load project context",
  prompt="[Full prompt above]"
)
```

**Note:** This agent is for CONTEXT LOADING only. Follow up with the post-context reviewer for bead review.
</context_loader>

<post_context_reviewer>
## Post-Context Reviewer

**Purpose:** Review beads after loading fresh context in a new session. Brings fresh perspective to bead analysis.

**When to spawn:** After running context-loader in a new session.

**Model:** Opus 4.5 with ultrathink

**Prompt:**
```
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
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Review beads post-context",
  prompt="[Full prompt above]"
)
```
</post_context_reviewer>

<plan_synthesizer>
## Plan Synthesizer

**Purpose:** Merge competing plans from multiple LLMs into a single "best of all worlds" hybrid plan.

**When to spawn:** When user has collected outputs from GPT Pro, Gemini Deep Think, Grok Heavy, Opus, etc.

**Model:** Opus 4.5 with ultrathink

**Input required:** User must provide the competing plans inline or as file paths.

**Prompt:**
```
I asked 3 competing LLMs to do the exact same thing and they came up with pretty different plans which you can read below. I want you to REALLY carefully analyze their plans with an open mind and be intellectually honest about what they did that's better than your plan. Then I want you to come up with the best possible revisions to your plan (you should simply update your existing document for your original plan with the revisions) that artfully and skillfully blends the "best of all worlds" to create a true, ultimate, superior hybrid version of the plan that best achieves our stated goals and will work the best in real-world practice to solve the problems we are facing and our overarching goals while ensuring the extreme success of the enterprise as best as possible; you should provide me with a complete series of git-diff style changes to your original plan to turn it into the new, enhanced, much longer and detailed plan that integrates the best of all the plans with every good idea included (you don't need to mention which ideas came from which models in the final revised enhanced plan).

PLANS TO ANALYZE:
{competing_plans}

YOUR TASK:
1. Read each competing plan carefully
2. For each plan, identify:
   - Unique strengths and good ideas
   - Better architecture decisions
   - Superior feature designs
   - More robust approaches
   - Better user experience considerations
3. Be INTELLECTUALLY HONEST - acknowledge when other plans are better
4. Create hybrid plan that takes the best from ALL sources
5. Output as git-diff style changes to the original

OUTPUT FORMAT:
## Analysis of Competing Plans

### Plan 1 Strengths
- {strength}

### Plan 2 Strengths
- {strength}

### Plan 3 Strengths
- {strength}

## Synthesis: Git-Diff Style Changes

```diff
- original line
+ improved line from synthesis
```

## Final Hybrid Plan
{complete merged plan}

Maximum: 3,000 words output. Detailed analysis stays internal.
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Synthesize competing plans",
  prompt="[Prompt with {competing_plans} filled in from user input]"
)
```

**Note:** Orchestrator must collect the competing plans from user before spawning this agent.
</plan_synthesizer>

<plan_improver>
## Plan Improver

**Purpose:** Iteratively improve an existing markdown plan. Each pass proposes specific improvements with rationale.

**When to spawn:** When user has a markdown plan file they want to improve.

**Model:** Opus 4.5 with ultrathink

**Input required:** Path to the markdown plan file.

**Prompt:**
```
Carefully review this entire plan for me and come up with your best revisions in terms of better architecture, new features, changed features, etc. to make it better, more robust/reliable, more performant, more compelling/useful, etc. For each proposed change, give me your detailed analysis and rationale/justification for why it would make the project better along with the git-diff style change versus the original plan shown below.

PLAN FILE: {plan_path}

YOUR TASK:
1. Read the entire plan file carefully
2. Analyze for improvement opportunities:
   - Architecture: Better design decisions?
   - Features: Missing or improvable features?
   - Robustness: Error handling, edge cases, reliability?
   - Performance: Scalability, efficiency?
   - User Experience: More compelling, easier to use?
3. For EACH proposed change:
   - Explain WHY it makes the project better
   - Provide detailed rationale/justification
   - Show git-diff style change
4. Prioritize changes by impact

OUTPUT FORMAT:
## Plan Review: {plan_name}

### Change 1: {title}
**Impact:** High/Medium/Low
**Category:** Architecture/Feature/Robustness/Performance/UX

**Analysis:**
{detailed reasoning for why this change improves the project}

**Rationale:**
{justification for the change}

**Git-diff:**
```diff
- original text
+ improved text
```

---

### Change 2: {title}
...

## Summary
- Total changes proposed: {count}
- High impact: {count}
- Medium impact: {count}
- Recommended next iteration: Yes/No (are there likely more improvements?)

Maximum: 2,500 words output.
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Improve markdown plan",
  prompt="[Prompt with {plan_path} filled in]"
)
```

**Iteration pattern:**
After agent returns, orchestrator applies changes and asks: "Run another improvement pass? (Recommended until diminishing returns)"
</plan_improver>

<idea_wizard>
## Idea Wizard

**Purpose:** Generate and rigorously evaluate improvement ideas for a project. Starts with 30 ideas, thinks through each carefully, then winnows to the very best 5 with full rationale.

**When to spawn:** When you want fresh, creative ideas to improve a project before or during planning. Great for breaking out of tunnel vision.

**Model:** Opus 4.5 with ultrathink

**Input required:** Context about the project (can be beads, a plan file, or just the codebase).

**Prompt:**
```
Come up with your very best ideas for improving this project to make it more robust, reliable, performant, intuitive, user-friendly, ergonomic, useful, compelling, etc. while still being obviously accretive and pragmatic. Come up with 30 ideas and then really think through each idea carefully, how it would work, how users are likely to perceive it, how we would implement it, etc; then winnow that list down to your VERY best 5 ideas. Explain each of the 5 ideas in order from best to worst and give your full, detailed rationale and justification for how and why it would make the project obviously better and why you're confident of that assessment. Use ultrathink.

PROJECT CONTEXT:
{project_context}

YOUR TASK:
1. Understand the project thoroughly first
2. Brainstorm 30 improvement ideas across all dimensions:
   - Robustness and reliability
   - Performance and efficiency
   - Intuitive design and user-friendliness
   - Ergonomics and developer experience
   - Usefulness and value proposition
   - Compelling features that delight users
3. For EACH of the 30 ideas, think through:
   - How would this actually work?
   - How would users perceive it?
   - How would we implement it?
   - Is it pragmatic and accretive?
4. Winnow to your VERY BEST 5 ideas
5. Rank them best to worst with full justification

OUTPUT FORMAT:
## Idea Generation: {project_name}

### Initial 30 Ideas (Brief List)
1. {idea}
2. {idea}
...
30. {idea}

### Winnowed to Top 5

#### #1: {title} (BEST)
**What it is:**
{description}

**How it works:**
{mechanics}

**User perception:**
{how users will experience this}

**Implementation approach:**
{how to build it}

**Why this is the best idea:**
{detailed rationale and justification}

**Confidence level:** High/Medium
{why you're confident}

---

#### #2: {title}
...

#### #3: {title}
...

#### #4: {title}
...

#### #5: {title} (Still excellent)
...

## Summary
These 5 ideas were selected from 30 because they best combine:
- Obvious value to users
- Pragmatic implementation
- Meaningful improvement to the project

Maximum: 3,000 words output. The 30→5 winnowing process stays internal.
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Generate best improvement ideas",
  prompt="[Prompt with {project_context} filled in]"
)
```

**Context options:**
- Point agent at beads: `bd list --status=open` output
- Point agent at plan file: read and include content
- Point agent at codebase: let it explore with Task tool

**Note:** This agent is for IDEATION, not implementation. Use output to inform beads or plan updates.
</idea_wizard>

<robot_mode_maker>
## Robot-Mode Maker

**Purpose:** Design agent-optimized CLI interfaces for projects. Creates "robot mode" that lets coding agents access all functionality without UI, with output optimized for agent consumption (JSON/markdown).

**When to spawn:** When building tools that agents will use, or when you want to add agent-friendly interfaces to existing projects.

**Model:** Opus 4.5 with ultrathink

**Input required:** Context about the project/tool that needs agent-friendly interfaces.

**Prompt:**
```
Next, I want you to create a "robot mode" for coding agents that want to interact with this so they don't need to use the UI but can instead access all the same functionality via a cli in the console that is hyper-optimized and ergonomic for agents, while also being ultra-intuitive for coding agents like yourself; the agent users should get back as output either json or markdown-- whatever fits best in the context and is most token-efficient and intuitive for you.

Basically, the agent users should get all the same information as a human would get from manipulating and visually observing the UI, but in a more usable, helpful, intuitive, and accessible form for agents. Make the tooling here that YOU would want if YOU were using it (because you WILL be!), that maximizes agent ergonomics and agent intuition. Be sure to give the command a quick-start mode (when no arguments are supplied) that explains the most critical functionality in the most intuitive, token-dense way possible. Use ultrathink.

PROJECT CONTEXT:
{project_context}

YOUR TASK:
1. Understand the project's current functionality thoroughly
2. Identify all user-facing features that agents would need to access
3. Design CLI commands that expose this functionality:
   - Command names that are intuitive for agents
   - Arguments/flags that are ergonomic and predictable
   - Output formats (JSON/markdown) optimized for agent parsing
4. For each command, specify:
   - Name and purpose
   - Arguments and flags
   - Output format and structure
   - Example usage
5. Design the quick-start mode (no args):
   - Most critical functionality first
   - Token-dense explanations
   - Examples that teach by showing
6. Consider agent-specific needs:
   - Structured output for easy parsing
   - Predictable error formats
   - Idempotent operations where possible
   - Clear success/failure signals

OUTPUT FORMAT:
## Robot Mode Design: {project_name}

### Philosophy
{why these design choices optimize for agent usage}

### Quick-Start Output (when no args)
```
{exactly what agents see when they run the command with no args}
```

### Command Reference

#### `{command} {subcommand}`
**Purpose:** {what it does}
**When to use:** {agent decision criteria}

**Arguments:**
| Arg | Type | Required | Description |
|-----|------|----------|-------------|
| {arg} | {type} | {yes/no} | {description} |

**Output format:** JSON / Markdown
```json
{example output structure}
```

**Example:**
```bash
{command} {subcommand} {example args}
```

---

(repeat for all commands)

### Error Handling
{how errors are reported in agent-friendly format}

### Design Rationale
{why YOU would want to use this interface}

Maximum: 3,000 words output. Design reasoning stays internal.
```

**Task tool call:**
```
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Design agent-optimized CLI",
  prompt="[Prompt with {project_context} filled in]"
)
```

**Key insight:** The agent designs for ITSELF. "Make the tooling that YOU would want if YOU were using it" - this creates genuinely agent-ergonomic interfaces rather than human assumptions about what agents need.

**Note:** This agent outputs a DESIGN. Implementation is separate. The design can become beads or direct implementation guidance.
</robot_mode_maker>

<spawning_reference>
## Quick Reference: Spawning Agents

All agents use the Task tool with `model="opus"` for Opus 4.5:

```python
Task(
  subagent_type="general-purpose",
  model="opus",  # CRITICAL: Use Opus for deep reasoning
  description="[3-5 word description]",
  prompt="[Full prompt from agent section]"
)
```

### Agent Selection Guide

| Scenario | Agent | Run Multiple Times? |
|----------|-------|---------------------|
| Just created beads from plan | bead-refiner | Yes, 6+ times |
| Starting new CC session | context-loader | Once |
| After context-loader | post-context-reviewer | Yes, until ready |
| Have outputs from multiple LLMs | plan-synthesizer | Once |
| Have markdown plan to improve | plan-improver | Yes, until plateau |
| Want fresh improvement ideas | idea-wizard | Once (then act on ideas) |
| Need agent-friendly CLI design | robot-mode-maker | Once (then implement) |

### Plateau Detection

Signs to stop iterating:
- Agent reports "no significant changes recommended"
- Changes become increasingly minor/cosmetic
- Same areas getting tweaked back and forth
- User feels confident in plan quality

### Iteration Prompts

After each agent run, orchestrator should offer:
- "Run again? Iteration {N} typically finds more improvements"
- "Improvements are diminishing. Ready to implement?"
- "Consider starting fresh session for new perspective"
</spawning_reference>

<ultrathink_note>
## Note on "Use ultrathink"

The phrase "Use ultrathink" in prompts signals to Claude that deep, extended reasoning is expected. This encourages:

- More thorough analysis before conclusions
- Consideration of edge cases and alternatives
- Structured thinking about complex tradeoffs
- Higher quality output through deliberation

All agents in this skill benefit from this prompting pattern given the planning-focused nature of the work.
</ultrathink_note>
