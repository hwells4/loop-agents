# Loop Configuration Reference

Every loop is a directory in `scripts/loops/{name}/` containing:
- `loop.yaml` - Configuration (required)
- `prompt.md` - Agent instructions (required)
- `prompts/*.md` - Alternative prompts (optional)

## loop.yaml Fields

### Required Fields

```yaml
name: my-loop
description: What this loop does in one sentence
completion: beads-empty  # Stopping strategy
```

### Optional Fields

```yaml
# Model selection (default: opus)
model: opus  # opus, sonnet, haiku

# Seconds between iterations (default: 3)
delay: 3

# Check completion before running iteration (default: false)
check_before: true

# For plateau strategy: minimum iterations before checking (default: 1)
min_iterations: 2

# Parse structured output from Claude's response
output_parse: "plateau:PLATEAU reasoning:REASONING"

# Alternative prompt file (default: prompt.md)
prompt: custom-prompt  # Uses prompts/custom-prompt.md

```

## Completion Strategies

| Strategy | Value | When to Use |
|----------|-------|-------------|
| Tasks until done | `beads-empty` | Implementation loops that work through beads |
| Quality plateaued | `plateau` | Refinement loops where 2 agents must agree |
| Fixed iterations | `fixed-n` | Brainstorming, exploration, batch processing |

## Output Parsing

For loops that need to extract structured data from Claude's output, use `output_parse`:

```yaml
output_parse: "fieldname:MARKER othername:OTHER"
```

This extracts lines like:
```
MARKER: some value
OTHER: another value
```

Into JSON for the state file:
```json
{"fieldname": "some value", "othername": "another value"}
```

**Required for plateau strategy:**
```yaml
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

The prompt must instruct the agent to output:
```
PLATEAU: true
REASONING: The plan is complete and ready for implementation
```

## Complete Examples

### Implementation Loop (beads-empty)

```yaml
name: work
description: Implement features from beads until done
completion: beads-empty
check_before: true
delay: 3
```

### Refinement Loop (plateau)

```yaml
name: improve-plan
description: Iteratively improve a plan document until quality plateaus
completion: plateau
min_iterations: 2
delay: 2
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

### Brainstorming Loop (fixed-n)

```yaml
name: idea-wizard
description: Generate improvement ideas
completion: fixed-n
delay: 3
```

