# Workflow: Create Stage (Single-Stage Pipeline)

Create a new stage definition with custom prompt and completion strategy.

> **Note:** A "loop" is a single-stage pipeline. You're creating a stage definition in `scripts/loops/{name}/` that the unified engine runs as a single-stage pipeline.

## Prerequisites

Read these first:
- `references/loop-config.md` - Configuration options
- `references/template-variables.md` - Available variables
- `references/completion-strategies.md` - When to use each

## Step 1: Gather Requirements

**Use your judgment.** Based on what the user has told you, determine:

1. **Loop name** - Short, lowercase, hyphenated (e.g., `bug-hunter`, `doc-reviewer`)
2. **What each iteration does** - The agent's task
3. **When to stop** - What "done" means

**If unclear, ask focused questions:**
```json
{
  "questions": [{
    "question": "What should each iteration of this loop accomplish?",
    "header": "Task",
    "options": [
      {"label": "Implement a task", "description": "Pick a bead, implement it, close it"},
      {"label": "Improve a document", "description": "Review and refine until quality plateaus"},
      {"label": "Generate/explore", "description": "Brainstorm or explore for a fixed number of iterations"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Determine Configuration

Apply opinionated defaults based on task type:

| Task Type | Completion | check_before | min_iterations | output_parse |
|-----------|------------|--------------|----------------|--------------|
| Implementation | `beads-empty` | `true` | - | - |
| Refinement | `plateau` | `false` | `2` | `plateau:PLATEAU reasoning:REASONING` |
| Brainstorming/exploration | `fixed-n` | `false` | - | - |

**Always use:**
- `model: opus` (unless user requests otherwise)
- `delay: 3` (prevents rate limiting)

## Step 3: Create Directory

```bash
mkdir -p scripts/loops/{name}
```

## Step 4: Write loop.yaml

Create the configuration file:

```bash
cat > scripts/loops/{name}/loop.yaml << 'EOF'
# {Name} - {Brief description}
# {When to stop explanation}

name: {name}
description: {One sentence description}
completion: {strategy}
{additional fields based on strategy}
delay: 3
EOF
```

### Configuration by Strategy

**For beads-empty:**
```yaml
name: {name}
description: {description}
completion: beads-empty
check_before: true
delay: 3
```

**For plateau:**
```yaml
name: {name}
description: {description}
completion: plateau
min_iterations: 2
delay: 3
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

**For fixed-n:**
```yaml
name: {name}
description: {description}
completion: fixed-n
delay: 3
```

## Step 5: Write prompt.md

Create the agent prompt. Structure depends on completion strategy.

### Template for beads-empty loops

```markdown
# {Agent Name}

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}

## Context

Read the progress file for accumulated learnings:
```bash
cat ${PROGRESS_FILE}
```

## Available Work

List tasks for this session:
```bash
bd ready --label=loop/${SESSION_NAME}
```

## Workflow

1. **Choose next task** based on dependencies and what's already done
2. **Claim it**: `bd update <id> --status=in_progress`
3. **Read details**: `bd show <id>`
4. **Implement** the task
5. **Verify** (run tests/build if specified in progress file)
6. **Commit** with descriptive message
7. **Close**: `bd close <id>`
8. **Update progress file** with learnings

## Stop Condition

Check remaining work:
```bash
bd ready --label=loop/${SESSION_NAME}
```

If empty:
```
<promise>COMPLETE</promise>
```
```

### Template for plateau loops

```markdown
# {Agent Name}

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

## Context

Read the progress file:
```bash
cat ${PROGRESS_FILE}
```

## Your Task

{Describe what the agent should review/improve}

## Workflow

1. **Load** the target document(s)
2. **Review** critically against these criteria:
   - {Criterion 1}
   - {Criterion 2}
   - {Criterion 3}
3. **Make improvements** directly to the document
4. **Update progress file** with changes made

## Plateau Decision

At the END of your response:

```
PLATEAU: true/false
REASONING: [Your explanation]
```

**Say true if:**
- Remaining issues are cosmetic
- Finding the same issues repeatedly
- Document is ready for next phase

**Say false if:**
- Found significant gaps
- Made substantial changes
- Not confident in quality
```

### Template for fixed-n loops

```markdown
# {Agent Name}

Session: ${SESSION_NAME}
Iteration: ${ITERATION}

## Context

Read previous iterations:
```bash
cat ${PROGRESS_FILE}
```

## Your Task

{Describe what to generate/explore this iteration}

Focus on: {what makes this iteration unique}

## Output

{Where/how to capture output}

Append to progress file:
```
## Iteration ${ITERATION}
- {What was produced}
```
```

## Step 6: Verify Configuration

**Spawn verification subagent** using the protocol in SKILL.md.

Pass the path: `scripts/loops/{name}/`

Wait for validation report. If issues found, fix them.

## Step 7: Confirm to User

```
Stage created: scripts/loops/{name}/
- loop.yaml: {completion strategy} completion
- prompt.md: Agent instructions

To run this stage, use the sessions skill:
  /loop-agents:sessions → Start Session → Single-stage

Or run directly in tmux:
  tmux new-session -d -s "loop-{session}" -c "$(pwd)" \
    "./scripts/run.sh {name} {session} {max-iterations}"

Example:
  tmux new-session -d -s "loop-my-session" -c "$(pwd)" \
    "./scripts/run.sh {name} my-session 25"

Session files will be created at:
  .claude/pipeline-runs/{session}/
  ├── state.json              # Iteration tracking + crash recovery
  └── progress-{session}.md   # Accumulated context

IMPORTANT: Always run in tmux for background execution. Running directly
in your terminal will block until completion and won't persist if you
disconnect.
```

## Success Criteria

- [ ] Directory created at `scripts/loops/{name}/`
- [ ] `loop.yaml` has all required fields
- [ ] `prompt.md` matches completion strategy requirements
- [ ] Verification passed
- [ ] User informed how to run the loop
