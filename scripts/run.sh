#!/bin/bash
# Unified Entry Point
# Usage: run.sh <loop|pipeline|lint|dry-run|status|tail> ...
#
# Everything is a pipeline. A "loop" is just a single-stage pipeline.
#
# Examples:
#   ./run.sh work auth 25             # Run work loop (shortcut for single-stage pipeline)
#   ./run.sh loop work auth 25        # Same as above (explicit)
#   ./run.sh pipeline full-refine.yaml myproject  # Run multi-stage pipeline
#   ./run.sh lint                     # Validate all loops and pipelines
#   ./run.sh lint loop work           # Validate specific loop
#   ./run.sh dry-run loop work auth   # Preview loop execution
#   ./run.sh status auth              # Check session status
#   ./run.sh tail auth                # Stream session events

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Parse global flags early
TMUX_FLAG="true"  # Default: run in tmux for persistent background execution
INPUT_FILES=()
REMAINING_ARGS=()
skip_next=false
for i in $(seq 1 $#); do
  arg="${!i}"
  if [ "$skip_next" = true ]; then
    skip_next=false
    continue
  fi
  case "$arg" in
    --foreground|--no-tmux) TMUX_FLAG="" ;;
    --tmux) TMUX_FLAG="true" ;;  # Explicit (redundant but clear)
    --provider=*) export PIPELINE_CLI_PROVIDER="${arg#*=}" ;;
    --model=*) export PIPELINE_CLI_MODEL="${arg#*=}" ;;
    --context=*) export PIPELINE_CLI_CONTEXT="${arg#*=}" ;;
    --input)
      next_i=$((i + 1))
      INPUT_FILES+=("${!next_i}")
      skip_next=true
      ;;
    *) REMAINING_ARGS+=("$arg") ;;
  esac
done
set -- "${REMAINING_ARGS[@]}"

