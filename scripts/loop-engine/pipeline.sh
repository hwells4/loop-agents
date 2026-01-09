#!/bin/bash
set -e

# Pipeline Runner - Execute loops in sequence
# Usage: pipeline.sh <pipeline_name> [session_name]

PIPELINE_NAME=${1:?"Usage: pipeline.sh <pipeline_name> [session_name]"}
SESSION_NAME=${2:-"$PIPELINE_NAME-$(date +%Y%m%d-%H%M)"}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINES_DIR="$SCRIPT_DIR/../pipelines"
PIPELINE_FILE="$PIPELINES_DIR/${PIPELINE_NAME}.yaml"

if [ ! -f "$PIPELINE_FILE" ]; then
  echo "Error: Pipeline not found: $PIPELINE_FILE"
  echo ""
  echo "Available pipelines:"
  ls "$PIPELINES_DIR"/*.yaml 2>/dev/null | while read f; do
    echo "  $(basename "$f" .yaml)"
  done
  exit 1
fi

echo "═══════════════════════════════════════"
echo "  Pipeline: $PIPELINE_NAME"
echo "  Session: $SESSION_NAME"
echo "═══════════════════════════════════════"
echo ""

# Parse pipeline YAML (simple format)
# Format:
#   steps:
#     - loop: improve-plan
#       max: 5
#     - loop: refine-beads
#       max: 5

STEP_NUM=0
CURRENT_LOOP=""
CURRENT_MAX=""

run_step() {
  if [ -n "$CURRENT_LOOP" ]; then
    STEP_NUM=$((STEP_NUM + 1))
    MAX=${CURRENT_MAX:-10}

    echo ""
    echo "┌─────────────────────────────────────"
    echo "│ Step $STEP_NUM: $CURRENT_LOOP (max $MAX iterations)"
    echo "└─────────────────────────────────────"
    echo ""

    "$SCRIPT_DIR/run.sh" "$CURRENT_LOOP" "$SESSION_NAME" "$MAX"

    RESULT=$?
    if [ $RESULT -ne 0 ] && [ $RESULT -ne 1 ]; then
      echo "Step failed with exit code $RESULT"
      exit $RESULT
    fi

    echo ""
    echo "✓ Step $STEP_NUM complete"
  fi
}

while IFS=': ' read -r key value || [ -n "$key" ]; do
  # Trim whitespace
  key=$(echo "$key" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  value=$(echo "$value" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  # Skip comments and empty lines
  [[ "$key" =~ ^#.*$ ]] && continue
  [[ -z "$key" ]] && continue

  case "$key" in
    "- loop")
      # New step starting - run previous step first
      run_step
      CURRENT_LOOP="$value"
      CURRENT_MAX=""
      ;;
    "max")
      CURRENT_MAX="$value"
      ;;
  esac
done < "$PIPELINE_FILE"

# Run final step
run_step

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              PIPELINE COMPLETE                           ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Pipeline: $PIPELINE_NAME"
echo "║  Session: $SESSION_NAME"
echo "║  Steps completed: $STEP_NUM"
echo "╚══════════════════════════════════════════════════════════╝"
