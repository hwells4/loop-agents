# Check Pipeline Status Workflow

## Step 1: List Running Pipelines

```bash
# Check tmux sessions
echo "=== Running Pipelines (tmux) ==="
tmux list-sessions 2>/dev/null | grep "^pipeline-" || echo "  (none running)"

echo ""
echo "=== Recent Runs ==="
ls -lt .claude/pipeline-runs/ 2>/dev/null | head -10 || echo "  (no runs found)"
```

## Step 2: Select a Run to Check

If there are runs, ask which to check:

```json
{
  "questions": [{
    "question": "Which run would you like to check?",
    "header": "Run",
    "options": [
      {"label": "{run-1}", "description": "{status}"},
      {"label": "{run-2}", "description": "{status}"}
    ],
    "multiSelect": false
  }]
}
```

## Step 3: Show Status

For the selected run:

```bash
SESSION="{selected-session}"
STATE_FILE=".claude/pipeline-runs/$SESSION/state.json"

if [ -f "$STATE_FILE" ]; then
  echo "=== Pipeline Status ==="
  cat "$STATE_FILE" | jq '{
    pipeline: .pipeline,
    session: .session,
    status: .status,
    started: .started_at,
    completed: .completed_at,
    current_stage: .current_stage,
    stages: [.stages[] | {name: .name, status: .status}]
  }'
else
  echo "No state file found for: $SESSION"
fi
```

## Step 4: Show Stage Details

```bash
SESSION="{selected-session}"
RUN_DIR=".claude/pipeline-runs/$SESSION"

echo ""
echo "=== Stage Outputs ==="
for stage_dir in "$RUN_DIR"/stage-*/; do
  if [ -d "$stage_dir" ]; then
    stage_name=$(basename "$stage_dir")
    file_count=$(ls -1 "$stage_dir"/*.md 2>/dev/null | wc -l | tr -d ' ')
    echo "  $stage_name: $file_count output file(s)"
  fi
done
```

## Step 5: Offer Actions

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Action",
    "options": [
      {"label": "View outputs", "description": "Read the output files"},
      {"label": "Attach to live", "description": "Watch the running pipeline"},
      {"label": "Kill", "description": "Stop the running pipeline"},
      {"label": "Done", "description": "That's all"}
    ],
    "multiSelect": false
  }]
}
```

**For "View outputs":**
```bash
# Read output files
cat .claude/pipeline-runs/$SESSION/stage-*/output.md 2>/dev/null
cat .claude/pipeline-runs/$SESSION/stage-*/run-*.md 2>/dev/null
```

**For "Attach to live":**
```bash
echo "Attaching to pipeline-$SESSION..."
echo "Detach with: Ctrl+b, then d"
tmux attach -t pipeline-$SESSION
```

**For "Kill":**
```bash
tmux kill-session -t pipeline-$SESSION
echo "Pipeline killed."
```
