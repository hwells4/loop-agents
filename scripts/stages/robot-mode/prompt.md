# Robot Mode Planner

Read context from: ${CTX}
Progress file: ${PROGRESS}
Output file: ${OUTPUT_PATH}
Iteration: ${ITERATION}

## Your Task

Analyze existing code, CLIs, or plans and identify opportunities to make them more **agent-usable**. Output a prioritized list of improvements that would help coding agents interact with this system more effectively.

### Step 1: Gather Context

```bash
cat ${PROGRESS}
cat ${OUTPUT_PATH} 2>/dev/null || echo "First iteration"
```

Read the codebase, plans, or docs that need agent-usability analysis.

### Step 2: Agent Friction Points

Look for things that make agent interaction difficult:

- Verbose output that wastes tokens
- Human-oriented formatting (colors, spinners, ASCII art)
- Ambiguous command syntax
- Missing machine-readable output options
- Documentation that's hard to parse programmatically
- UI-only features with no CLI equivalent
- Inconsistent response formats
- Poor error messages for programmatic handling

### Step 3: Prioritize Improvements

For each friction point, assess:
- **Impact:** How much would this help agents? (1-5)
- **Frequency:** How often do agents hit this? (1-5)
- **Effort:** How hard to fix? (1-5)

Keep highest impact-to-effort ratio items.

### Step 4: Output Top 5 Improvements

For each improvement:
1. **Problem:** What's the agent friction?
2. **Solution:** How to make it agent-friendly
3. **Benefit:** What agents can do better after this

### Step 5: Save Output

Write to ${OUTPUT_PATH}:

```markdown
## Robot Mode Analysis - Iteration ${ITERATION}

### 1. [Improvement Title]
**Problem:** ...
**Solution:** ...
**Benefit:** ...

### 2. [Improvement Title]
...
```

### Step 6: Update Progress & Write Status

Append summary to progress file, then write to `${STATUS}`:

```json
{
  "decision": "continue",
  "reason": "Identified agent-usability improvements in iteration ${ITERATION}",
  "summary": "Brief themes analyzed",
  "work": {"items_completed": [], "files_touched": ["${OUTPUT_PATH}"]},
  "errors": []
}
```

## Guidelines

- Think like an agent using this system
- Iteration 2+ should analyze different areas or go deeper
- Focus on practical, high-impact changes
