# List Pipelines Workflow

## Step 1: Check for Pipelines

```bash
# List user pipelines
echo "=== Your Pipelines ==="
ls -la .claude/pipelines/*.yaml 2>/dev/null || echo "  (none)"

echo ""
echo "=== Available Templates ==="
ls -la .claude/loop-agents/scripts/orchestrator/templates/*.yaml 2>/dev/null || echo "  (none)"
```

## Step 2: Show Details

For each pipeline found, extract and show:

```bash
# For each .yaml file
for f in .claude/pipelines/*.yaml; do
  if [ -f "$f" ]; then
    name=$(basename "$f" .yaml)
    desc=$(grep "^description:" "$f" | cut -d: -f2- | sed 's/^[[:space:]]*//')
    stages=$(grep -c "^  - name:" "$f" || echo "0")
    echo "  $name - $desc ($stages stages)"
  fi
done
```

## Step 3: Format Output

Present to user:

```
## Your Pipelines (.claude/pipelines/)

| Pipeline | Description | Stages |
|----------|-------------|--------|
| code-review | Multi-perspective code review | 4 |
| research-implement | Research, plan, implement | 4 |

## Templates (ready to copy)

| Template | Description | Stages |
|----------|-------------|--------|
| code-review | Multi-perspective review with synthesis | 4 |
| research-implement | Research, plan, and implement | 4 |
| ideate | Generate and synthesize ideas | 3 |

To copy a template:
  cp .claude/loop-agents/scripts/orchestrator/templates/{name}.yaml .claude/pipelines/
```

## Step 4: Offer Actions

```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Next",
    "options": [
      {"label": "Run a pipeline", "description": "Execute one of these pipelines"},
      {"label": "Create new", "description": "Design a new pipeline"},
      {"label": "View details", "description": "See full YAML of a pipeline"},
      {"label": "Done", "description": "That's all I needed"}
    ],
    "multiSelect": false
  }]
}
```

Route accordingly.
