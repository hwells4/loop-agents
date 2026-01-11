#!/bin/bash
set -e

# Unified Loop/Pipeline Engine
# Runs single-stage loops or multi-stage pipelines
#
# Usage:
#   engine.sh stage <stage_type> [session] [max_iterations]  # Run single stage
#   engine.sh pipeline <pipeline.yaml> [session]              # Run multi-stage pipeline

MODE=${1:?"Usage: engine.sh <loop|pipeline> <type_or_file> [session] [max_iterations]"}
shift

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
LOOPS_DIR="$SCRIPT_DIR/loops"

export PROJECT_ROOT

# Check dependencies
for cmd in jq claude; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Missing required command: $cmd" >&2
    case "$cmd" in
      jq) echo "  Install: brew install jq" >&2 ;;
      claude) echo "  Install: npm install -g @anthropic-ai/claude-code" >&2 ;;
    esac
    exit 1
  fi
done

# Source libraries
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/state.sh"
source "$LIB_DIR/progress.sh"
source "$LIB_DIR/resolve.sh"
source "$LIB_DIR/parse.sh"
source "$LIB_DIR/notify.sh"
source "$LIB_DIR/lock.sh"

# Export for hooks
export CLAUDE_LOOP_AGENT=1

#-------------------------------------------------------------------------------
# Loop Loading
#-------------------------------------------------------------------------------

# Load a stage definition from loops/ directory
# Sets: LOOP_CONFIG (JSON), LOOP_PROMPT, LOOP_*
load_stage() {
  local stage_type=$1
  local stage_dir="$LOOPS_DIR/$stage_type"

  if [ ! -d "$stage_dir" ]; then
    echo "Error: Loop type not found: $stage_type" >&2
    echo "Available loops:" >&2
    ls "$LOOPS_DIR" 2>/dev/null | while read d; do
      [ -d "$LOOPS_DIR/$d" ] && echo "  $d" >&2
    done
    return 1
  fi

  # Load config YAML as JSON
  local config_file="$stage_dir/loop.yaml"
  if [ ! -f "$config_file" ]; then
    echo "Error: No loop.yaml in $stage_dir" >&2
    return 1
  fi

  LOOP_CONFIG=$(yaml_to_json "$config_file")

  # Extract config values
  LOOP_NAME=$(json_get "$LOOP_CONFIG" ".name" "$stage_type")
  LOOP_COMPLETION=$(json_get "$LOOP_CONFIG" ".completion" "fixed-n")
  LOOP_MODEL=$(json_get "$LOOP_CONFIG" ".model" "opus")
  LOOP_DELAY=$(json_get "$LOOP_CONFIG" ".delay" "3")
  LOOP_CHECK_BEFORE=$(json_get "$LOOP_CONFIG" ".check_before" "false")
  LOOP_OUTPUT_PARSE=$(json_get "$LOOP_CONFIG" ".output_parse" "")
  LOOP_MIN_ITERATIONS=$(json_get "$LOOP_CONFIG" ".min_iterations" "1")
  LOOP_ITEMS=$(json_get "$LOOP_CONFIG" ".items" "")
  LOOP_PROMPT_NAME=$(json_get "$LOOP_CONFIG" ".prompt" "prompt")

  # Export for completion strategies
  export MIN_ITERATIONS="$LOOP_MIN_ITERATIONS"
  export ITEMS="$LOOP_ITEMS"

  # Load prompt
  local prompt_file="$stage_dir/prompts/${LOOP_PROMPT_NAME}.md"
  if [ ! -f "$prompt_file" ]; then
    prompt_file="$stage_dir/prompt.md"
  fi

  if [ ! -f "$prompt_file" ]; then
    echo "Error: No prompt found for loop: $stage_type" >&2
    return 1
  fi

  LOOP_PROMPT=$(cat "$prompt_file")
  LOOP_DIR="$stage_dir"
}

#-------------------------------------------------------------------------------
# Execution
#-------------------------------------------------------------------------------

# Execute Claude with a prompt
# Usage: execute_claude "$prompt" "$model" "$output_file"
execute_claude() {
  local prompt=$1
  local model=${2:-"opus"}
  local output_file=$3

  # Normalize model names
  case "$model" in
    opus|claude-opus|opus-4|opus-4.5) model="opus" ;;
    sonnet|claude-sonnet|sonnet-4) model="sonnet" ;;
    haiku|claude-haiku) model="haiku" ;;
  esac

  if [ -n "$output_file" ]; then
    printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1 | tee "$output_file"
  else
    printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1
  fi
}

