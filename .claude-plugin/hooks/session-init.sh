#!/bin/bash
# Session initialization for Agent Pipelines
# Checks for running/completed loops

PROJECT_PATH="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# Check for completed loops since last session
COMPLETIONS_FILE="$PROJECT_PATH/.claude/loop-completions.json"
if [ -f "$COMPLETIONS_FILE" ]; then
  if command -v jq &> /dev/null; then
    COUNT=$(jq 'length' "$COMPLETIONS_FILE" 2>/dev/null || echo "0")
    if [ "$COUNT" -gt 0 ]; then
      echo ""
      echo "COMPLETED LOOPS SINCE LAST SESSION:"
      jq -r '.[] | "  \(.status): loop-\(.session) at \(.completed_at)"' "$COMPLETIONS_FILE"
      rm "$COMPLETIONS_FILE"
    fi
  else
    echo ""
    echo "LOOPS COMPLETED (install jq for details):"
    cat "$COMPLETIONS_FILE"
    rm "$COMPLETIONS_FILE"
  fi
fi

# Check for running tmux loop sessions
PIPELINE_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^pipeline-" | wc -l | tr -d ' ')
if [ "$PIPELINE_SESSIONS" -gt 0 ]; then
  echo ""
  echo "RUNNING PIPELINE SESSIONS: $PIPELINE_SESSIONS"
  tmux list-sessions 2>/dev/null | grep "^pipeline-"
  echo ""
  echo "  Check:  tmux capture-pane -t SESSION -p | tail -20"
  echo "  Attach: tmux attach -t SESSION"

  # Check for stale sessions (>2 hours)
  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/lib/warn-stale.sh" ]; then
    bash "$PLUGIN_ROOT/scripts/lib/warn-stale.sh"
  fi
fi

# Check dependencies
MISSING=""
if ! command -v tmux &> /dev/null; then
  MISSING="$MISSING tmux"
fi
if ! command -v bd &> /dev/null; then
  MISSING="$MISSING beads(bd)"
fi

if [ -n "$MISSING" ]; then
  echo ""
  echo "MISSING DEPENDENCIES:$MISSING"
  echo "  tmux: brew install tmux"
  echo "  bd:   brew install steveyegge/tap/bd"
fi