# Export CLI inputs for pipeline engine
if [ ${#INPUT_FILES[@]} -gt 0 ]; then
  export PIPELINE_CLI_INPUTS=$(printf '%s\n' "${INPUT_FILES[@]}" | jq -R . | jq -s .)
fi

# Helper: wrap command in tmux for persistent background execution
run_in_tmux() {
  local session_name=$1
  shift
  local cmd="$*"

  # Check if tmux session already exists
  if tmux has-session -t "pipeline-${session_name}" 2>/dev/null; then
    echo "Error: tmux session 'pipeline-${session_name}' already exists" >&2
    echo "  Attach: tmux attach -t pipeline-${session_name}" >&2
    echo "  Kill:   tmux kill-session -t pipeline-${session_name}" >&2
    exit 1
  fi

  # Start in tmux
  tmux new-session -d -s "pipeline-${session_name}" -c "$(pwd)" "$cmd"

  # Verify startup
  sleep 1
  if tmux has-session -t "pipeline-${session_name}" 2>/dev/null; then
    echo "Session started in tmux: pipeline-${session_name}"
    echo ""
    echo "  Monitor: tmux capture-pane -t pipeline-${session_name} -p | tail -50"
    echo "  Attach:  tmux attach -t pipeline-${session_name}"
    echo "  Status:  ./scripts/run.sh status ${session_name}"
    echo "  Kill:    tmux kill-session -t pipeline-${session_name}"
  else
    echo "Error: Session failed to start" >&2
    exit 1
  fi
}

show_help() {
  echo "Usage: run.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  <stage-type> [session] [max]     Run a single-stage pipeline (shortcut)"
  echo "  loop <type> [session] [max]     Run a single-stage pipeline (explicit)"
  echo "  pipeline <file> [session]       Run a multi-stage pipeline"
  echo "  lint [loop|pipeline] [name]     Validate configurations"
  echo "  dry-run <loop|pipeline> <name> [session]  Preview execution"
  echo "  test [name] [--verbose]         Run tests (all or specific)"
  echo "  status <session>                Check session status"
  echo "  tail <session> [lines]          Stream event log"
  echo ""
  echo "Flags:"
  echo "  --foreground                    Run in foreground instead of tmux (default: tmux)"
  echo "  --force                         Override existing session lock"
  echo "  --resume                        Resume a crashed/failed session"
  echo "  --recompile                     Regenerate plan.json before running"
  echo "  --input <file>                  Initial input file for pipeline (can use multiple times)"
  echo "  --provider=<name>               Override provider (claude, codex)"
  echo "  --model=<name>                  Override model (opus, o3, etc.)"
  echo "  --context=<text>                Inject context into prompt via \${CONTEXT}"
  echo "  --verbose                       Show detailed test output"
  echo ""
  echo "Available stages:"
  for dir in "$SCRIPT_DIR"/stages/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    desc=$(grep "^description:" "$dir/stage.yaml" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
    echo "  $name - $desc"
  done
  echo ""
  echo "Available pipelines:"
  for f in "$SCRIPT_DIR"/pipelines/*.yaml; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .yaml)
    desc=$(grep "^description:" "$f" 2>/dev/null | cut -d: -f2- | sed 's/^[[:space:]]*//')
    echo "  $name - $desc"
  done
  echo ""
  echo "Pipeline schema: use 'nodes:' (deprecated: 'stages:')."
}

if [ -z "$1" ]; then
  show_help
  exit 1
fi

case "$1" in
  lint)
    source "$LIB_DIR/validate.sh"
    shift
    lint_all "$@"
    exit $?
    ;;

  dry-run)
    source "$LIB_DIR/validate.sh"
    shift
    if [ -z "$1" ] || [ -z "$2" ]; then
      echo "Usage: run.sh dry-run <loop|pipeline> <name> [session]"
      exit 1
    fi
    target_type=$1
    target_name=$2
    session=${3:-"preview"}

    if [ "$target_type" = "loop" ]; then
      dry_run_loop "$target_name" "$session"
    elif [ "$target_type" = "pipeline" ]; then
      dry_run_pipeline "$target_name" "$session"
    else
      echo "Error: Unknown target type '$target_type'. Use 'loop' or 'pipeline'."
      exit 1
    fi
    exit $?
    ;;

  test)
    shift
    TESTS_DIR="$SCRIPT_DIR/tests"

    # Parse flags
    TEST_VERBOSE=false
    TEST_TARGET=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --verbose|-v) TEST_VERBOSE=true; shift ;;
        --ci) TEST_CI=true; shift ;;
        *) TEST_TARGET=$1; shift ;;
      esac
    done
    export TEST_VERBOSE

    # Check if tests directory exists
    if [ ! -d "$TESTS_DIR" ]; then
      echo "No tests directory found at: $TESTS_DIR"
      exit 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Agent Pipelines Test Suite"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Source test library
    source "$LIB_DIR/test.sh"

    # Run specific test or all tests
    if [ -n "$TEST_TARGET" ]; then
      # Run specific test file
      test_file="$TESTS_DIR/test_${TEST_TARGET}.sh"
      if [ -f "$test_file" ]; then
        source "$test_file"
      else
        echo "Test file not found: $test_file"
        echo "Available tests:"
        while IFS= read -r f; do
          name=$(basename "$f" .sh | sed 's/^test_//')
          echo "  $name"
        done < <(ls "$TESTS_DIR"/test_*.sh 2>/dev/null)
        exit 1
      fi
    else
      # Run all tests
      for test_file in "$TESTS_DIR"/test_*.sh; do
        [ -f "$test_file" ] || continue
        echo "Running: $(basename "$test_file")"
        echo ""
        source "$test_file"
      done
    fi

    # Print summary
    test_summary
    exit $?
    ;;

  status)
    shift
    session=$1
    if [ -z "$session" ]; then
      echo "Usage: run.sh status <session>"
      exit 1
    fi
    source "$LIB_DIR/events.sh"
    if ! events_print_status "$session"; then
      exit 1
    fi
    exit 0
    ;;

  tail)
    shift
    session=$1
    if [ -z "$session" ]; then
      echo "Usage: run.sh tail <session> [lines]"
      exit 1
    fi
    source "$LIB_DIR/events.sh"
    lines=${2:-${EVENTS_TAIL_LINES:-50}}
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
      lines=${EVENTS_TAIL_LINES:-50}
    fi
    run_root=$(events_default_run_root)
    events_file="$run_root/$session/events.jsonl"
    if [ ! -f "$events_file" ]; then
      echo "No events found: $session"
      exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      if ! echo "$line" | jq -e '.' >/dev/null 2>&1; then
        continue
      fi
      formatted=$(events_format_event_line "$line")
      [ -n "$formatted" ] && echo "$formatted"
    done < <(tail -n "$lines" -F "$events_file")
    exit 0
    ;;

  loop)
    # Convert loop command to single-stage pipeline
    # Usage: run.sh loop <type> [session] [max] [--force] [--resume] [--tmux]
    shift
    STAGE_TYPE=${1:?"Usage: run.sh loop <type> [session] [max]"}
    SESSION_NAME=${2:-"$STAGE_TYPE"}
    shift

    if [ "$TMUX_FLAG" = "true" ]; then
      run_in_tmux "$SESSION_NAME" "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$STAGE_TYPE" "$@"
      exit 0
    else
      exec "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$STAGE_TYPE" "$@"
    fi
    ;;

  pipeline)
    shift
    PIPELINE_FILE=${1:?"Usage: run.sh pipeline <file> [session]"}
    SESSION_NAME=${2:-""}

    # Derive session name from pipeline if not provided
    if [ -z "$SESSION_NAME" ]; then
      source "$LIB_DIR/yaml.sh"
      pipeline_json=$(yaml_to_json "$PIPELINE_FILE" 2>/dev/null || echo "{}")
      SESSION_NAME=$(json_get "$pipeline_json" ".name" "pipeline")-$(date +%Y%m%d-%H%M%S)
    fi

    if [ "$TMUX_FLAG" = "true" ]; then
      run_in_tmux "$SESSION_NAME" "$SCRIPT_DIR/engine.sh" pipeline "$PIPELINE_FILE" "$SESSION_NAME" "${@:3}"
      exit 0
    else
      exec "$SCRIPT_DIR/engine.sh" pipeline "$PIPELINE_FILE" "$SESSION_NAME" "${@:3}"
    fi
    ;;

  -h|--help|help)
    show_help
    exit 0
    ;;

  *)
    # Check if first arg is a valid stage type (shortcut syntax)
    # e.g., ./run.sh work auth 25 → same as ./run.sh loop work auth 25
    if [ -d "$SCRIPT_DIR/stages/$1" ]; then
      STAGE_TYPE=$1
      SESSION_NAME=${2:-"$STAGE_TYPE"}
      shift

      if [ "$TMUX_FLAG" = "true" ]; then
        run_in_tmux "$SESSION_NAME" "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$STAGE_TYPE" "$@"
        exit 0
      else
        exec "$SCRIPT_DIR/engine.sh" pipeline --single-stage "$STAGE_TYPE" "$@"
      fi
    fi

    echo "Error: Unknown command '$1'"
    echo ""
    show_help
    exit 1
    ;;
esac
