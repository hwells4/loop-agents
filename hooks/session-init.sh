#!/bin/bash
# Session initialization for Agent Pipelines
# Creates symlink, checks for running/completed loops

PROJECT_PATH="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# Create symlink to plugin (needed for tmux to find scripts)
if [ -n "$PLUGIN_ROOT" ]; then
  mkdir -p "$PROJECT_PATH/.claude"
  if [ ! -L "$PROJECT_PATH/.claude/agent-pipelines" ] || [ "$(readlink "$PROJECT_PATH/.claude/agent-pipelines")" != "$PLUGIN_ROOT" ]; then
    rm -f "$PROJECT_PATH/.claude/agent-pipelines" 2>/dev/null
    ln -sf "$PLUGIN_ROOT" "$PROJECT_PATH/.claude/agent-pipelines"
  fi
fi

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

  # Show ready beads for each running session
  if command -v bd &> /dev/null; then
    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^pipeline-" | sed 's/^loop-//'); do
      READY_OUTPUT=$(bd ready --label="pipeline/$session" 2>/dev/null | grep "\[" | wc -l | tr -d ' ')
      if [ "$READY_OUTPUT" -gt 0 ] 2>/dev/null; then
        echo ""
        echo "  Ready beads for loop-$session: $READY_OUTPUT"
      fi
    done
  fi

  # Check for stale sessions (>2 hours)
  if [ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/scripts/lib/warn-stale.sh" ]; then
    bash "$PLUGIN_ROOT/scripts/lib/warn-stale.sh"
  fi
fi

# Check dependencies and provide context
DEPS_OK=true
MISSING=""

if ! command -v tmux &> /dev/null; then
  MISSING="$MISSING tmux"
  DEPS_OK=false
fi

if ! command -v bd &> /dev/null; then
  MISSING="$MISSING beads(bd)"
  DEPS_OK=false
fi

if [ -n "$MISSING" ]; then
  echo ""
  echo "MISSING DEPENDENCIES:$MISSING"
  echo "  tmux: brew install tmux"
  echo "  bd:   brew install steveyegge/tap/bd"
fi

# Check if beads is initialized in this repo
if command -v bd &> /dev/null; then
  if ! bd list --limit 1 &> /dev/null; then
    echo ""
    echo "BEADS NOT INITIALIZED:"
    echo "  Run: bd init"
    echo "  This creates issues.json to track tasks for loop agents"
    DEPS_OK=false
  fi
fi

# Report status
if [ "$DEPS_OK" = true ]; then
  echo ""
  echo "LOOP AGENTS READY: Dependencies OK, beads initialized"
fi
