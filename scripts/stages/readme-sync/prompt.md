# README Sync

Read context from: ${CTX}
Progress file: ${PROGRESS}
Output file: ${OUTPUT_PATH}
Status file: ${STATUS}
Iteration: ${ITERATION}

OK, we have made tons of recent changes that aren't yet reflected in the README file. First, reread AGENTS dot md so it's still fresh in your mind. Use ultrathink. Now, we need to revise the README for these changes (don't write about them as'changes' however, make it read like it was always like that, since we don't have any users yet!).  

## Your Task

Analyze the codebase and update README.md to reflect current functionality. Find implemented features that are missing, under-documented, under-explained, or under-justified in the README.

### Step 1: Gather Context

```bash
cat ${PROGRESS}
```

Read CLAUDE.md or AGENTS.md for authoritative codebase context:
```bash
cat CLAUDE.md 2>/dev/null || cat AGENTS.md 2>/dev/null || echo "No agent docs"
```

Read current README:
```bash
cat README.md
```

### Step 2: Explore the Codebase

Use your context window for breadth - scan directory structures:
```bash
find . -type f -name "*.yaml" -o -name "*.md" -o -name "*.sh" | head -50
ls -la scripts/stages/
ls -la scripts/lib/
ls -la commands/
ls -la skills/
```

Use subagents for depth - spawn Task agents to explore specific areas that need investigation. For example:
- "Explore scripts/lib/ and summarize what each utility does"
- "Analyze all stage types and their termination strategies"
- "Document the pipeline configuration schema"

### Step 3: Compare Code vs README

For each implemented feature, check:
1. Is it mentioned in README?
2. Is documentation accurate and current?
3. Is there enough detail for new users?
4. Are there usage examples?
5. Is there rationale (why it's useful, not just what it does)?

Look for:
- **Missing** - Implemented but not documented
- **Outdated** - README says X, code does Y
- **Under-explained** - Mentioned but lacks detail
- **Under-justified** - What but not why

### Step 4:  Now with that context, what else can we put in there to make the README longer and more detailed about what we built, why it's useful, how it works, the algorithms/design principles used, etc? This should be incremental NEW content, not replacement for what is there already.  

### Step 5: Update README Directly

Make actual edits to README.md. Write as if features were always there (not "we added X" or "recent changes"). Add:
- Clear descriptions
- Usage examples
- Why it's useful
- How it connects to other features
- Design principles and algorithms where relevant

Make the README longer and more detailed. Cover:
- What we built
- Why it's useful
- How it works
- Design principles used
- Algorithms (like plateau detection)

### Step 5: Document What You Changed

Write to ${OUTPUT_PATH}:

```markdown
## README Sync - Iteration ${ITERATION}

### Sections Updated
- [List sections you added or modified]

### Key Additions
- [Notable new content]
```

### Step 6: Write Status

Write to `${STATUS}`:

```json
{
  "decision": "stop",
  "reason": "Updated README in iteration ${ITERATION}",
  "summary": "What sections you updated",
  "work": {"items_completed": [], "files_touched": ["README.md", "${OUTPUT_PATH}"]},
  "errors": []
}
```

## Guidelines

- CLAUDE.md is the source of truth - README should reflect it
- Write documentation users would actually want to read
- Be concise but complete
- Include real examples, not placeholders
- Explain the "why" not just the "what"
