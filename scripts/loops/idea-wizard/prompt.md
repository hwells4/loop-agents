# Idea Wizard

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

## Your Task

You are a creative product thinker. Generate fresh ideas to improve this project.

### Step 1: Gather Context

Read the progress file and any existing plans:
```bash
cat ${PROGRESS_FILE}
ls -la docs/*.md 2>/dev/null || echo "No docs yet"
```

Also check what ideas have already been generated:
```bash
cat docs/ideas.md 2>/dev/null || echo "No previous ideas"
```

### Step 2: Brainstorm

Think of 20-30 potential improvements across these dimensions:
- **User Experience:** How could this be more delightful?
- **Performance:** What could be faster or more efficient?
- **Reliability:** What could break? How to prevent it?
- **Simplicity:** What's overcomplicated? What could be removed?
- **Features:** What's missing that users would love?
- **Developer Experience:** What would make this easier to work with?

### Step 3: Evaluate & Winnow

For each idea, quickly assess:
- Impact (1-5): How much would this improve things?
- Effort (1-5): How hard to implement?
- Risk (1-5): How likely to cause problems?

Keep only ideas with high impact-to-effort ratio.

### Step 4: Output Top 5

Select your best 5 ideas. For each:
1. **Title:** Clear, actionable name
2. **Problem:** What pain point does this address?
3. **Solution:** Concrete approach
4. **Why now:** Why is this the right time?

### Step 5: Save Ideas

Append your top 5 to `docs/ideas.md`:
```bash
mkdir -p docs
```

Then write/append to the file with your ideas in this format:
```markdown
## Ideas from ${SESSION_NAME} - Iteration ${ITERATION}

### 1. [Title]
**Problem:** ...
**Solution:** ...
**Why now:** ...

### 2. [Title]
...
```

### Step 6: Update Progress

Append a summary to the progress file noting what ideas you generated.

## Important

- Read existing ideas first to avoid duplicates
- Be creative but practical
- Focus on high-impact, low-effort wins
- If this is iteration 2+, push yourself to think differently than before
