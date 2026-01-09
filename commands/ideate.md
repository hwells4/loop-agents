---
description: Generate creative improvement ideas for the project
---

# /ideate Command

**Idea generation:** Run the Idea Wizard to generate and evaluate improvement ideas.

## Usage

```
/ideate                  # Generate ideas for current project
/ideate 3                # Run 3 iterations for more diverse ideas
```

---

## Plugin Path

```
.claude/loop-agents/scripts/loop-engine/run.sh idea-wizard [session] [iterations]
```

---

## What This Does

The Idea Wizard generates improvement ideas across multiple dimensions:

1. **Brainstorm 20-30 ideas** covering:
   - User experience & delight
   - Performance & efficiency
   - Reliability & robustness
   - Simplicity (what to remove)
   - Missing features
   - Developer experience

2. **Evaluate each idea:**
   - Impact (1-5)
   - Effort (1-5)
   - Risk (1-5)

3. **Winnow to top 5** with full rationale

4. **Save to `docs/ideas.md`** (appends, doesn't overwrite)

---

## Execution

### Check Context First

```bash
# Check for existing plans
ls docs/plans/*.md 2>/dev/null

# Check for existing ideas
cat docs/ideas.md 2>/dev/null | head -20

# Check for beads
bd list --status=open 2>/dev/null | head -5
```

### Ask About Scope

```yaml
question: "What should I focus ideas on?"
header: "Focus"
options:
  - label: "Whole project"
    description: "Generate ideas for everything"
  - label: "Specific plan"
    description: "Focus on a plan in docs/plans/"
  - label: "Current beads"
    description: "Ideas related to open tasks"
```

### Launch

```bash
PLUGIN_DIR=".claude/loop-agents"
SESSION_NAME="ideate-$(date +%Y%m%d)"

$PLUGIN_DIR/scripts/loop-engine/run.sh idea-wizard $SESSION_NAME 1
```

**For multiple iterations** (more diverse ideas):
```bash
$PLUGIN_DIR/scripts/loop-engine/run.sh idea-wizard $SESSION_NAME 3
```

Each iteration reads previous ideas from `docs/ideas.md` to avoid duplicates.

---

## Output

Ideas are saved to `docs/ideas.md`:

```markdown
## Ideas from {session} - Iteration {N}

### 1. [Idea Title]
**Problem:** What pain point this addresses
**Solution:** Concrete approach
**Why now:** Why this is the right time
**Impact:** High | Effort: Low | Risk: Low

### 2. [Another Idea]
...
```

---

## After Ideation

```yaml
question: "Ideas generated. What next?"
header: "Next"
options:
  - label: "Incorporate into plan"
    description: "Run /refine to add best ideas to plan"
  - label: "Create beads"
    description: "Turn ideas into tasks with /loop-agents:create-tasks"
  - label: "Generate more"
    description: "Run another ideation pass"
```

---

## When to Use

- **Before planning:** Generate ideas before writing a PRD
- **Between refine passes:** Inject fresh thinking into refinement
- **When stuck:** Get new perspectives on a problem
- **For brainstorming:** Rapid idea generation with evaluation