# Run a single stage for N iterations
# Usage: run_stage "$stage_type" "$session" "$max_iterations" "$run_dir" "$stage_idx" "$start_iteration"
run_stage() {
  local stage_type=$1
  local session=$2
  local max_iterations=${3:-25}
  local run_dir=${4:-"$PROJECT_ROOT/.claude"}
  local stage_idx=${5:-0}
  local start_iteration=${6:-1}

  load_stage "$stage_type" || return 1

  # Source completion strategy
  local completion_script="$LIB_DIR/completions/${LOOP_COMPLETION}.sh"
  if [ ! -f "$completion_script" ]; then
    echo "Error: Unknown completion strategy: $LOOP_COMPLETION" >&2
    return 1
  fi
  source "$completion_script"

  # Initialize state and progress
  local state_file=$(init_state "$session" "loop" "$run_dir")
  local progress_file=$(init_progress "$session" "$run_dir")

  export CLAUDE_LOOP_SESSION="$session"
  export CLAUDE_LOOP_TYPE="$stage_type"
  export MAX_ITERATIONS="$max_iterations"

  # Display header
  if [ "$start_iteration" -eq 1 ]; then
    echo ""
    echo "  Loop: $LOOP_NAME"
    echo "  Session: $session"
    echo "  Max iterations: $max_iterations"
    echo "  Model: $LOOP_MODEL"
    echo "  Completion: $LOOP_COMPLETION"
    echo ""
  else
    show_resume_info "$session" "$start_iteration" "$max_iterations"
  fi

  for i in $(seq $start_iteration $max_iterations); do
    echo ""
    echo "  Iteration $i of $max_iterations"
    echo ""

    # Mark iteration started (for crash recovery)
    mark_iteration_started "$state_file" "$i"

    # Pre-iteration completion check
    if [ "$LOOP_CHECK_BEFORE" = "true" ]; then
      if check_completion "$session" "$state_file" ""; then
        local reason=$(check_completion "$session" "$state_file" "" 2>&1)
        echo "$reason"
        mark_complete "$state_file" "$reason"
        record_completion "complete" "$session" "$stage_type"
        return 0
      fi
    fi

    # Build variables for prompt resolution
    local vars_json=$(jq -n \
      --arg session "$session" \
      --arg iteration "$i" \
      --arg index "$((i - 1))" \
      --arg progress "$progress_file" \
      --arg run_dir "$run_dir" \
      --arg stage_idx "$stage_idx" \
      '{session: $session, iteration: $iteration, index: $index, progress: $progress, run_dir: $run_dir, stage_idx: $stage_idx}')

    # Resolve prompt
    local resolved_prompt=$(resolve_prompt "$LOOP_PROMPT" "$vars_json")

    # Execute Claude
    set +e
    local output=$(execute_claude "$resolved_prompt" "$LOOP_MODEL" | tee /dev/stderr)
    local exit_code=$?
    set -e

    if [ $exit_code -ne 0 ]; then
      echo ""
      echo "Warning: Claude exited with code $exit_code"
      echo "   Continuing to next iteration..."
      echo ""
    fi

    # Parse output
    local output_json="{}"
    if [ -n "$LOOP_OUTPUT_PARSE" ]; then
      output_json=$(parse_outputs_to_json "$output" $LOOP_OUTPUT_PARSE)
    fi

    # Update state - mark iteration completed
    update_iteration "$state_file" "$i" "$output_json"
    mark_iteration_completed "$state_file" "$i"

    # Post-iteration completion check
    if check_completion "$session" "$state_file" "$output"; then
      local reason=$(check_completion "$session" "$state_file" "$output" 2>&1)
      echo ""
      echo "$reason"
      mark_complete "$state_file" "$reason"
      record_completion "complete" "$session" "$stage_type"
      return 0
    fi

    # Check for explicit completion signal
    if type check_output_signal &>/dev/null && check_output_signal "$output"; then
      echo ""
      echo "Completion signal received"
      mark_complete "$state_file" "completion_signal"
      record_completion "complete" "$session" "$stage_type"
      return 0
    fi

    echo ""
    echo "Waiting ${LOOP_DELAY} seconds..."
    sleep "$LOOP_DELAY"
  done

  echo ""
  echo "Maximum iterations ($max_iterations) reached"
  mark_complete "$state_file" "max_iterations"
  record_completion "max_iterations" "$session" "$stage_type"
  return 1
}

