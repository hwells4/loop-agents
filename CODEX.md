# Codex Rules for Agent Pipelines

These rules apply when Codex runs as part of the agent-pipelines system.

## Execution Limits

### Command Timeouts
- **Maximum 60 seconds** for any single command
- If a command exceeds 60 seconds, kill it and write an error status
- Use `timeout 60 <command>` for uncertain commands
- NEVER retry a command that timed out - it will timeout again

### Forbidden Commands
These commands cause infinite loops - NEVER run them:
- `scripts/tests/run_tests.sh` - comprehensive test suite, times out
- `scripts/tests/run_tests.sh --ci` - same issue
- `npm run test:all` - too slow
- `pytest` without `-x` or `--timeout` flags
- Any command with "integration" or "e2e" in the name

### Approved Test Commands
Only use these fast test commands:
- `go test ./...` - Go unit tests (fast)
- `npm test` - should complete in <30s
- `pytest -x --timeout=30` - Python with safeguards
- `cargo test` - Rust tests

## Pipeline Behavior

### Status File Priority
When running in a pipeline:
1. Write status.json BEFORE doing anything risky
2. If uncertain, write `decision: error` and exit
3. Never leave status.json unwritten - the pipeline needs it

### Bead Management
- Check `bd list --status=in_progress` FIRST - finish claimed work
- Always run `bd close <id>` after completing a bead
- If beads are blocked (not ready), write `decision: continue` and exit

### Exit Early Philosophy
It is ALWAYS better to:
- Exit with an error than loop forever
- Skip tests than wait for timeout
- Write partial progress than hang indefinitely

## Error Recovery

If you encounter:
- **Timeout**: Write error status, exit immediately
- **Blocked beads**: Write continue status, exit (dependencies will resolve)
- **Test failure**: Try to fix ONCE, then write error status if still failing
- **Uncertain state**: Write error status with explanation, exit

## Git Workflow

- Create work branch: `git checkout -b work/${SESSION_NAME}`
- Commit after each bead: `git commit -m "feat(${SESSION_NAME}): <what>"`
- Never commit failing tests
- Never force push
