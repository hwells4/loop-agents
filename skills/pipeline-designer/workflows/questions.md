# Workflow: Answer Questions

Help users learn about the pipeline system. Answer questions, show examples, suggest next steps.

## Approach

When users ask questions about the pipeline system:

1. **Understand the question** - What are they trying to learn?
2. **Provide a clear answer** - Draw from V3 system knowledge
3. **Show relevant examples** - Point to existing configurations
4. **Suggest next steps** - Guide them toward relevant workflows

## Common Questions

### "What termination strategies are available?"

See `references/termination.md` for full details. Quick summary:

| Strategy | Use When | Agent Responsibility |
|----------|----------|---------------------|
| `queue` | External queue drives work (beads) | Engine checks `bd ready` |
| `judgment` | Quality plateau detection | Agent writes `decision: stop` |
| `fixed` | Exactly N iterations needed | Runs to completion |

**Examples:**
- `work` stage uses `queue` (stops when beads are done)
- `improve-plan` uses `judgment` (stops on consensus)
- `idea-wizard` uses `fixed` (runs exactly N times)

### "What variables can I use in prompts?"

See `references/v3-system.md` for full details. Key variables:

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to context.json with full metadata |
| `${STATUS}` | Path where agent writes status.json |
| `${PROGRESS}` | Path to progress file |
| `${ITERATION}` | Current iteration (1-based) |
| `${SESSION_NAME}` | Session identifier |

### "How do stages connect in multi-stage pipelines?"

Stages connect via inputs:

```yaml
stages:
  - name: plan-stage
    stage: improve-plan
    runs: 5

  - name: bead-stage
    stage: refine-tasks
    runs: 5
    inputs:
      from: plan-stage
```

The second stage reads outputs via `context.json`:

```bash
# In the prompt template for bead-stage
jq -r '.inputs.from_stage | to_entries[] | .value[]' ${CTX} | while read output_file; do
  cat "$output_file"
done
```

### "What makes a good prompt template?"

A good prompt has:

1. **Context section** - How to read `${CTX}` and `${PROGRESS}`
2. **Autonomy grant** - "This is not a checklist task. Trust your instincts."
3. **Guidance (not constraints)** - What to look for, how to approach
4. **Status template** - JSON format for `${STATUS}`

See `scripts/stages/elegance/prompt.md` for an exemplary template.

### "How do I run a dry-run?"

```bash
./scripts/run.sh dry-run loop {stage-name} preview
./scripts/run.sh dry-run pipeline {pipeline}.yaml preview
```

This shows what would happen without actually running.

### "What's the difference between a loop and a pipeline?"

A "loop" is a single-stage pipeline. They're the same thing internally.

- **Loop/Single-stage:** One stage running until termination
- **Pipeline/Multi-stage:** Multiple stages chained together

All sessions use the same engine (`scripts/engine.sh`) and state tracking.

## When to Redirect

If the question leads toward building something:
- "I want to create a..." → Redirect to build workflow
- "How do I edit..." → Redirect to edit workflow

```markdown
That's a great question! It sounds like you want to build something.
Would you like me to switch to the build workflow to help you design it?
```

## Showing Examples

Point users to existing configurations:

```bash
# Stage examples
cat scripts/stages/ralph/stage.yaml
cat scripts/stages/elegance/prompt.md

# Pipeline examples
cat scripts/pipelines/full-refine.yaml
```

## Next Steps

After answering, suggest relevant follow-ups:

```markdown
**Next steps:**
- `/pipeline` to design a new pipeline
- `/agent-pipelines:sessions` to run an existing one
- Explore `scripts/stages/` for more examples
```

## Success Criteria

- [ ] Question understood correctly
- [ ] Clear, accurate answer provided
- [ ] Relevant examples shown
- [ ] Next steps suggested
- [ ] User redirected if they want to build/edit
