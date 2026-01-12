# Commands Reference

All bash commands for session management, organized by operation.

<start_commands>
## Starting Sessions

**Single-stage (work loop):**
```bash
./scripts/run.sh work {session} {max_iterations}
./scripts/run.sh work auth 25
```

**Single-stage (other types):**
```bash
./scripts/run.sh {type} {session} {max}
./scripts/run.sh improve-plan my-plan 5
./scripts/run.sh refine-beads my-beads 5
./scripts/run.sh elegance my-code 3
./scripts/run.sh idea-wizard my-ideas 10
```

**Multi-stage pipeline:**
```bash
./scripts/run.sh pipeline {file} {session}
./scripts/run.sh pipeline full-refine.yaml my-project
./scripts/run.sh pipeline quick-refine.yaml my-feature
./scripts/run.sh pipeline deep-refine.yaml big-refactor
```

**With flags:**
```bash
./scripts/run.sh work auth 25 --force    # Override existing lock
./scripts/run.sh work auth 25 --resume   # Continue from crash
```
</start_commands>

<discovery_commands>
## Discovering Options

**List available stage types:**
```bash
ls scripts/stages/
```

**List available pipelines:**
```bash
ls scripts/pipelines/*.yaml 2>/dev/null | xargs -n1 basename
```

**View pipeline configuration:**
```bash
cat scripts/pipelines/full-refine.yaml
```

**View stage configuration:**
```bash
cat scripts/stages/work/stage.yaml
```
</discovery_commands>

<status_commands>
## Checking Status

**Built-in status command:**
```bash
./scripts/run.sh status {session}
```

**List running tmux sessions:**
```bash
tmux list-sessions 2>/dev/null | grep -E "^loop-"
```

**Check specific tmux session:**
```bash
tmux has-session -t pipeline-{session} 2>/dev/null && echo "running" || echo "not running"
```

**View state file:**
```bash
cat .claude/pipeline-runs/{session}/state.json | jq
```

**View lock file:**
```bash
cat .claude/locks/{session}.lock | jq
```

**Check if lock PID is alive:**
```bash
pid=$(jq -r .pid .claude/locks/{session}.lock)
kill -0 "$pid" 2>/dev/null && echo "alive" || echo "dead"
```
</status_commands>

<monitoring_commands>
## Monitoring Sessions

**Peek at output (non-interactive):**
```bash
tmux capture-pane -t pipeline-{session} -p | tail -50
```

**Capture full pane:**
```bash
tmux capture-pane -t pipeline-{session} -p
```

**Attach to watch live:**
```bash
tmux attach -t pipeline-{session}
# Detach: Ctrl+b, then d
```
</monitoring_commands>

<termination_commands>
## Terminating Sessions

**Kill tmux session:**
```bash
tmux kill-session -t pipeline-{session}
```

**Remove lock file:**
```bash
rm .claude/locks/{session}.lock
```

**Update state to killed:**
```bash
jq '.status = "killed"' .claude/pipeline-runs/{session}/state.json > /tmp/state.json \
    && mv /tmp/state.json .claude/pipeline-runs/{session}/state.json
```
</termination_commands>

<beads_commands>
## Beads Integration (Work Sessions)

**Check remaining beads:**
```bash
bd ready --label=pipeline/{session}
```

**Count remaining:**
```bash
bd ready --label=pipeline/{session} | wc -l
```

**List all session beads:**
```bash
bd list --label=pipeline/{session}
```

**List completed:**
```bash
bd list --label=pipeline/{session} --status=closed
```

**List in progress:**
```bash
bd list --label=pipeline/{session} --status=in_progress
```
</beads_commands>

<file_locations>
## File Locations

**Lock files:**
```
.claude/locks/{session}.lock
```

**State files:**
```
.claude/pipeline-runs/{session}/state.json
```

**Progress files:**
```
.claude/pipeline-runs/{session}/progress-{session}.md
```

**Iteration snapshots:**
```
.claude/pipeline-runs/{session}/iterations/NNN/
  ├── output.md
  └── status.json
```
</file_locations>

<state_file_format>
## State File Format

```json
{
  "session": "auth",
  "loop_type": "work",
  "iteration": 5,
  "iteration_completed": 4,
  "iteration_started": "2025-01-10T10:05:00Z",
  "status": "running",
  "started_at": "2025-01-10T10:00:00Z",
  "history": [
    {"plateau": false, "summary": "..."},
    {"plateau": true, "summary": "..."}
  ]
}
```

**Status values:**
- `running` - Active
- `complete` - Finished successfully
- `failed` - Ended with error
- `killed` - Manually terminated
- `unknown_termination` - Crashed, state recovered
</state_file_format>

<lock_file_format>
## Lock File Format

```json
{
  "session": "auth",
  "pid": 12345,
  "started_at": "2025-01-10T10:00:00Z"
}
```
</lock_file_format>

<naming_conventions>
## Naming Conventions

| Resource | Pattern | Example |
|----------|---------|---------|
| Session name | lowercase-hyphens | `auth`, `billing-refactor` |
| tmux session | `pipeline-{session}` | `loop-auth` |
| Beads label | `pipeline/{session}` | `pipeline/auth` |
| Lock file | `{session}.lock` | `auth.lock` |
</naming_conventions>
