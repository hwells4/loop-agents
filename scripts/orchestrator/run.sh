#!/bin/bash
set -e

# Pipeline Orchestrator - Run multi-stage pipelines
# Usage: run.sh <pipeline.yaml> [session_name]
#
# The orchestrator coordinates pipeline execution:
# - Parses pipeline YAML definition
# - Sets up run directory for outputs
# - For each stage, creates a temporary loop and calls loop-engine
# - Passes data between stages via resolved variables
#
# Architecture:
#   Orchestrator = coordination (what stages, what order, data flow)
#   Loop-engine  = execution (run prompts, completion strategies)

PIPELINE_FILE=${1:?"Usage: run.sh <pipeline.yaml> [session_name]"}

# Resolve pipeline file path
if [ ! -f "$PIPELINE_FILE" ]; then
  if [ -f ".claude/pipelines/${PIPELINE_FILE}" ]; then
    PIPELINE_FILE=".claude/pipelines/${PIPELINE_FILE}"
  elif [ -f ".claude/pipelines/${PIPELINE_FILE}.yaml" ]; then
    PIPELINE_FILE=".claude/pipelines/${PIPELINE_FILE}.yaml"
  else
    echo "Error: Pipeline not found: $PIPELINE_FILE" >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
LOOP_ENGINE_DIR="$SCRIPT_DIR/../loop-engine"

# Source libraries
source "$SCRIPT_DIR/lib/parse.sh"
source "$SCRIPT_DIR/lib/resolve.sh"

# Parse pipeline
parse_pipeline "$PIPELINE_FILE"

# Generate session name if not provided
PIPELINE_NAME=$(get_pipeline_value "name")
SESSION_NAME=${2:-"${PIPELINE_NAME}-$(date +%Y%m%d-%H%M%S)"}

# Set up run directory
RUN_DIR="$PROJECT_ROOT/.claude/pipeline-runs/$SESSION_NAME"
TEMP_LOOPS_DIR="$RUN_DIR/.loops"
mkdir -p "$RUN_DIR" "$TEMP_LOOPS_DIR"

# Copy pipeline definition for reference
cp "$PIPELINE_FILE" "$RUN_DIR/pipeline.yaml"

# Initialize orchestrator state
STATE_FILE="$RUN_DIR/state.json"
cat > "$STATE_FILE" << EOF
{
  "pipeline": "$PIPELINE_NAME",
  "session": "$SESSION_NAME",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "running",
  "current_stage": 0,
  "stages": []
}
EOF

# Export for child processes
export PROJECT_ROOT SESSION_NAME RUN_DIR
export ORCHESTRATOR_MODE=1
export ORCHESTRATOR_RUN_DIR="$RUN_DIR"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Pipeline Orchestrator                                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Pipeline: $PIPELINE_NAME"
echo "║  Session:  $SESSION_NAME"
echo "║  Run dir:  $RUN_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Get stage count
STAGE_COUNT=$(get_stage_count)

# Execute each stage
for stage_idx in $(seq 0 $((STAGE_COUNT - 1))); do
  STAGE_NAME=$(get_stage_value "$stage_idx" "name")
  STAGE_DESC=$(get_stage_value "$stage_idx" "description")
  STAGE_RUNS=$(get_stage_value "$stage_idx" "runs" "1")
  STAGE_MODEL=$(get_stage_value "$stage_idx" "model" "$(get_pipeline_value 'defaults.model' 'sonnet')")
  STAGE_PROVIDER=$(get_stage_value "$stage_idx" "provider" "$(get_pipeline_value 'defaults.provider' 'claude-code')")
  STAGE_COMPLETION=$(get_stage_value "$stage_idx" "completion" "")
  STAGE_PARALLEL=$(get_stage_value "$stage_idx" "parallel" "false")

  # Create stage output directory
  STAGE_DIR="$RUN_DIR/stage-$((stage_idx + 1))-$STAGE_NAME"
  mkdir -p "$STAGE_DIR"

  echo "┌──────────────────────────────────────────────────────────────"
  echo "│ Stage $((stage_idx + 1))/$STAGE_COUNT: $STAGE_NAME"
  [ -n "$STAGE_DESC" ] && echo "│ $STAGE_DESC"
  echo "│ Runs: $STAGE_RUNS | Model: $STAGE_MODEL | Provider: $STAGE_PROVIDER"
  [ -n "$STAGE_COMPLETION" ] && echo "│ Completion: $STAGE_COMPLETION"
  echo "└──────────────────────────────────────────────────────────────"
  echo ""

  # Update orchestrator state
  update_state_stage "$STATE_FILE" "$stage_idx" "$STAGE_NAME" "running"

  # Get prompt template and perspectives
  PROMPT_TEMPLATE=$(get_stage_prompt "$stage_idx")
  PERSPECTIVES=$(get_stage_array "$stage_idx" "perspectives")

  # Create temporary loop for this stage
  TEMP_LOOP_DIR="$TEMP_LOOPS_DIR/stage-$((stage_idx + 1))-$STAGE_NAME"
  mkdir -p "$TEMP_LOOP_DIR"

  # Determine completion strategy (default to fixed-n for pipelines)
  COMPLETION_STRATEGY="${STAGE_COMPLETION:-fixed-n}"

  # Create loop.yaml for this stage
  cat > "$TEMP_LOOP_DIR/loop.yaml" << EOF
