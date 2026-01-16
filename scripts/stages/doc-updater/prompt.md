# Documentation Updater

You are updating documentation based on an audit of outdated/missing content.

${CONTEXT}

## Your Inputs

Read context from: `${CTX}`

```bash
# Get the audit document (list of things to fix)
AUDIT=$(jq -r '.inputs.from_initial[0] // empty' ${CTX})

# Get the feature reference (source of truth for accurate details)
FEATURE_REF=$(jq -r '.inputs.from_initial[1] // empty' ${CTX})
```

## Progress Tracking

Read the progress file to see what's already been completed:
```bash
cat ${PROGRESS}
```

Items marked with `✓ COMPLETED:` have already been done by previous iterations. **Do not redo them.**

## Your Task

Work through up to 3 items per iteration. After each item, check your context before continuing.

### Workflow

```
┌─────────────────────────────────────────┐
│ 1. Read audit + progress                │
│ 2. Pick ONE unclaimed HIGH priority item│
│ 3. Make the change                      │
│ 4. Mark it ✓ COMPLETED in progress      │
│ 5. Check: context still manageable?     │
│    YES → pick another item (up to 3)    │
│    NO  → stop, write result, next iter  │
└─────────────────────────────────────────┘
```

### For each item:
- Read the file that needs updating
- Read the feature reference for accurate details
- Make the recommended change
- For skills, look at existing `skills/*/SKILL.md` files in this repo for patterns
- Mark it complete in progress immediately

### Cap: 3 items per iteration
Even if you have context remaining after 3 items, stop and let the next iteration continue. This ensures fresh context for complex changes.

## Making Changes

When editing files:
- **CLAUDE.md**: Add missing sections, update examples, expand tables
- **Skills (SKILL.md)**: Follow the structure of existing skills in this repo
- **Stage prompts**: Add `${CONTEXT}` placeholders, input system guidance
- **Schema/reference docs**: Align with `docs/research/parallel-blocks-feature.md`

For skill editing, reference these patterns:
```bash
# See how existing skills are structured
ls skills/*/SKILL.md
cat skills/sessions/SKILL.md  # Good example of complete skill
```

## Progress File Format

After completing each item, append to ${PROGRESS}:

```markdown
## Iteration ${ITERATION}

✓ COMPLETED: path/to/file.md
  - What was changed: [brief description]

✓ COMPLETED: path/to/another.md
  - What was changed: [brief description]
```

## Write Result

After making your changes, write result to `${RESULT}` (set `signals.plateau_suspected` true when all audit items are complete and no gaps remain):

```json
{
  "summary": "Updated [files]. Remaining: [what's left]",
  "work": {
    "items_completed": ["file1.md", "file2.md"],
    "files_touched": ["path/to/file1.md", "path/to/file2.md"]
  },
  "artifacts": {
    "outputs": [],
    "paths": []
  },
  "signals": {
    "plateau_suspected": false,
    "risk": "low",
    "notes": ""
  }
}
```

## Important

- **Actually edit the files** - don't just report what should change
- **Be accurate** - use the feature reference as your source of truth
- **Don't duplicate work** - skip items marked ✓ COMPLETED in progress
- **Quality over quantity** - better to do 2 items well than 4 items poorly
