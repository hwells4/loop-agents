#!/bin/bash
set -e

# Loop Agent - Single Run Test Mode
# Runs one iteration to test behavior before running AFK mode
# Uses beads for task management - each story is a bead tagged with loop/{session}

SESSION_NAME=${1:-"default"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"

export SESSION_NAME

# Progress files stored in project, not plugin
PROGRESS_DIR="$PROJECT_ROOT/.claude/loop-progress"
PROGRESS_FILE="$PROGRESS_DIR/progress-${SESSION_NAME}.txt"

echo "Loop Agent (Test Mode - Single Run)"
echo "Session: $SESSION_NAME"
echo "Project: $PROJECT_ROOT"
echo ""

# Initialize progress file if it doesn't exist
mkdir -p "$PROGRESS_DIR"
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Progress: $SESSION_NAME" > "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
  echo "## Codebase Patterns" >> "$PROGRESS_FILE"
  echo "(Add patterns discovered during implementation here)" >> "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
  echo "" >> "$PROGRESS_FILE"
fi

# Check if any work exists
REMAINING=$(bd ready --label="loop/$SESSION_NAME" 2>/dev/null | grep -c "^" || echo "0")
if [ "$REMAINING" -eq 0 ]; then
  echo "No stories found for session: $SESSION_NAME"
  echo "Create stories first with: bd create --label=loop/$SESSION_NAME ..."
  exit 1
fi

echo "$REMAINING stories available"
echo ""
echo "═══════════════════════════════════════"
echo "         Running Single Iteration"
echo "═══════════════════════════════════════"
echo ""

# Pipe prompt into Claude Code with session context substituted
OUTPUT=$(cat "$SCRIPT_DIR/prompt.md" \
  | sed "s|\${SESSION_NAME}|$SESSION_NAME|g" \
  | sed "s|\${PROGRESS_FILE}|$PROGRESS_FILE|g" \
  | claude --model opus --dangerously-skip-permissions 2>&1 \
  | tee /dev/stderr) || true

echo ""
echo "═══════════════════════════════════════"

# Check for completion signal
if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
  echo "Agent signaled completion"
  echo "All tasks done - check: bd list --label=loop/$SESSION_NAME"
else
  REMAINING_AFTER=$(bd ready --label="loop/$SESSION_NAME" 2>/dev/null | grep -c "^" || echo "0")
  echo "Agent completed one iteration"
  echo "$REMAINING_AFTER stories remaining"
  echo "Review progress: cat $PROGRESS_FILE"
  echo "Ready for AFK mode: .claude/loop-agents/scripts/loop.sh 50 $SESSION_NAME"
fi

echo ""
exit 0