#-------------------------------------------------------------------------------
# Pipeline Mode
#-------------------------------------------------------------------------------

run_pipeline() {
  local pipeline_file=$1
  local session_override=$2

  # Resolve pipeline file
  if [ ! -f "$pipeline_file" ]; then
    if [ -f ".claude/pipelines/${pipeline_file}" ]; then
      pipeline_file=".claude/pipelines/${pipeline_file}"
    elif [ -f ".claude/pipelines/${pipeline_file}.yaml" ]; then
      pipeline_file=".claude/pipelines/${pipeline_file}.yaml"
    elif [ -f "$SCRIPT_DIR/pipelines/${pipeline_file}" ]; then
      pipeline_file="$SCRIPT_DIR/pipelines/${pipeline_file}"
    elif [ -f "$SCRIPT_DIR/pipelines/${pipeline_file}.yaml" ]; then
      pipeline_file="$SCRIPT_DIR/pipelines/${pipeline_file}.yaml"
    else
      echo "Error: Pipeline not found: $pipeline_file" >&2
      exit 1
    fi
  fi

  # Parse pipeline
  local pipeline_json=$(yaml_to_json "$pipeline_file")
  local pipeline_name=$(json_get "$pipeline_json" ".name" "pipeline")
  local session=${session_override:-"${pipeline_name}-$(date +%Y%m%d-%H%M%S)"}

  # Set up run directory
  local run_dir="$PROJECT_ROOT/.claude/pipeline-runs/$session"
  mkdir -p "$run_dir"
  cp "$pipeline_file" "$run_dir/pipeline.yaml"

  # Initialize state
  local state_file=$(init_state "$session" "pipeline" "$run_dir")

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Pipeline: $pipeline_name"
  echo "║  Session:  $session"
  echo "║  Run dir:  $run_dir"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  # Get defaults
  local default_model=$(json_get "$pipeline_json" ".defaults.model" "sonnet")

  # Execute each stage
  local stage_count=$(json_array_len "$pipeline_json" ".loops")

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    local stage_name=$(json_get "$pipeline_json" ".stages[$stage_idx].name")
    local stage_runs=$(json_get "$pipeline_json" ".stages[$stage_idx].runs" "1")
    local stage_model=$(json_get "$pipeline_json" ".stages[$stage_idx].model" "$default_model")
    # Support both "stage" (new) and "loop" (legacy) keywords
    local stage_type=$(json_get "$pipeline_json" ".stages[$stage_idx].stage" "")
    [ -z "$stage_type" ] && stage_type=$(json_get "$pipeline_json" ".stages[$stage_idx].loop" "")
    local stage_prompt=$(json_get "$pipeline_json" ".stages[$stage_idx].prompt" "")
    local stage_completion=$(json_get "$pipeline_json" ".stages[$stage_idx].completion" "")
    local stage_desc=$(json_get "$pipeline_json" ".stages[$stage_idx].description" "")

    # Create stage output directory
    local stage_dir="$run_dir/stage-$((stage_idx + 1))-$stage_name"
    mkdir -p "$stage_dir"

    echo "┌──────────────────────────────────────────────────────────────"
    echo "│ Loop $((stage_idx + 1))/$stage_count: $stage_name"
    [ -n "$stage_desc" ] && echo "│ $stage_desc"
    [ -n "$stage_type" ] && echo "│ Using stage type: $stage_type"
    echo "│ Runs: $stage_runs | Model: $stage_model"
    echo "└──────────────────────────────────────────────────────────────"
    echo ""

    update_stage "$state_file" "$stage_idx" "$stage_name" "running"

    # If using a stage type, load its config
    if [ -n "$stage_type" ]; then
      load_stage "$stage_type" || exit 1
      [ -z "$stage_prompt" ] && stage_prompt="$LOOP_PROMPT"
      [ -z "$stage_completion" ] && stage_completion="$LOOP_COMPLETION"
    fi

    # Initialize progress for this stage
    local progress_file=$(init_stage_progress "$stage_dir")

    # Get perspectives array
    local perspectives=$(json_get "$pipeline_json" ".stages[$stage_idx].perspectives" "")

    # Source completion strategy if specified
    if [ -n "$stage_completion" ]; then
      local completion_script="$LIB_DIR/completions/${stage_completion}.sh"
      [ -f "$completion_script" ] && source "$completion_script"
    fi

    # Run iterations
    for run_idx in $(seq 0 $((stage_runs - 1))); do
      echo "  Iteration $((run_idx + 1))/$stage_runs..."

      # Determine output file
      local output_file
      if [ "$stage_runs" -eq 1 ]; then
        output_file="$stage_dir/output.md"
      else
        output_file="$stage_dir/run-$run_idx.md"
      fi

      # Get perspective for this run
      local perspective=""
      if [ -n "$perspectives" ]; then
        perspective=$(echo "$perspectives" | jq -r ".[$run_idx] // empty" 2>/dev/null)
      fi

      # Build variables
      local vars_json=$(jq -n \
        --arg session "$session" \
        --arg iteration "$((run_idx + 1))" \
        --arg index "$run_idx" \
        --arg perspective "$perspective" \
        --arg output "$output_file" \
        --arg progress "$progress_file" \
        --arg run_dir "$run_dir" \
        --arg stage_idx "$stage_idx" \
        '{session: $session, iteration: $iteration, index: $index, perspective: $perspective, output: $output, progress: $progress, run_dir: $run_dir, stage_idx: $stage_idx}')

      # Resolve prompt
      local resolved_prompt=$(resolve_prompt "$stage_prompt" "$vars_json")

      # Execute
      set +e
      local output=$(execute_claude "$resolved_prompt" "$stage_model" "$output_file")
      set -e

      # Check completion
      if [ -n "$stage_completion" ] && type check_completion &>/dev/null; then
        if check_completion "$session" "$state_file" "$output"; then
          echo "  ✓ Completion condition met after $((run_idx + 1)) iterations"
          break
        fi
      fi

      [ "$run_idx" -lt "$((stage_runs - 1))" ] && sleep 2
    done

    update_stage "$state_file" "$stage_idx" "$stage_name" "complete"
    echo ""
  done

  mark_complete "$state_file" "all_loops_complete"

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  PIPELINE COMPLETE                                           ║"
  echo "╠══════════════════════════════════════════════════════════════╣"
  echo "║  Pipeline: $pipeline_name"
  echo "║  Session:  $session"
  echo "║  Loops:   $stage_count"
  echo "║  Output:   $run_dir"
  echo "╚══════════════════════════════════════════════════════════════╝"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

# Parse flags from remaining args
FORCE_FLAG=""
RESUME_FLAG=""
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --force) FORCE_FLAG="--force" ;;
    --resume) RESUME_FLAG="--resume" ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

