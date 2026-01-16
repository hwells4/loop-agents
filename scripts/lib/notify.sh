#!/bin/bash
# Desktop Notifications and Completion Logging

NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$NOTIFY_SCRIPT_DIR}"

if [ -f "$LIB_DIR/lock.sh" ]; then
  source "$LIB_DIR/lock.sh"
fi

# Send desktop notification
# Usage: notify "$title" "$message"
notify() {
  local title=$1
  local message=$2

  if command -v osascript &>/dev/null; then
    # macOS - escape backslashes and quotes to prevent AppleScript injection
    title="${title//\\/\\\\}"
    title="${title//\"/\\\"}"
    message="${message//\\/\\\\}"
    message="${message//\"/\\\"}"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    # Linux
    notify-send "$title" "$message" 2>/dev/null || true
  fi
}

# Record completion to JSON log
# Usage: record_completion "$status" "$session" "$type"
_notify_write_completion() {
  local file=$1
  local entry=$2

  if [ -f "$file" ]; then
    jq --argjson entry "$entry" '. += [$entry]' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    echo "[$entry]" > "$file"
  fi
}

record_completion() {
  local status=$1
  local session=$2
  local type=${3:-"unknown"}
  local file="$PROJECT_ROOT/.claude/loop-completions.json"
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  mkdir -p "$PROJECT_ROOT/.claude"

  # Use jq --arg for safe JSON construction (prevents injection)
  local entry=$(jq -n \
    --arg session "$session" \
    --arg type "$type" \
    --arg status "$status" \
    --arg ts "$timestamp" \
    '{session: $session, type: $type, status: $status, completed_at: $ts}')

  if type with_file_lock &>/dev/null; then
    with_file_lock "$file" _notify_write_completion "$file" "$entry"
  else
    _notify_write_completion "$file" "$entry"
  fi

  notify "Loop Agent" "$type $session: $status"
}
