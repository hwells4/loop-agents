# Workflow: Edit Existing Loop or Pipeline

Modify an existing loop or pipeline configuration.

## Step 1: Identify Target

Ask what to edit if not specified:

```json
{
  "questions": [{
    "question": "What would you like to edit?",
    "header": "Target",
    "options": [
      {"label": "Loop", "description": "Edit a loop's configuration or prompt"},
      {"label": "Pipeline", "description": "Edit a pipeline's stages or configuration"}
    ],
    "multiSelect": false
  }]
}
```

## Step 2: List Available Targets

**For loops:**
```bash
echo "Available loops:"
ls scripts/loops/
```

**For pipelines:**
```bash
echo "Available pipelines:"
ls scripts/pipelines/*.yaml 2>/dev/null | xargs -I {} basename {}
```

## Step 3: Read Current Configuration

**For loops:**
```bash
# Read config
cat scripts/loops/{name}/loop.yaml

# Read prompt
cat scripts/loops/{name}/prompt.md
```

**For pipelines:**
```bash
cat scripts/pipelines/{name}.yaml
```

## Step 4: Understand Requested Changes

Common edit types:

| Change Type | What to Modify |
|-------------|----------------|
| Completion strategy | `loop.yaml` completion field |
| Prompt behavior | `prompt.md` content |
| Model selection | `loop.yaml` model field |
| Iteration count | Pipeline stage `runs` field |
| Add/remove stage | Pipeline `stages` array |
| Stage order | Pipeline stage positions |
| Variable usage | Prompt template variables |

## Step 5: Make Changes

### Editing loop.yaml

Use Edit tool to modify specific fields:

```
# Example: Change completion strategy
Edit scripts/loops/{name}/loop.yaml
- completion: fixed-n
+ completion: plateau
+ min_iterations: 2
+ output_parse: "plateau:PLATEAU reasoning:REASONING"
```

### Editing prompt.md

Use Edit tool for prompt changes. Remember:
- If changing to plateau, add PLATEAU output section
- If changing to beads-empty, add stop condition check
- Update template variables as needed

### Editing Pipeline

Use Edit tool for pipeline changes:

```
# Example: Add a stage
stages:
  - name: existing-stage
    ...
+
+  - name: new-stage
+    loop: some-loop
+    runs: 3
```

## Step 6: Verify After Changes

**Always run verification** after any edit.

Spawn verification subagent with:
- Loop: `scripts/loops/{name}/`
- Pipeline: `scripts/pipelines/{name}.yaml`

## Step 7: Check for Breaking Changes

If you changed:

**Completion strategy:**
- Prompt may need updating (plateau needs PLATEAU output)
- Configuration may need new fields (min_iterations, output_parse)

**Template variables:**
- Verify all ${VARIABLES} are valid
- Check pipeline stage references still work

**Stage names:**
- Update any `${INPUTS.old-name}` references to new names

## Step 8: Confirm Changes

Show diff of what changed:

```
Changes made to scripts/loops/{name}/:

loop.yaml:
- completion: fixed-n
+ completion: plateau

prompt.md:
+ Added plateau decision section

Verification: PASSED
```

## Common Edit Scenarios

### Change Model

```yaml
# Before
name: my-loop

# After
name: my-loop
model: sonnet  # or opus, haiku
```

### Add Minimum Iterations to Plateau

```yaml
# Before
completion: plateau

# After
completion: plateau
min_iterations: 3  # Require at least 3 iterations before checking
```

### Change Pipeline Stage Count

```yaml
# Before
- name: improve-plan
  loop: improve-plan
  runs: 3

# After
- name: improve-plan
  loop: improve-plan
  runs: 5
```

### Add Stage to Pipeline

```yaml
stages:
  - name: existing
    loop: work
    runs: 10

  # Add new stage
  - name: review
    runs: 1
    prompt: |
      Review the work from previous stage:
      ${INPUTS}

      Write summary to: ${OUTPUT}
    completion: fixed-n
```

### Remove Stage from Pipeline

Simply delete the stage block. Update any `${INPUTS.removed-stage}` references.

## Success Criteria

- [ ] Changes applied correctly
- [ ] No syntax errors in YAML
- [ ] Prompt matches completion strategy requirements
- [ ] Variable references are valid
- [ ] Verification passed
- [ ] User informed of changes made
