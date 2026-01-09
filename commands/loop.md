---
description: Plan, launch, and monitor autonomous loop agents
hooks:
  PreToolUse:
    - matcher: ""
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/skills/loops/scripts/loop-prehook.sh"
          once: true
---

# /loop Command

**Automated end-to-end flow:** Gather context → Generate PRD → Create tasks → Launch autonomous agent

Execute phases adaptively based on context. Always use `AskUserQuestion` for interactions - be quick and conversational.

## Usage

```
/loop                    # Full adaptive flow
/loop status             # Check running loops
/loop attach NAME        # Attach to a session
/loop kill NAME          # Stop a session
```

---

## ADAPTIVE EXECUTION

**Key principle:** Be intelligent about what's needed. Skip phases that aren't necessary. Always use `AskUserQuestion` with an "Other" option so users can type custom responses quickly.

### Phase 1: Gather Context (Adaptive)

**If invoked with no context** (user just typed `/loop`):

Use `AskUserQuestion`:
```yaml
question: "What do you want to build or accomplish?"
header: "Goal"
options:
  - label: "Build a new feature"
    description: "Add new functionality to the codebase"
  - label: "Improve existing code"
    description: "Refactor, optimize, or fix something"
  - label: "Batch operation"
    description: "Process multiple items (files, records, etc.)"
  - label: "I have a PRD ready"
    description: "Skip planning, go straight to task generation"
```

Then ask for specifics:
```yaml
question: "Briefly describe what you want to build:"
header: "Description"
options:
  - label: "Let me type it out"
    description: "I'll describe it in the 'Other' field below"
```

**If invoked with context** (user described what they want):

Ask deeper clarifying questions based on what they said. Examples:
- "What's the scope?" (MVP vs full feature)
- "Any specific tech/patterns to use?"
- "What should it integrate with?"

**If context is already clear** (enough detail provided):

Confirm and move to PRD generation:
```yaml
question: "Ready to generate a PRD for: {summary}?"
header: "Confirm"
options:
  - label: "Yes, generate PRD"
    description: "I'll review and refine it"
  - label: "Let me add more details"
    description: "I want to clarify something first"
```

### Phase 2: Research Codebase (Skip if Not Needed)

**Only spawn Explore subagents if:**
- Building on existing code
- Need to understand patterns/architecture
- Integrating with existing systems

**Skip exploration if:**
- Greenfield/new project
- User already knows the codebase well
- The feature is standalone

When exploring, spawn 1-2 focused agents:
```
Task(subagent_type="Explore", prompt="Find files related to {topic}. Understand patterns to follow.")
```

### Phase 3: Generate PRD

Invoke the create-prd skill:
```
Skill(skill="create-prd")
```

This asks adaptive questions and creates: `brain/outputs/{date}-{slug}-prd.md`

**Skip if user said "I have a PRD ready"** - use `AskUserQuestion` to ask which PRD:
```yaml
question: "Which PRD should I use?"
header: "PRD"
options:
  - label: "{most recent PRD}"
    description: "brain/outputs/{filename}"
  - label: "Let me specify"
    description: "I'll provide the path"
```

### Phase 4: Generate Stories → Beads

Invoke the create-tasks skill:
```
Skill(skill="create-tasks")
```

This creates beads tagged `loop/{session-name}` and returns the session name.

### Phase 5: Confirm and Launch

**Calculate suggested iterations:** stories + buffer for retries/fixes
- 5 stories → suggest ~8 iterations
- 10 stories → suggest ~15 iterations
- 15 stories → suggest ~20 iterations
- Formula: `stories * 1.3 + 3` (rounded up)

Use `AskUserQuestion` for final confirmation:
```yaml
question: "Ready to launch loop-{session-name} with {N} stories?"
header: "Launch"
options:
  - label: "Yes, start it ({suggested} iterations)"
    description: "Recommended based on {N} stories"
  - label: "Test one iteration first"
    description: "Run loop-once.sh to verify setup"
  - label: "Fewer iterations ({stories + 2})"
    description: "Tighter run, less buffer"
```

### Phase 6: Launch in tmux

```bash
SESSION_NAME="{from phase 4}"
ITERATIONS="{from phase 5, default 15}"

tmux new-session -d -s "loop-$SESSION_NAME" -c "$(pwd)" ".claude/loop-agents/scripts/loop.sh $ITERATIONS $SESSION_NAME"
```

**Show confirmation:**

```
╔════════════════════════════════════════════════════════════╗
║  🚀 Loop Launched: loop-{session-name}                     ║
╠════════════════════════════════════════════════════════════╣
║                                                            ║
║  Running autonomously ({iterations} iterations max)        ║
║                                                            ║
║  Check progress:                                           ║
║    bd ready --label=loop/{session-name}                      ║
║    tmux capture-pane -t loop-{session-name} -p | tail -20  ║
║                                                            ║
║  Commands:                                                 ║
║    /loop status                - Check all loops           ║
║    /loop attach {session-name} - Watch live                ║
║    /loop kill {session-name}   - Stop the loop             ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

---

## ALWAYS USE AskUserQuestion

**Every interaction should use `AskUserQuestion`** with practical options plus the ability to type custom input (users can always select "Other").

Good pattern:
```yaml
question: "What testing framework does this project use?"
header: "Tests"
options:
  - label: "npm test"
    description: "Standard npm test command"
  - label: "pytest"
    description: "Python pytest"
  - label: "No tests yet"
    description: "Skip test verification"
```

This keeps things quick and interactive - user clicks an option or types something custom.

---

## Subcommands

### /loop status
```bash
tmux list-sessions 2>/dev/null | grep "^loop-" || echo "No loop sessions running"
bd ready --label=loop/ 2>/dev/null | head -10
```

### /loop attach NAME
```bash
tmux attach -t loop-NAME
```
Remind: `Ctrl+b` then `d` to detach.

### /loop kill NAME
```bash
tmux kill-session -t loop-NAME
```

---

## Multi-Agent Support

Multiple loops run simultaneously with separate beads and progress files:

```bash
tmux new-session -d -s "loop-auth" ".claude/loop-agents/scripts/loop.sh 15 auth"
tmux new-session -d -s "loop-dashboard" ".claude/loop-agents/scripts/loop.sh 15 dashboard"
```
