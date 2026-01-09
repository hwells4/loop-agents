# Workflow: Robot Mode

Design agent-optimized CLI interfaces that let coding agents access all project functionality without a UI, with output hyper-optimized for agent consumption.

## When to Use
- Building tools that agents will interact with
- Adding agent-friendly interfaces to existing projects
- Designing CLI commands for agent workflows
- Creating "headless" modes for UI-based applications

## The Key Insight

The prompt asks the agent to design for ITSELF:

> "Make the tooling here that YOU would want if YOU were using it (because you WILL be!)"

This produces genuinely agent-ergonomic interfaces rather than human assumptions about what agents need.

## Prerequisites
- Project context (codebase, existing UI, or functionality description)
- Understanding of what functionality needs agent access

## Steps

### 1. Gather Project Context

Ask user about the project:

```
Robot Mode designs CLI interfaces optimized for agent consumption.

What project needs agent-friendly interfaces?

[1] Current project (I'll explore the codebase)
[2] Specific files/modules (provide paths)
[3] I'll describe the functionality
```

### 2. Collect Context Based on Choice

**Option 1 - Explore codebase:**
Include instruction for agent to explore first.

**Option 2 - Specific files:**
Read the provided files.

**Option 3 - Description:**
Wait for user to describe functionality.

### 3. Spawn Robot-Mode Maker Agent

Read the full prompt from `references/sub-agents.md#robot_mode_maker`.

```python
Task(
  subagent_type="general-purpose",
  model="opus",
  description="Design agent-optimized CLI",
  prompt=f"""
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
## Robot Mode Design: {{project_name}}

### Philosophy
{{why these design choices optimize for agent usage}}

### Quick-Start Output (when no args)
```
{{exactly what agents see when they run the command with no args}}
```

### Command Reference

#### `{{command}} {{subcommand}}`
**Purpose:** {{what it does}}
**When to use:** {{agent decision criteria}}

**Arguments:**
| Arg | Type | Required | Description |
|-----|------|----------|-------------|
| {{arg}} | {{type}} | {{yes/no}} | {{description}} |

**Output format:** JSON / Markdown
```json
{{example output structure}}
```

**Example:**
```bash
{{command}} {{subcommand}} {{example args}}
```

---

(repeat for all commands)

### Error Handling
{{how errors are reported in agent-friendly format}}

### Design Rationale
{{why YOU would want to use this interface}}

Maximum: 3,000 words output. Design reasoning stays internal.
"""
)
```

### 4. Process Results

Display the complete design:
- Philosophy and rationale
- Quick-start mode output
- Full command reference
- Error handling approach

### 5. Act on Design

Present options:

```
ROBOT MODE DESIGN COMPLETE

Agent-optimized CLI interface designed.

What would you like to do?

[1] Convert design to implementation beads
[2] Save design to file for reference
[3] Start implementing directly
[4] Refine the design (run again with feedback)
```

**If converting to beads:**
Create beads for:
- Core CLI infrastructure
- Each major command group
- Quick-start mode implementation
- Error handling system
- Tests for agent interaction

## Agent-Ergonomic Principles

The design should prioritize:

| Principle | Why |
|-----------|-----|
| **Structured output** | Agents parse JSON/markdown, not prose |
| **Predictable formats** | Same structure every time |
| **Token efficiency** | Minimize output length while preserving info |
| **Clear success/failure** | Agents need unambiguous signals |
| **Idempotent operations** | Safe to retry on failure |
| **Quick-start docs** | Teach the tool in minimal tokens |

## Example: What Agent-Friendly Looks Like

**Human-friendly output:**
```
Successfully created 3 new items. The first one is called "Widget"
and was assigned ID #42. The second one...
```

**Agent-friendly output:**
```json
{"status": "success", "created": [{"id": 42, "name": "Widget"}, ...]}
```

## Success Criteria
- [ ] Project context gathered
- [ ] Opus agent spawned with full prompt
- [ ] Design includes quick-start mode
- [ ] All commands have structured output formats
- [ ] Error handling is agent-friendly
- [ ] Agent explained why IT would want this design
- [ ] User offered actionable next steps
