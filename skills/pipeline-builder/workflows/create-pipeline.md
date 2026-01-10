# Workflow: Create Pipeline

Create a multi-stage pipeline that chains loops together.

## Prerequisites

Read these first:
- `references/pipeline-config.md` - Pipeline structure
- `references/template-variables.md` - Variables for stage inputs
- `references/completion-strategies.md` - Strategy selection

## Step 1: Gather Requirements

**Use your judgment.** Determine:

1. **Pipeline name** - Short, descriptive (e.g., `full-refine`, `deep-analysis`)
2. **Stages** - What phases does this workflow have?
3. **Stage dependencies** - Does each stage use outputs from previous?

**If unclear, ask:**
```json
{
  "questions": [{
    "question": "What stages should this pipeline have?",
    "header": "Stages",
    "options": [
      {"label": "Plan → Beads", "description": "Improve plan, then refine beads"},
      {"label": "Multi-perspective", "description": "Same loop from different perspectives, then synthesize"},
      {"label": "Sequential loops", "description": "Run different loop types in sequence"},
      {"label": "Custom", "description": "I'll describe the stages"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: Check Existing Loops

List available loops the pipeline can use:

```bash
ls scripts/loops/
```

For each stage, determine:
- Use existing loop? → reference by name
- Need new loop? → create it first (use `workflows/create-loop.md`)
- One-off stage? → use inline prompt

## Step 3: Design Stage Configuration

For each stage, determine:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Stage identifier (used in `${INPUTS.name}`) |
| `loop` | If using existing | References `scripts/loops/{loop}/` |
| `runs` | Yes | Number of iterations |
| `prompt` | If inline | Custom prompt for one-off stages |
| `completion` | If inline | Required for inline prompts |
| `model` | Optional | Override default model |
| `perspectives` | Optional | Array for fan-out runs |

## Step 4: Create Pipeline File

```bash
cat > scripts/pipelines/{name}.yaml << 'EOF'
# {Name} Pipeline
# {Description of what this accomplishes}

name: {name}
description: {One sentence description}

stages:
  - name: {stage-1-name}
    loop: {loop-name}
    runs: {count}

  - name: {stage-2-name}
    loop: {loop-name}
    runs: {count}
EOF
```

### Common Patterns

**Two-stage refinement:**
```yaml
name: refine
description: Improve plan then refine beads

stages:
  - name: improve-plan
    loop: improve-plan
    runs: 5

  - name: refine-beads
    loop: refine-beads
    runs: 5
```

**Multi-perspective with synthesis:**
```yaml
name: multi-review
description: Review from multiple perspectives then synthesize

stages:
  - name: perspectives
    loop: code-review
    runs: 3
    perspectives:
      - "security engineer"
      - "performance engineer"
      - "UX designer"

  - name: synthesize
    runs: 1
    prompt: |
      Reviews from different perspectives:
      ${INPUTS}

      Create unified improvement plan.
      Write to: ${OUTPUT}
    completion: fixed-n
```

**Sequential with stage references:**
```yaml
name: full-workflow
description: Plan, implement, verify

stages:
  - name: planning
    loop: improve-plan
    runs: 3

  - name: implementation
    loop: work
    runs: 25

  - name: review
    runs: 1
    prompt: |
      Planning decisions:
      ${INPUTS.planning}

      Implementation results:
      ${INPUTS.implementation}

      Verify implementation matches plan.
      Write report to: ${OUTPUT}
    completion: fixed-n
```

## Step 5: Validate Loop References

For each stage that references a loop:

```bash
# Check loop exists
test -d scripts/loops/{loop-name} && echo "OK: {loop-name}" || echo "MISSING: {loop-name}"
```

If any loops are missing, create them using `workflows/create-loop.md`.

## Step 6: Verify Variable Flow

Check that stages properly reference each other:

1. First stage cannot use `${INPUTS}` (nothing before it)
2. Later stages can use:
   - `${INPUTS}` - previous stage
   - `${INPUTS.stage-name}` - named stage

**Verify stage names match references:**
```bash
# Extract stage names from pipeline
grep "name:" scripts/pipelines/{name}.yaml

# Check for ${INPUTS.xxx} references
grep -o '\${INPUTS\.[^}]*}' scripts/pipelines/{name}.yaml
```

## Step 7: Verify Configuration

**Spawn verification subagent** using the protocol in SKILL.md.

Pass the path: `scripts/pipelines/{name}.yaml`

Wait for validation report. If issues found, fix them.

## Step 8: Confirm to User

```
Pipeline created: scripts/pipelines/{name}.yaml

Stages:
1. {stage-1-name}: {loop} x{runs}
2. {stage-2-name}: {loop} x{runs}
...

To run:
./scripts/run.sh pipeline {name}.yaml {session-name}

Example:
./scripts/run.sh pipeline {name}.yaml my-session
```

## Success Criteria

- [ ] Pipeline file created at `scripts/pipelines/{name}.yaml`
- [ ] All referenced loops exist
- [ ] Variable flow is correct (no invalid ${INPUTS.xxx} references)
- [ ] Inline stages have `completion` specified
- [ ] Verification passed
- [ ] User informed how to run the pipeline
