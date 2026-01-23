# Ralph Agent

Context: ${CTX}
Progress: ${PROGRESS}
Status: ${STATUS}

${CONTEXT}

## Do ONE Task

1. **Read progress** - check ${PROGRESS} for codebase patterns and prior work

2. **Read inputs** (if first iteration):
   ```bash
   jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | xargs cat
   ```

3. **Get one task**:
   ```bash
   bd ready | head -1
   ```

4. **Claim it**:
   ```bash
   bd update <id> --status=in_progress
   ```

5. **Implement it fully** - write code, make it work

6. **Run tests**:
   ```bash
   TEST_CMD=$(jq -r '.commands.test // "npm test"' ${CTX})
   $TEST_CMD
   ```

7. **Commit**:
   ```bash
   git add -A && git commit -m "feat(<id>): <title>"
   ```

8. **Close it**:
   ```bash
   bd close <id>
   ```

9. **Update progress** - append to ${PROGRESS} (see format below)

10. **Write status** and STOP:
    ```bash
    cat > ${STATUS} << 'EOF'
    {"decision": "continue", "summary": "Completed <id>: <title>"}
    EOF
    ```
    If no tasks remain, use `"decision": "stop"` instead.

**IMPORTANT: Do exactly ONE task, then stop.**

---

## Progress File Format

**Codebase Patterns** (top of file, update as you learn):
```markdown
## Codebase Patterns
- **Pattern name**: How to use it
- **Another pattern**: Description
```

**Work Log** (append after each task):
```markdown
## YYYY-MM-DD - <bead-id>: <title>
- What was implemented
- Files changed
- **Learnings**: Patterns discovered, gotchas encountered
---
```
