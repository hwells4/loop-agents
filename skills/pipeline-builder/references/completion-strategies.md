# Completion Strategies Reference

Completion strategies determine when a loop stops running. Choose based on what "done" means for your use case.

## Strategy Overview

| Strategy | Stops When | Best For |
|----------|------------|----------|
| `beads-empty` | All beads/tasks are complete | Implementation, task-driven work |
| `plateau` | Two agents agree quality plateaued | Refinement, review, planning |
| `fixed-n` | After exactly N iterations | Brainstorming, exploration |

## beads-empty

**Use when:** You have a discrete set of tasks (beads) to complete.

**How it works:**
1. Before each iteration, checks `bd ready --label=loop/{session}`
2. If no beads remain, stops
3. Otherwise, continues

**Configuration:**
```yaml
completion: beads-empty
check_before: true  # Check BEFORE iteration, not after
```

**Prompt requirements:**
- Must use `bd` commands to claim and close beads
- Should include stop condition check

**Example prompt section:**
```markdown
## Stop Condition

Check if work remains:
```bash
bd ready --label=loop/${SESSION_NAME}
```

If no stories returned, output:
```
<promise>COMPLETE</promise>
```
```

## plateau

**Use when:** Quality improvement should continue until diminishing returns.

**How it works:**
1. Each agent outputs `PLATEAU: true/false`
2. Requires **TWO consecutive** agents to say `true`
3. Single agent can't prematurely stop the loop
4. Prevents blind spots from any one agent

**Configuration:**
```yaml
completion: plateau
min_iterations: 2           # Don't check until at least 2 iterations
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

**Prompt requirements:**
- Must instruct agent to output structured decision
- Should explain criteria for plateau judgment

**Required prompt section:**
```markdown
## Plateau Decision

At the END of your response:

```
PLATEAU: true/false
REASONING: [Your reasoning]
```

**Say true (stop) if:**
- Changes are cosmetic, not substantive
- Finding same issues repeatedly
- Document is ready for next phase

**Say false (continue) if:**
- Found significant gaps or errors
- Made substantial changes that need review
- Not confident in current quality
```

**Why two-agent consensus?**
```
Agent 1: PLATEAU: true  (thinks it's done)
Agent 2: PLATEAU: false (finds issues) → counter resets
Agent 3: PLATEAU: true  (fixes issues, thinks done)
Agent 4: PLATEAU: true  (confirms) → STOPS
```

## fixed-n

**Use when:** You want exactly N iterations regardless of output.

**How it works:**
1. Runs for exactly `max_iterations` specified at launch
2. No early stopping
3. No completion checks needed

**Configuration:**
```yaml
completion: fixed-n
```

**Prompt requirements:**
- No special output format needed
- Each iteration should produce distinct value

**Use cases:**
- Brainstorming (want diverse ideas across iterations)
- Batch processing with known count
- Time-boxed exploration

## Choosing the Right Strategy

### Decision Tree

1. **Do you have discrete tasks/beads?**
   - Yes → `beads-empty`
   - No → continue

2. **Is quality subjective and iterative?**
   - Yes → `plateau`
   - No → `fixed-n`

### Common Patterns

| Loop Type | Strategy | Why |
|-----------|----------|-----|
| Work/implementation | `beads-empty` | Clear "done" = all tasks complete |
| Plan improvement | `plateau` | Quality plateaus, not binary done |
| Bead refinement | `plateau` | Same as plan improvement |
| Idea generation | `fixed-n` | Want N diverse perspectives |
| Code review | `plateau` | Stop when no new issues found |
| Bug hunting | `plateau` | Stop when no new bugs found |
| Batch file processing | `beads-empty` | Create a bead per file, process until done |

## Strategy-Specific Tips

### beads-empty
- Use `check_before: true` to avoid running when already done
- Make sure beads are properly tagged with `loop/{session}`
- For batch processing, create beads from your list first

### plateau
- Set `min_iterations: 2` minimum (need 2 agents to compare)
- Higher min (3-4) for complex refinement
- Be explicit about plateau criteria in prompt

### fixed-n
- Choose N based on desired diversity vs. cost
- 3-5 iterations for quick exploration
- 8-10 for thorough analysis
