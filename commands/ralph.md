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

1. **Tell the user what's about to happen:**
```
I'm going to spawn an autonomous agent in a tmux session. It will work through your tasks independently.
```

2. **Verify tasks exist:**
```bash
# For beads:
bd ready --label={label} | head -5

# For file:
cat {file} | head -10
```

3. **Derive session name** from the label or file (e.g., `pipeline/auth` → `auth`, `tasks/feature.md` → `feature`)

4. **Start the work pipeline:**
```bash
./scripts/run.sh work {session} {iterations}
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
**Assistant:** *runs `./scripts/run.sh work auth 25`* "Started pipeline 'auth'..."

**User:** `/ralph`
**Assistant:** "Where are your tasks?"
**User:** "All ready beads"
**Assistant:** *checks `bd ready`* "Found 8 ready beads. How many iterations?"
**User:** "10"
**Assistant:** *runs `./scripts/run.sh work default 10`* "Started pipeline 'default'..."
