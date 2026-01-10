# Run Pipeline Workflow

## Step 1: List Available Pipelines

```bash
# Check for pipelines
ls -la .claude/pipelines/*.yaml 2>/dev/null
```

If no pipelines exist:
- Tell user: "No pipelines found in `.claude/pipelines/`"
- Suggest: "Would you like to create one? Use `/loop-agents:pipeline` and select Create"
- Or: "You can copy a template from `.claude/loop-agents/scripts/orchestrator/templates/`"

## Step 2: Select Pipeline

If multiple pipelines exist, ask:

```json
{
  "questions": [{
    "question": "Which pipeline would you like to run?",
    "header": "Pipeline",
    "options": [
      {"label": "{pipeline-1}", "description": "{description from yaml}"},
      {"label": "{pipeline-2}", "description": "{description from yaml}"}
    ],
    "multiSelect": false
  }]
}
```

## Step 3: Session Name

Ask for a session name (optional):

```json
{
  "questions": [{
    "question": "What session name? (Leave blank for auto-generated)",
    "header": "Session",
    "options": [
      {"label": "Auto-generate", "description": "Use pipeline-name-timestamp"},
      {"label": "Custom", "description": "I'll provide a name"}
    ],
    "multiSelect": false
  }]
}
```

If custom, ask for the name.

## Step 4: Execution Mode

Ask how to run:

```json
{
  "questions": [{
    "question": "How should the pipeline run?",
    "header": "Mode",
    "options": [
      {"label": "Background (Recommended)", "description": "Run in tmux, monitor anytime"},
      {"label": "Foreground", "description": "Run here, watch live output"}
    ],
    "multiSelect": false
  }]
}
```

## Step 5: Launch

**Background (tmux):**
```bash
PLUGIN_DIR=".claude/loop-agents"
PIPELINE="{selected-pipeline}"
SESSION="{session-name}"  # or auto-generated

tmux new-session -d -s "pipeline-$SESSION" -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/orchestrator/run.sh $PIPELINE $SESSION"

echo "Pipeline launched in tmux session: pipeline-$SESSION"
```

**Foreground:**
```bash
PLUGIN_DIR=".claude/loop-agents"
$PLUGIN_DIR/scripts/orchestrator/run.sh {pipeline} {session}
```

## Step 6: Provide Status

After launching, tell the user:

**For background:**
```
Pipeline launched!

Session: pipeline-{session}
Output: .claude/pipeline-runs/{session}/

Commands:
  - Check status: cat .claude/pipeline-runs/{session}/state.json | jq
  - View live: tmux attach -t pipeline-{session}
  - Detach: Ctrl+b, then d
  - Kill: tmux kill-session -t pipeline-{session}
```

**For foreground:**
Wait for completion, then show:
```
Pipeline complete!

Output: .claude/pipeline-runs/{session}/
Status: {status from state.json}
```
