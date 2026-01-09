# Bead Refinement Iteration

Session: ${SESSION_NAME}
Iteration: ${ITERATION}

## Your Task

You are a meticulous planning reviewer. Your job is to carefully examine each bead and improve its quality.

1. **Load context** - Read AGENTS.md and any relevant architecture docs
2. **List all beads** for this session:
   ```bash
   bd list --label=loop/${SESSION_NAME}
   ```
3. **For each bead**, check:
   - Is the title clear and actionable?
   - Is the description specific enough to implement?
   - Are acceptance criteria testable and complete?
   - Are dependencies correctly set up?
   - Is the scope right-sized (not too big, not too small)?

4. **Make improvements** using bd update commands:
   ```bash
   bd update <id> --description="..." --acceptance="..."
   ```

5. **Add missing beads** if you discover gaps:
   ```bash
   bd create --title="..." --type=task --priority=2 --add-label="loop/${SESSION_NAME}"
   ```

6. **Fix dependencies** if needed:
   ```bash
   bd dep add <issue> <depends-on>
   ```

## Quality Standards

- Each bead should be implementable in 15-60 minutes
- Acceptance criteria should be verifiable (testable)
- Dependencies should reflect actual blocking relationships
- Titles should start with a verb (Create, Implement, Add, Fix)

## Output Requirements

Count your changes and output at the END of your response:

```
CHANGES: {number of updates/creates/deletes made}
SUMMARY: {one-line summary of what you improved}
```

If you made no changes because everything looks good:
```
CHANGES: 0
SUMMARY: All beads meet quality standards
```