name: $STAGE_NAME
description: Pipeline stage - $STAGE_DESC
completion: $COMPLETION_STRATEGY
delay: 2
model: $STAGE_MODEL
provider: $STAGE_PROVIDER
output_dir: $STAGE_DIR
EOF

  # Handle parallel fan-out vs sequential execution
  if [ "$STAGE_PARALLEL" = "true" ] && [ "$STAGE_RUNS" -gt 1 ]; then
    # Parallel fan-out: create separate prompts, run concurrently
    echo "  Running $STAGE_RUNS iterations in parallel..."

    PIDS=()
    for run_idx in $(seq 0 $((STAGE_RUNS - 1))); do
      OUTPUT_FILE="$STAGE_DIR/run-$run_idx.md"
      PERSPECTIVE=$(get_array_item "$PERSPECTIVES" "$run_idx")

      # Resolve variables for this run
      RESOLVED_PROMPT=$(resolve_prompt "$PROMPT_TEMPLATE" "$stage_idx" "$run_idx" "$PERSPECTIVE" "$OUTPUT_FILE" "")

      # Create individual prompt file
      PROMPT_FILE="$TEMP_LOOP_DIR/prompt-$run_idx.md"
      echo "$RESOLVED_PROMPT" > "$PROMPT_FILE"

      # Execute via loop-engine (single iteration each)
      (
        export LOOP_OUTPUT_FILE="$OUTPUT_FILE"
        export LOOP_MODEL="$STAGE_MODEL"
        cd "$PROJECT_ROOT"

        # Use loop-engine's execute function or direct claude call
        if [ "$STAGE_PROVIDER" = "claude-code" ] || [ "$STAGE_PROVIDER" = "claude" ]; then
          cat "$PROMPT_FILE" | claude --model "$STAGE_MODEL" --dangerously-skip-permissions > "$OUTPUT_FILE" 2>&1
        else
          # Future: other providers
          cat "$PROMPT_FILE" | claude --model "$STAGE_MODEL" --dangerously-skip-permissions > "$OUTPUT_FILE" 2>&1
        fi
      ) &
      PIDS+=($!)
    done

    # Wait for all parallel runs
    for pid in "${PIDS[@]}"; do
      wait "$pid" || true
    done

    echo "  ✓ All $STAGE_RUNS parallel runs complete"

  else
    # Sequential execution via loop-engine
    # Create the prompt file with variable placeholders for loop-engine
    PROGRESS_FILE="$STAGE_DIR/progress.md"

    # For sequential runs, we use the loop-engine properly
    # First, resolve stage-level inputs (from previous stages)
    STAGE_INPUTS=$(resolve_stage_inputs_for_prompt "$stage_idx")

    # Create prompt.md with resolved inter-stage references but keeping iteration vars
    PROMPT_WITH_INPUTS=$(echo "$PROMPT_TEMPLATE" | sed "s|\${INPUTS}|$STAGE_INPUTS|g")

    # Resolve any ${INPUTS.stage-name} references
    while [[ "$PROMPT_WITH_INPUTS" =~ \$\{INPUTS\.([a-zA-Z0-9_-]+)\} ]]; do
      ref_stage="${BASH_REMATCH[1]}"
      ref_content=$(resolve_stage_inputs "$ref_stage")
      escaped=$(printf '%s\n' "$ref_content" | sed 's/[&/\]/\\&/g')
      PROMPT_WITH_INPUTS=$(echo "$PROMPT_WITH_INPUTS" | sed "s|\${INPUTS\.$ref_stage}|$escaped|g")
    done

    echo "$PROMPT_WITH_INPUTS" > "$TEMP_LOOP_DIR/prompt.md"

    # Add output_parse if using plateau
    if [ "$COMPLETION_STRATEGY" = "plateau" ]; then
      echo "output_parse: plateau:PLATEAU reasoning:REASONING" >> "$TEMP_LOOP_DIR/loop.yaml"
      echo "min_iterations: 2" >> "$TEMP_LOOP_DIR/loop.yaml"
    fi

    # Set up environment for loop-engine
    export LOOPS_DIR="$TEMP_LOOPS_DIR"
    export STAGE_OUTPUT_DIR="$STAGE_DIR"

    # Call loop-engine
    LOOP_SESSION="${SESSION_NAME}-stage-$((stage_idx + 1))"

    # The loop-engine needs to know about our custom loops dir
    ORIGINAL_LOOPS_DIR="$LOOP_ENGINE_DIR/../loops"

    # Run the loop-engine with our temporary loop
    (
      cd "$PROJECT_ROOT"

      # Source loop-engine components
      source "$LOOP_ENGINE_DIR/lib/state.sh"
      source "$LOOP_ENGINE_DIR/lib/progress.sh"
      source "$LOOP_ENGINE_DIR/lib/parse.sh"
      source "$LOOP_ENGINE_DIR/lib/notify.sh"

      # Initialize state and progress for this stage
      STAGE_STATE_FILE=$(init_state "$LOOP_SESSION" "$STAGE_NAME")
      STAGE_PROGRESS_FILE=$(init_progress "$LOOP_SESSION")

      # Source completion strategy
      COMPLETION_SCRIPT="$LOOP_ENGINE_DIR/completions/${COMPLETION_STRATEGY}.sh"
      if [ -f "$COMPLETION_SCRIPT" ]; then
        source "$COMPLETION_SCRIPT"
      fi

      # Run iterations
      for i in $(seq 1 $STAGE_RUNS); do
        echo "  Iteration $i/$STAGE_RUNS..."

        # Determine output file
        if [ "$STAGE_RUNS" -eq 1 ]; then
          OUTPUT_FILE="$STAGE_DIR/output.md"
        else
          OUTPUT_FILE="$STAGE_DIR/run-$((i - 1)).md"
        fi

        # Get perspective if applicable
        PERSPECTIVE=$(get_array_item "$PERSPECTIVES" "$((i - 1))")

        # Read and substitute prompt
        PROMPT_CONTENT=$(cat "$TEMP_LOOP_DIR/prompt.md")
        PROMPT_CONTENT=$(echo "$PROMPT_CONTENT" | sed "s|\${SESSION}|$SESSION_NAME|g")
        PROMPT_CONTENT=$(echo "$PROMPT_CONTENT" | sed "s|\${INDEX}|$((i - 1))|g")
        PROMPT_CONTENT=$(echo "$PROMPT_CONTENT" | sed "s|\${PERSPECTIVE}|$PERSPECTIVE|g")
        PROMPT_CONTENT=$(echo "$PROMPT_CONTENT" | sed "s|\${OUTPUT}|$OUTPUT_FILE|g")
        PROMPT_CONTENT=$(echo "$PROMPT_CONTENT" | sed "s|\${PROGRESS}|$STAGE_PROGRESS_FILE|g")

        # Execute
        OUTPUT=$(echo "$PROMPT_CONTENT" | claude --model "$STAGE_MODEL" --dangerously-skip-permissions 2>&1 | tee /dev/stderr) || true

        # Save output
        echo "$OUTPUT" > "$OUTPUT_FILE"

        # Parse output if needed
        if [ "$COMPLETION_STRATEGY" = "plateau" ]; then
          OUTPUT_JSON=$(parse_outputs_to_json "$OUTPUT" "plateau:PLATEAU" "reasoning:REASONING")
          update_state "$STAGE_STATE_FILE" "$i" "$OUTPUT_JSON"

          # Check plateau
          if type check_completion &>/dev/null; then
            if check_completion "$LOOP_SESSION" "$STAGE_STATE_FILE" "$OUTPUT"; then
              echo "  ✓ Plateau reached after $i iterations"
              break
            fi
          fi
        fi

        # Brief pause between iterations
        [ "$i" -lt "$STAGE_RUNS" ] && sleep 2
      done
    )
  fi

  # Update orchestrator state
  update_state_stage "$STATE_FILE" "$stage_idx" "$STAGE_NAME" "complete"

  echo ""
done

# Clean up temporary loops
rm -rf "$TEMP_LOOPS_DIR"

# Mark pipeline complete
jq '.status = "complete" | .completed_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  PIPELINE COMPLETE                                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Pipeline: $PIPELINE_NAME"
echo "║  Session:  $SESSION_NAME"
echo "║  Stages:   $STAGE_COUNT"
echo "║  Output:   $RUN_DIR"
echo "╚══════════════════════════════════════════════════════════════╝"
