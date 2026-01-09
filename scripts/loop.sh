#!/bin/bash
set -e

# Loop Agent - AFK Multi-Iteration Mode
# Runs Claude Code in a loop until all tasks complete or max iterations reached
# Uses beads for task management - each story is a bead tagged with loop/{session}

MAX_ITERATIONS=${1:-25}
SESSION_NAME=${2:-"default"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"  # tmux starts in project directory

# Export for use in prompts
export SESSION_NAME

# Export for loop-stop-gate.py hook (only activates when these are set)
export CLAUDE_LOOP_AGENT=1
export CLAUDE_LOOP_SESSION="$SESSION_NAME"

# Progress files stored in project, not plugin
PROGRESS_DIR="$PROJECT_ROOT/.claude/loop-progress"
PROGRESS_FILE="$PROGRESS_DIR/progress-${SESSION_NAME}.txt"

# Record completion status for notification system
record_completion() {
  local status=$1
  local session=$2
  local file="$PROJECT_ROOT/.claude/loop-completions.json"
  local timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Ensure .claude directory exists
  mkdir -p "$PROJECT_ROOT/.claude"

  # Create JSON entry
  local entry="{\"session\": \"$session\", \"status\": \"$status\", \"completed_at\": \"$timestamp\"}"

  if [ -f "$file" ]; then
    # Append to existing array using jq if available, else recreate
    if command -v jq &> /dev/null; then
      jq ". += [$entry]" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    else
      # Fallback: read existing, append manually
      local existing=$(cat "$file" | tr -d '\n' | sed 's/]$//')
      echo "$existing, $entry]" > "$file"
    fi
  else
    echo "[$entry]" > "$file"
  fi

  # Desktop notification (cross-platform)
  if command -v osascript &> /dev/null; then
    # macOS
    osascript -e "display notification \"Loop $session $status\" with title \"Loop Agent\"" 2>/dev/null || true
  elif command -v notify-send &> /dev/null; then
    # Linux
    notify-send "Loop Agent" "Loop $session $status" 2>/dev/null || true
  fi
}

echo "Starting Loop Agent (AFK Mode)"
echo "Max iterations: $MAX_ITERATIONS"
echo "Session: $SESSION_NAME"
echo "Project: $PROJECT_ROOT"
echo ""

# Initialize progress file if it doesn't exist
mkdir -p "$PROGRESS_DIR"
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Progress: $SESSION_NAME" > "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
  echo "Verify: (none)" >> "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
  echo "## Codebase Patterns" >> "$PROGRESS_FILE"
  echo "(Add patterns discovered during implementation here)" >> "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo "═══════════════════════════════════════"
  echo "    Iteration $i of $MAX_ITERATIONS"
  echo "    Session: $SESSION_NAME"
  echo "═══════════════════════════════════════"
  echo ""

  # Check if any work remains BEFORE starting iteration
  REMAINING=$(bd ready --label="loop/$SESSION_NAME" 2>/dev/null | grep -c "^" || echo "0")
  if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "All tasks complete!"
    record_completion "complete" "$SESSION_NAME"
    exit 0
  fi

  echo "$REMAINING stories remaining"
  echo ""

  # Pipe prompt into Claude Code with session context substituted
  # Use sed to replace both SESSION_NAME and PROGRESS_FILE placeholders
  OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" \
    | sed "s|\${SESSION_NAME}|$SESSION_NAME|g" \
    | sed "s|\${PROGRESS_FILE}|$PROGRESS_FILE|g" \
    | claude --model opus --dangerously-skip-permissions 2>&1 \
    | tee /dev/stderr) || true

  # Check for completion signal (backup check)
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "All tasks complete!"
    record_completion "complete" "$SESSION_NAME"
    exit 0
  fi

  echo ""
  echo "Waiting 3 seconds before next iteration..."
  sleep 3
done

echo ""
echo "Maximum iterations ($MAX_ITERATIONS) reached"
echo "Check $PROGRESS_FILE for status"
record_completion "max_iterations" "$SESSION_NAME"
exit 1
