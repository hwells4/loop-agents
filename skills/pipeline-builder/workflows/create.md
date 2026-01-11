# Workflow: Create Pipeline

Create a pipeline based on what the user wants to accomplish.

> **Be an agent, not a wizard.** Infer what's needed, propose a plan, execute end-to-end, validate, confirm.

## Philosophy

**Don't interrogate the user.** They said what they want. Your job is to:
1. Understand the goal
2. Decide how many stages and what completion strategy
3. Propose your plan in one clear message
4. Get confirmation (or adjustments)
5. Create everything
6. Validate with linter
7. Show where everything lives and how to run it

## Step 1: Analyze the Request

Read what the user wants and determine:

| Question | How to Decide |
|----------|---------------|
| **Completion strategy** | Implementation/tasks → `beads-empty`. Refinement/review → `plateau`. Exploration/brainstorm → `fixed-n` |
| **Number of stages** | Most things are single-stage. Multi-stage only if there are distinct phases (e.g., plan then implement, analyze then synthesize) |
| **Use existing stages?** | Check `ls scripts/loops/` - reuse if it fits |
| **Output location** | Must go somewhere tracked (not just progress file). Determine based on purpose |

## Step 2: Propose the Plan

Present your decision in ONE message. Be specific:

```
Based on what you described, here's my plan:

**Pipeline: {name}**
- Stages: {N}
- Completion: {strategy} ({why})

**Stage 1: {name}**
- Purpose: {what it does each iteration}
- Stops when: {completion condition}
- Output: {where results go - must be a tracked file/directory}

[If multi-stage]
**Stage 2: {name}**
- Purpose: {what it does}
- Input: Results from Stage 1
- Output: {where results go}

Ready to create this? (Confirm / Adjust)
```

**Key points:**
- State WHERE outputs will be written (not just "progress file")
- If outputs go to gitignored locations only, that's wrong - add a tracked output location
- Be concrete about what each iteration does

## Step 3: Get Confirmation

Use AskUserQuestion only ONCE for confirmation:

```json
{
  "questions": [{
    "question": "Ready to create this pipeline?",
    "header": "Confirm",
    "options": [
      {"label": "Create it", "description": "Proceed with the plan above"},
      {"label": "Adjust", "description": "I want to change something"}
    ],
    "multiSelect": false
  }]
}
```

If they choose "Adjust", ask what they want to change, update the plan, confirm again.

## Step 4: Create Everything

Execute the full creation without stopping for questions.

### 4a. Create Stage Directories

For each new stage:
```bash
mkdir -p scripts/loops/{stage-name}
```

### 4b. Write Stage Configs

**loop.yaml for beads-empty:**
```yaml
name: {stage-name}
description: {One sentence}
completion: beads-empty
check_before: true
delay: 3
```

**loop.yaml for plateau:**
```yaml
name: {stage-name}
description: {One sentence}
completion: plateau
min_iterations: 2
delay: 3
output_parse: "plateau:PLATEAU reasoning:REASONING"
```

**loop.yaml for fixed-n:**
```yaml
name: {stage-name}
description: {One sentence}
completion: fixed-n
delay: 3
```

### 4c. Write Stage Prompts

Keep prompts **focused**. One task per iteration. Study existing prompts in `scripts/loops/*/prompt.md` for length and style.

**Critical: Define where outputs go.** Every prompt must specify:
- Progress file: `.claude/pipeline-runs/{session}/progress-{session}.md` (for iteration context)
- **Primary output:** A tracked location like `docs/`, `reports/`, or the files being modified

Example output section in prompt:
```markdown
## Output

Update the target files directly. After making changes:

1. Commit your changes with a descriptive message
2. Append a summary to the progress file:
   ```
   ## Iteration ${ITERATION}
   - Changed: [files]
   - Reason: [why]
   ```
```

### 4d. Write Pipeline Config (Multi-Stage Only)

```bash
cat > scripts/pipelines/{name}.yaml << 'EOF'
name: {name}
description: {What this accomplishes}

stages:
  - name: {stage-1}
    loop: {stage-type}
    runs: {max}

  - name: {stage-2}
    loop: {stage-type}
    runs: {max}
EOF
```

## Step 5: Validate

**Always run the linter.** Don't skip this.

```bash
# Validate each new stage
./scripts/run.sh lint loop {stage-name}

# Validate pipeline (multi-stage only)
./scripts/run.sh lint pipeline {pipeline-name}
```

**If lint fails:** Fix the errors immediately. Don't tell the user "it's ready" until lint passes.

**After lint passes:** Run dry-run to verify resolution:
```bash
./scripts/run.sh dry-run loop {stage-name} test-session
```

## Step 6: Confirm Completion

Show the user exactly what was created and how to use it:

```
Pipeline created and validated.

**Files created:**
- scripts/loops/{stage-name}/loop.yaml
- scripts/loops/{stage-name}/prompt.md
[- scripts/pipelines/{name}.yaml (multi-stage only)]

**Outputs will be written to:**
- {Primary output location - tracked in git}
- .claude/pipeline-runs/{session}/progress-{session}.md (iteration context)

**To run:**
Use `/loop-agents:sessions` → Start Session

Or directly:
```bash
tmux new-session -d -s "loop-{session}" -c "$(pwd)" \
  "./scripts/run.sh {stage-name} {session} {max}"
```

**To monitor:**
```bash
tmux attach -t loop-{session}
```
```

## Common Mistakes to Avoid

1. **Output only to progress file** - Progress file is for iteration context, not primary output. Always define a tracked output location.

2. **Bloated prompts** - If your prompt is 150+ lines with multiple sub-agent spawns, it's too complex. One clear task per iteration.

3. **Too many questions** - Don't ask the user about completion strategy, stage count, etc. Decide based on what they want.

4. **Skipping validation** - Always run lint. Always.

5. **Not showing output location** - User must know where to find results.

## Success Criteria

- [ ] Analyzed request and made decisions (didn't just ask user)
- [ ] Proposed plan with specific output locations
- [ ] Got single confirmation before creating
- [ ] Created all files end-to-end
- [ ] Ran linter and it passed
- [ ] Showed user exactly where files are and how to run