# Cleanup stale locks on startup
cleanup_stale_locks

# Helper function to get state file path for a session
get_state_file_path() {
  local session=$1
  local run_dir="${PROJECT_ROOT}/.claude"
  echo "$run_dir/state.json"
}

# Helper function to check for failed session and handle resume
check_failed_session() {
  local session=$1
  local state_file=$2
  local max_iterations=$3

  # Get session status
  local status=$(get_session_status "$session" "$state_file")

  case "$status" in
    completed)
      echo "Session '$session' is already complete."
      echo "$SESSION_STATUS_DETAILS"
      exit 0
      ;;
    active)
      echo "Error: Session '$session' is currently active."
      echo "$SESSION_STATUS_DETAILS"
      echo ""
      echo "Use --force to override if you're sure it's not running."
      exit 1
      ;;
    failed)
      if [ "$RESUME_FLAG" = "--resume" ]; then
        return 0  # Allow resume
      else
        show_crash_recovery_info "$session" "$state_file" "$max_iterations"
        exit 1
      fi
      ;;
    none)
      if [ "$RESUME_FLAG" = "--resume" ]; then
        echo "Error: Cannot resume - no previous session '$session' found."
        exit 1
      fi
      return 0  # New session
      ;;
  esac
}

case "$MODE" in
  loop)
    LOOP_TYPE=${1:?"Usage: engine.sh loop <stage_type> [session] [max_iterations] [--force] [--resume]"}
    SESSION=${2:-"$LOOP_TYPE"}
    MAX_ITERATIONS=${3:-25}

    # Determine run directory and state file
    RUN_DIR="${PROJECT_ROOT}/.claude"
    STATE_FILE="$RUN_DIR/state.json"

    # Check for existing/failed session
    check_failed_session "$SESSION" "$STATE_FILE" "$MAX_ITERATIONS"

    # Determine start iteration
    START_ITERATION=1
    if [ "$RESUME_FLAG" = "--resume" ] && [ -f "$STATE_FILE" ]; then
      START_ITERATION=$(get_resume_iteration "$STATE_FILE")
      reset_for_resume "$STATE_FILE"
      echo "Resuming session '$SESSION' from iteration $START_ITERATION"
    fi

    # Acquire lock before starting
    if ! acquire_lock "$SESSION" "$FORCE_FLAG"; then
      exit 1
    fi

    # Ensure lock is released on exit
    trap 'release_lock "$SESSION"' EXIT

    run_stage "$LOOP_TYPE" "$SESSION" "$MAX_ITERATIONS" "$RUN_DIR" "0" "$START_ITERATION"
    ;;

  pipeline)
    PIPELINE_FILE=${1:?"Usage: engine.sh pipeline <pipeline.yaml> [session] [--force] [--resume]"}
    SESSION=$2

    # For pipelines, derive session name if not provided
    if [ -z "$SESSION" ]; then
      pipeline_json=$(yaml_to_json "$PIPELINE_FILE" 2>/dev/null || echo "{}")
      SESSION=$(json_get "$pipeline_json" ".name" "pipeline")-$(date +%Y%m%d-%H%M%S)
    fi

    # Determine run directory and state file for pipeline
    RUN_DIR="$PROJECT_ROOT/.claude/pipeline-runs/$SESSION"
    STATE_FILE="$RUN_DIR/state.json"

    # Check for existing/failed session (only if state file exists)
    if [ -f "$STATE_FILE" ]; then
      check_failed_session "$SESSION" "$STATE_FILE" "?"
    fi

    # Resume for pipelines is more complex - show warning
    if [ "$RESUME_FLAG" = "--resume" ]; then
      if [ -f "$STATE_FILE" ]; then
        echo "Warning: Pipeline resume support is limited."
        echo "The pipeline will restart from the beginning."
        echo "Previous state will be preserved in: $RUN_DIR"
        echo ""
      else
        echo "Error: Cannot resume - no previous pipeline session '$SESSION' found."
        exit 1
      fi
    fi

    # Acquire lock before starting
    if ! acquire_lock "$SESSION" "$FORCE_FLAG"; then
      exit 1
    fi

    # Ensure lock is released on exit (success, error, or signal)
    trap 'release_lock "$SESSION"' EXIT

    run_pipeline "$PIPELINE_FILE" "$SESSION"
    ;;

  status)
    # Show status of a session
    SESSION=${1:?"Usage: engine.sh status <session>"}
    STATE_FILE=$(get_state_file_path "$SESSION")

    status=$(get_session_status "$SESSION" "$STATE_FILE")
    echo "Session: $SESSION"
    echo "Status: $status"
    echo "$SESSION_STATUS_DETAILS"

    if [ "$status" = "failed" ]; then
      get_crash_info "$SESSION" "$STATE_FILE"
      echo ""
      echo "Last iteration started: $CRASH_LAST_ITERATION"
      echo "Last iteration completed: $CRASH_LAST_COMPLETED"
      [ -n "$CRASH_ERROR" ] && echo "Error: $CRASH_ERROR"
    fi
    ;;

  *)
    echo "Usage: engine.sh <loop|pipeline|status> <type_or_file> [session] [max_iterations] [--force] [--resume]"
    echo ""
    echo "Modes:"
    echo "  loop <type> [session] [max]  - Run a loop"
    echo "  pipeline <file> [session]     - Run a multi-stage pipeline"
    echo "  status <session>              - Check session status"
    echo ""
    echo "Options:"
    echo "  --force    Override existing session lock"
    echo "  --resume   Resume a failed/crashed session"
    echo ""
    echo "Available loops:"
    ls "$LOOPS_DIR" 2>/dev/null | while read d; do
      [ -d "$LOOPS_DIR/$d" ] && echo "  $d"
    done
    exit 1
    ;;
esac
