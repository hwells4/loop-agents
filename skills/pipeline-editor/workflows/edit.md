# Workflow: Edit & Explore

Work with existing stage and pipeline configurations. Edit them, answer questions about them, help users explore options.

## Philosophy

**Use your intelligence.** This is not a checklist task.

The conversation will tell you what's needed. Sometimes you're editing. Sometimes you're answering questions. Sometimes you're helping someone think through options. Respond to what's actually happening.

## Investigation First

Before doing anything, understand what exists:

```bash
# See what stages exist
ls scripts/stages/

# See what pipelines exist
ls scripts/pipelines/*.yaml

# Read a stage's config
cat scripts/stages/{stage}/stage.yaml
cat scripts/stages/{stage}/prompt.md

# Read a pipeline's config
cat scripts/pipelines/{name}.yaml
```

**Always read the actual files.** Don't guess what's in them.

## When Editing

If the user wants to change something:

1. **Understand what they want** - Parse their request. If unclear, ask, but try to infer first.

2. **Show what exists** - Read the file, show the relevant section.

3. **Propose the change** - Clear before/after. Explain why this achieves what they asked.

4. **Wait for confirmation** - Don't edit until they say yes.

5. **Execute and validate** - Make the change, run lint, show the result.

Example flow:
```
User: "Make elegance use opus"

You: [Read stage.yaml]
     Currently elegance uses sonnet. I'll change it to opus:

     model: sonnet → model: opus

     Want me to make this change?

User: yes

You: [Edit file, run lint]
     Done. Elegance now uses opus. Lint passed.
```

## When Answering Questions

If the user asks about configuration:

1. **Investigate** - Read the actual files.

2. **Answer directly** - Give specific information from the files.

3. **Offer changes if relevant** - "Would you like me to change this?"

Example:
```
User: "What termination does work use?"

You: [Read stage.yaml]
     Work uses queue termination - it checks `bd ready` and stops
     when the bead queue is empty. There's no consensus requirement;
     it just runs until there's no more work.

     Want me to show you how it's configured?
```

## When Exploring

If the user is thinking through options:

1. **Probe their thinking** - Ask about their specific situation.
   - "What's happening that makes you think judgment isn't working?"
   - "Are you seeing false positives or false negatives?"

2. **Show real examples** - Point to actual configurations.
   - "The elegance stage uses judgment with consensus: 2. Here's how it's set up..."

3. **Help them reason** - Don't just list options. Help them think through implications.
   - "If you increase consensus to 3, you'll get fewer false stops but might run longer than needed."

4. **Offer to implement** - When they've decided, offer to make the change.

## Handling Ambiguity

When the user's request could mean multiple things:

**Bad:** Ask a menu question
**Good:** Make your best inference and check

```
User: "Make work faster"

You: I can reduce the delay between iterations from 3s to 1s,
     which will make it cycle faster. Or did you mean something
     else by "faster"?
```

## Validation

After any edit, validate:

```bash
./scripts/run.sh lint loop {stage}
# or
./scripts/run.sh lint pipeline {name}.yaml
```

If it fails, fix and re-validate before reporting success.

## Success

You succeeded if:
- You responded to what the user actually wanted
- You investigated before acting
- For edits: you got confirmation and validated
- For questions: you gave accurate, specific answers
- You used your judgment, not a checklist
