---
description: Start a Ralph loop in less than ~15 seconds. Uses 'beads' for task management.
---

# /ralph

The easiest way to start an autonomous agent pipeline. Ask two questions, start working.

## When Invoked

Ask the user these two questions, then start the pipeline:

### Question 1: Where are your tasks?

Ask: **"Where are your tasks?"**

Options:
- **Beads label** (default) - Tasks in beads with a specific label (e.g., `pipeline/auth`)
- **Ready beads** - All ready beads (`bd ready`)
- **File** - A markdown file with a task list

If they choose beads label, ask for the label name. Default to `pipeline/{something}` format.

### Question 2: How many iterations?

Ask: **"How many iterations maximum?"**

Options:
- **10** - Quick run
- **25** - Standard (recommended)
- **50** - Long running
- **Custom** - Let them specify

## Starting the Pipeline

Once you have answers:

1. **Verify tasks exist:**
```bash
# For beads:
bd ready --label={label}

# For file:
cat {file} | head -10
```

2. **Derive session name** from the label or file (e.g., `pipeline/auth` → `auth`, `tasks/feature.md` → `feature`)

3. **Show Pre-Launch Summary and ask for confirmation:**

Display exactly what will run, then use AskUserQuestion:

```
## Pre-Launch Summary

Pipeline: ralph (work loop)
Session: {session}
Provider: claude (opus)
Termination: fixed ({iterations} max iterations)

Tasks found:
  • {count} beads ready with label '{label}'
  • First 3: {bead1}, {bead2}, {bead3}

What will happen:
  • Fresh agent spawned each iteration
  • Works through beads until queue empty or max reached
  • Progress saved to .claude/pipeline-runs/{session}/
```

```json
{
  "questions": [{
    "question": "Ready to launch this pipeline?",
    "header": "Confirm",
    "options": [
      {"label": "Launch", "description": "Start the pipeline now"},
      {"label": "Edit Config", "description": "Change provider, model, or add context"},
      {"label": "Cancel", "description": "Don't start, return to conversation"}
    ],
    "multiSelect": false
  }]
}
```

**If "Launch":** Proceed to step 4
**If "Edit Config":** Ask what to change (provider, model, context, inputs)
**If "Cancel":** Abort and confirm cancellation

4. **Start the work pipeline:**
```bash
./scripts/run.sh ralph {session} {iterations}
```

5. **Confirm to user:**
```
Started pipeline '{session}' with max {iterations} iterations.

Monitor: /sessions status {session}
Attach:  tmux attach -t pipeline-{session}
Stop:    /sessions kill {session}
```

## Examples

**User:** `/ralph`
**Assistant:** "Where are your tasks?"
**User:** "Beads labeled pipeline/auth"
**Assistant:** "How many iterations?"
**User:** "25"
**Assistant:** *runs `./scripts/run.sh ralph auth 25`* "Started pipeline 'auth'..."

**User:** `/ralph`
**Assistant:** "Where are your tasks?"
**User:** "All ready beads"
**Assistant:** *checks `bd ready`* "Found 8 ready beads. How many iterations?"
**User:** "10"
**Assistant:** *runs `./scripts/run.sh ralph default 10`* "Started pipeline 'default'..."

## Advanced Options

You can override provider, model, context, and pass initial inputs:

### Provider and Model

```bash
# Use Codex instead of Claude
./scripts/run.sh ralph {session} {iterations} --provider=codex

# Use specific model
./scripts/run.sh ralph {session} {iterations} --model=opus
./scripts/run.sh ralph {session} {iterations} --model=o3

# Both
./scripts/run.sh ralph {session} {iterations} --provider=codex --model=gpt-5.2-codex
```

### Context Injection

Inject custom instructions into the prompt:

```bash
./scripts/run.sh ralph {session} {iterations} --context="Focus on authentication bugs only"
./scripts/run.sh ralph {session} {iterations} --context="Read docs/plan.md before starting"
```

### Initial Inputs

Pass files to read before starting:

```bash
# Single file
./scripts/run.sh ralph {session} {iterations} --input docs/plan.md

# Multiple files
./scripts/run.sh ralph {session} {iterations} \
  --input docs/plan.md \
  --input docs/requirements.md
```

### Commands Passthrough

If configured in `stage.yaml`, agents will use project-specific validation commands from `context.json`:

```json
{
  "commands": {
    "test": "bundle exec rspec",
    "lint": "bundle exec rubocop"
  }
}
```

Agents read these via:
```bash
TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
```
