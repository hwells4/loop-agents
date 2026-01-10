---
name: create-loop
description: Create new loop agent types for the loop-engine. Scaffolds loop.yaml config and prompt.md files with the right completion strategy.
---

<essential_principles>

## CRITICAL: CLARIFY BEFORE BUILDING

**If you don't fully understand what the user wants, ask questions until you do.**

Don't assume. Don't guess. Don't start building until you're confident you understand the goal, the structure, and what success looks like.

---

**Loop types need two files:**
1. `loop.yaml` - Configuration (completion strategy, parsing, delays)
2. `prompt.md` - Instructions for the agent each iteration

**Completion strategies:**
- `beads-empty` - Stop when no beads remain (implementation)
- `plateau` - Stop when 2 agents agree it's done (refinement)
- `fixed-n` - Run exactly N iterations (batch)
- `all-items` - Iterate through item list (multi-perspective)

**Output location:** `scripts/loops/<name>/`

</essential_principles>

<intake>
If loop name provided as argument, use it. Otherwise ask:

```json
{
  "questions": [{
    "question": "What should this loop be called?",
    "header": "Loop Name",
    "options": [
      {"label": "scraper", "description": "Data extraction loop"},
      {"label": "writer", "description": "Content generation loop"},
      {"label": "tester", "description": "Test execution loop"}
    ],
    "multiSelect": false
  }]
}
```

Then ask about completion strategy:

```json
{
  "questions": [{
    "question": "How should this loop know when to stop?",
    "header": "Completion",
    "options": [
      {"label": "beads-empty", "description": "Stop when no beads remain for this session"},
      {"label": "plateau", "description": "Stop when 2 agents agree work is done"},
      {"label": "fixed-n", "description": "Run exactly N iterations"},
      {"label": "all-items", "description": "Iterate through a list of items"}
    ],
    "multiSelect": false
  }]
}
```

</intake>

<process>

## Step 1: Gather Requirements

Collect from user:
- Loop name (lowercase, hyphens ok)
- Completion strategy
- Description of what the loop does
- Whether output parsing is needed

## Step 2: Create Directory

```bash
mkdir -p scripts/loops/{name}
```

## Step 3: Generate loop.yaml

Based on completion strategy:

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
output_parse: plateau:PLATEAU
```

**For fixed-n:**
```yaml
name: {name}
description: {description}
completion: fixed-n
delay: 3
```

**For all-items:**
```yaml
name: {name}
description: {description}
completion: all-items
items: item1 item2 item3
delay: 3
```

## Step 4: Generate prompt.md

```markdown
# {Name} Agent

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}

## Your Task

{Task description from user}

## Workflow

1. Read progress file for context
2. {Main task steps}
3. Update progress file with learnings

## Output

{If plateau strategy:}
At the END, output:
```
PLATEAU: {true/false}
REASONING: {one sentence}
```

{If beads-empty:}
When all beads are complete, output:
```
<promise>COMPLETE</promise>
```
```

## Step 5: Show Next Steps

```
Created loop type: {name}

Files:
  scripts/loops/{name}/loop.yaml
  scripts/loops/{name}/prompt.md

Run it:
  .claude/loop-agents/scripts/loop-engine/run.sh {name} [session] [max]

Test first:
  .claude/loop-agents/scripts/loop-engine/run.sh {name} test 1
```

</process>

<templates>

## loop.yaml Reference

```yaml
name: myloop                 # Loop identifier
description: What it does    # Shown in run.sh help
completion: plateau          # beads-empty, plateau, fixed-n, all-items

# For plateau completion
min_iterations: 2            # Don't check before this many iterations

# For all-items completion
items: a b c                 # Space-separated list

# For beads-empty completion
check_before: true           # Check before iteration starts

# General
delay: 3                     # Seconds between iterations
output_parse: key:KEY        # Parse "KEY: value" from output
prompt: prompt               # Prompt file name (default: prompt)
```

## prompt.md Variables

Available substitutions:
- `${SESSION_NAME}` - Current session name
- `${PROGRESS_FILE}` - Path to progress file
- `${ITERATION}` - Current iteration number (1-indexed)

</templates>

<examples>

## Example: Data Scraper Loop

**loop.yaml:**
```yaml
name: scraper
description: Scrape data from configured sources
completion: beads-empty
check_before: true
delay: 5
```

**prompt.md:**
```markdown
# Scraper Agent

Session: ${SESSION_NAME}

## Task

1. Get next scraping task: `bd ready --label=loop/${SESSION_NAME}`
2. Claim it: `bd update <id> --status=in_progress`
3. Execute the scrape
4. Save results
5. Close task: `bd close <id>`

When no tasks remain, output:
<promise>COMPLETE</promise>
```

## Example: Content Refiner Loop

**loop.yaml:**
```yaml
name: refiner
description: Iteratively improve content quality
completion: plateau
min_iterations: 2
delay: 3
output_parse: plateau:PLATEAU
```

**prompt.md:**
```markdown
# Refiner Agent

Session: ${SESSION_NAME}
Iteration: ${ITERATION}

## Task

Review and improve the content in docs/draft.md.

## Output

PLATEAU: {true if content is publication-ready, false if more work needed}
REASONING: {brief explanation}
```

</examples>
