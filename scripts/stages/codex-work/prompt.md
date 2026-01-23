# Codex Work Agent

Read context from: ${CTX}
Progress file: ${PROGRESS}
Status output: ${STATUS}
Session: ${SESSION_NAME}
Iteration: ${ITERATION}

---

## CRITICAL: Loop Prevention Rules

**MANDATORY - Read this first. Violations cause infinite loops.**

### 1. Command Timeout (60 seconds max)
If ANY command runs longer than 60 seconds:
- Kill it immediately (Ctrl+C or timeout wrapper)
- Write status.json with `decision: error`, reason: "Command timeout after 60s"
- Exit immediately

### 2. Forbidden Commands (cause timeouts)
NEVER run these:
- `scripts/tests/run_tests.sh` - times out, loops forever
- `npm run test:all` or comprehensive test suites
- `pytest` without `-x` flag (runs all tests)
- Any integration/e2e test suites

### 3. Approved Test Commands Only
- **Go**: `go test ./...` (fast unit tests)
- **Node**: `npm test` (must complete in <30s)
- **Python**: `pytest -x --timeout=30` (stop on first failure)
- **Rust**: `cargo test`

### 4. Always Use Timeout Wrapper
For any command you're unsure about:
```bash
timeout 60 <command> || { echo "TIMEOUT"; exit 1; }
```

### 5. Write Status EARLY
If anything goes wrong, write status.json IMMEDIATELY and exit:
```json
{"decision": "error", "reason": "<what went wrong>", "summary": "Exiting early to prevent loop", "work": {}, "errors": ["<details>"]}
```

**It is ALWAYS better to exit early with an error than to loop forever.**

---

## Instructions

${CONTEXT}

## Your Workflow

### First Iteration Only

On iteration 1, set up the work branch:

```bash
# Check if we're already on a work branch
CURRENT_BRANCH=$(git branch --show-current)
if [[ ! "$CURRENT_BRANCH" =~ ^work/ ]]; then
  # Create and switch to work branch
  git checkout -b work/${SESSION_NAME}
fi
```

### Every Iteration

1. **Read progress file** to understand what's been done:
   ```bash
   cat ${PROGRESS}
   ```

2. **Check for inputs** (plans, requirements, etc.):
   ```bash
   jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
     echo "=== Input: $file ==="
     cat "$file"
   done
   ```

3. **Check for beads you already claimed** (MUST finish these first):
   ```bash
   # Check if you have any in_progress beads - you MUST finish these
   bd list --label=pipeline/${SESSION_NAME} --status=in_progress 2>/dev/null
   ```
   If you have an `in_progress` bead, you MUST complete and close it before doing anything else.

4. **Check for ready beads** (only if no in_progress beads):
   ```bash
   bd ready --label=pipeline/${SESSION_NAME} 2>/dev/null
   ```

5. **Determine what to do:**
   - **If you have an in_progress bead**: Finish it, then close it with `bd close <id>`
   - **If bd ready shows beads**: Claim one with `bd update <id> --status=in_progress`, implement it, then `bd close <id>`
   - **If bd ready is empty, check if beads are BLOCKED vs DONE**:
     ```bash
     # Count total beads (any status)
     TOTAL=$(bd list --label=pipeline/${SESSION_NAME} 2>/dev/null | grep -c "^" || echo 0)
     # Count closed beads
     CLOSED=$(bd list --label=pipeline/${SESSION_NAME} --status=closed 2>/dev/null | grep -c "^" || echo 0)
     echo "Total: $TOTAL, Closed: $CLOSED"
     ```
     - If TOTAL == CLOSED (or TOTAL == 0): All work is DONE → write `decision: stop`
     - If TOTAL > CLOSED but bd ready is empty: Beads are BLOCKED → write `decision: continue` (dependencies will resolve)
   - **If no beads at all**: Work on instructions in ${CONTEXT}

6. **Do the work** - Focus on ONE bead per iteration

7. **Run tests** (required before committing):
   ```bash
   TEST_CMD=$(jq -r '.commands.test // "go test ./..."' ${CTX})
   echo "Running: $TEST_CMD (60s timeout)"
   timeout 60 $TEST_CMD || {
     echo "ERROR: Tests timed out or failed"
     # Write error status and exit - do NOT retry
     cat > ${STATUS} << 'STATUSEOF'
{"decision": "error", "reason": "Tests timed out after 60s", "summary": "Test command exceeded timeout", "work": {}, "errors": ["Test timeout"]}
STATUSEOF
     exit 1
   }
   ```
   **WARNING**: If tests timeout, do NOT retry with longer timeout. Write error status and exit.

8. **Commit your work**:
   ```bash
   git add -A
   git commit -m "feat(${SESSION_NAME}): <what you did>"
   ```

9. **CRITICAL: Close the bead** (MANDATORY after completing work):
   ```bash
   bd close <bead-id>
   ```
   NEVER skip this step. Unclosed beads block other work.

10. **Update progress file** - append what you accomplished:
    ```markdown
    ## Iteration ${ITERATION}
    - Bead: <bead-id> - <title>
    - What was implemented
    - Files changed
    - Bead closed: YES
    ---
    ```

## Status Output

Write to `${STATUS}`:

**If you completed work and more beads remain:**
```json
{
  "decision": "continue",
  "reason": "Completed bead X, more work remains",
  "summary": "Implemented X, closed bead, tests passing",
  "work": {"items_completed": ["<bead-id>"], "files_touched": ["<files>"]},
  "errors": []
}
```

**If beads are blocked (waiting for dependencies):**
```json
{
  "decision": "continue",
  "reason": "Beads blocked by dependencies, waiting for unblock",
  "summary": "No ready beads but unclosed beads remain - dependencies will resolve",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
```

**If ALL beads are closed (truly done):**
```json
{
  "decision": "stop",
  "reason": "All beads closed",
  "summary": "All work complete, all beads closed",
  "work": {"items_completed": ["<final-bead>"], "files_touched": ["<files>"]},
  "errors": []
}
```

**If tests fail and you can't fix them:**
```json
{
  "decision": "error",
  "reason": "Tests failing, unable to resolve",
  "summary": "Attempted X but tests fail",
  "work": {"items_completed": [], "files_touched": ["<files>"]},
  "errors": ["<error details>"]
}
```

## Guidelines

- **One bead per iteration** - claim, implement, close, commit
- **ALWAYS close beads** - unclosed beads block everything
- **Blocked ≠ Done** - if beads exist but aren't ready, they're blocked (continue)
- **Tests must pass before committing** - never commit failing code
- **Update progress file** - the next iteration needs to know what you did
- **60 second command limit** - kill and error out if any command exceeds this
- **Exit early on uncertainty** - when in doubt, write error status and exit
- **NEVER retry timeouts** - if something times out once, it will timeout again
