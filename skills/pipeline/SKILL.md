---
name: pipeline
description: Create and run multi-stage pipelines. Orchestrate sequences of AI agents with fan-out, fan-in, and data flow between stages. Use when you need to coordinate multiple prompts/agents in sequence.
---

<essential_principles>

**Pipelines are Reusable Assets:**
- Created once in `.claude/pipelines/`
- Run many times with different sessions
- Version controlled with the project

**Orchestrator Architecture:**
- Pipelines define stages (sequential)
- Each stage can run 1-N times (parallel within stage)
- Data flows via `${INPUTS.stage-name}` variables
- Completion strategies stop stages early

**Key Directories:**
- `.claude/pipelines/` - Pipeline definitions (YAML)
- `.claude/pipeline-runs/{session}/` - Execution outputs
- `.claude/loop-agents/scripts/orchestrator/` - Engine

**Provider Support:**
- `claude-code` - Claude Code CLI (default)
- `codex` - OpenAI Codex CLI
- `gemini` - Google Gemini CLI

</essential_principles>

<intake>
Use the AskUserQuestion tool:

```json
{
  "questions": [{
    "question": "What would you like to do with pipelines?",
    "header": "Action",
    "options": [
      {"label": "Create", "description": "Design and save a new pipeline definition"},
      {"label": "Run", "description": "Execute an existing pipeline"},
      {"label": "List", "description": "Show available pipelines"},
      {"label": "Status", "description": "Check running pipeline status"}
    ],
    "multiSelect": false
  }]
}
```

**Wait for response before proceeding.**
</intake>

<routing>
| Response | Workflow |
|----------|----------|
| "Create" | `workflows/create-pipeline.md` |
| "Run" | `workflows/run-pipeline.md` |
| "List" | `workflows/list-pipelines.md` |
| "Status" | `workflows/check-status.md` |

**After reading the workflow, follow it exactly.**
</routing>

<quick_commands>
```bash
# Plugin directory
PLUGIN_DIR=".claude/loop-agents"

# Run a pipeline
$PLUGIN_DIR/scripts/orchestrator/run.sh my-pipeline
$PLUGIN_DIR/scripts/orchestrator/run.sh my-pipeline custom-session-name

# Run in tmux (background)
tmux new-session -d -s pipeline-NAME -c "$(pwd)" \
  "$PLUGIN_DIR/scripts/orchestrator/run.sh my-pipeline NAME"

# List pipelines
ls -la .claude/pipelines/*.yaml 2>/dev/null

# List runs
ls -la .claude/pipeline-runs/

# Check run status
cat .claude/pipeline-runs/SESSION/state.json | jq '.status'

# View templates
ls $PLUGIN_DIR/scripts/orchestrator/templates/
```
</quick_commands>

<pipeline_schema>
```yaml
name: pipeline-name           # Required: identifier
description: What it does     # Optional
version: 1                    # Optional

defaults:                     # Optional: defaults for all stages
  provider: claude-code
  model: sonnet

stages:                       # Required: list of stages
  - name: stage-name          # Required: unique identifier
    description: ...          # Optional
    runs: 1                   # How many times (default: 1)
    model: opus               # Override model
    provider: claude-code     # Override provider
    completion: plateau       # Early-stop: plateau, beads-empty
    parallel: true            # Run iterations in parallel
    perspectives: [...]       # Values for ${PERSPECTIVE}
    prompt: |                 # Required: the prompt template
      Your instructions...
```

**Variables in prompts:**
- `${SESSION}` - Session name
- `${INDEX}` - Run index (0-based)
- `${PERSPECTIVE}` - Current perspective
- `${OUTPUT}` - Where to write output
- `${PROGRESS}` - Accumulating progress file
- `${INPUTS.stage-name}` - Outputs from named stage
- `${INPUTS}` - Outputs from previous stage
</pipeline_schema>

<reference_index>
| Reference | Purpose |
|-----------|---------|
| references/schema.md | Full pipeline schema reference |
| references/variables.md | Variable substitution details |
| references/providers.md | Provider configuration |
</reference_index>

<workflows_index>
| Workflow | Purpose |
|----------|---------|
| create-pipeline.md | Design and save a new pipeline |
| run-pipeline.md | Execute an existing pipeline |
| list-pipelines.md | Show available pipelines |
| check-status.md | Check running pipeline status |
</workflows_index>

<templates_index>
Templates in `scripts/orchestrator/templates/`:
| Template | Purpose |
|----------|---------|
| code-review.yaml | Multi-perspective code review with synthesis |
| research-implement.yaml | Research, plan, and implement |
| ideate.yaml | Generate and synthesize ideas |
</templates_index>
