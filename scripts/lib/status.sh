#!/bin/bash
# Status File Management (v3)
# Handles the universal status.json format
#
# Every agent writes the same status.json:
# {
#   "decision": "continue|stop|error",
#   "reason": "Brief explanation",
#   "summary": "What happened this iteration",
#   "work": {"items_completed": [], "files_touched": []},
#   "errors": [],
#   "timestamp": "ISO 8601"
# }

# Validate status.json
# Usage: validate_status "$status_file"
# Returns: 0 if valid, 1 if invalid
validate_status() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "Error: Status file not found: $status_file" >&2
    return 1
  fi

  # Check if it's valid JSON
  if ! jq -e '.' "$status_file" &>/dev/null; then
    echo "Error: Status file is not valid JSON: $status_file" >&2
    return 1
  fi

  local decision=$(jq -r '.decision // "missing"' "$status_file" 2>/dev/null)

  case "$decision" in
    continue|stop|error)
      return 0
      ;;
    missing)
      echo "Error: Status file missing 'decision' field" >&2
      return 1
      ;;
    *)
      echo "Error: Invalid decision value: $decision (must be continue|stop|error)" >&2
      return 1
      ;;
  esac
}

# Read status decision
# Usage: get_status_decision "$status_file"
# Returns: decision value or "error" if file doesn't exist/invalid
get_status_decision() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "error"
    return 1
  fi

  # Check if it's valid JSON first (fail fast on malformed status)
  if ! jq -e '.' "$status_file" &>/dev/null; then
    echo "error"
    return 1
  fi

  jq -r '.decision // "error"' "$status_file" 2>/dev/null || echo "error"
}

# Read status reason
# Usage: get_status_reason "$status_file"
get_status_reason() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo ""
    return
  fi

  jq -r '.reason // ""' "$status_file" 2>/dev/null || echo ""
}

# Read status summary
# Usage: get_status_summary "$status_file"
get_status_summary() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo ""
    return
  fi

  jq -r '.summary // ""' "$status_file" 2>/dev/null || echo ""
}

# Read files touched from status
# Usage: get_status_files "$status_file"
# Returns: JSON array of file paths
get_status_files() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "[]"
    return
  fi

  jq -c '.work.files_touched // []' "$status_file" 2>/dev/null || echo "[]"
}

# Read items completed from status
# Usage: get_status_items "$status_file"
# Returns: JSON array of item identifiers
get_status_items() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "[]"
    return
  fi

  jq -c '.work.items_completed // []' "$status_file" 2>/dev/null || echo "[]"
}

# Read errors from status
# Usage: get_status_errors "$status_file"
# Returns: JSON array of error messages
get_status_errors() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo "[]"
    return
  fi

  jq -c '.errors // []' "$status_file" 2>/dev/null || echo "[]"
}

# Create error status (when agent crashes, times out, or doesn't write status)
# Usage: create_error_status "$status_file" "$error_message"
create_error_status() {
  local status_file=$1
  local error=$2
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Ensure parent directory exists
  local status_dir=$(dirname "$status_file")
  [ -n "$status_dir" ] && [ "$status_dir" != "." ] && mkdir -p "$status_dir"

  jq -n \
    --arg error "$error" \
    --arg ts "$timestamp" \
    '{
      decision: "error",
      reason: $error,
      summary: "Iteration failed due to error",
      work: {items_completed: [], files_touched: []},
      errors: [$error],
      timestamp: $ts
    }' > "$status_file"
}

# Create a default continue status (for backward compatibility or missing status)
# Usage: create_default_status "$status_file" "$summary"
create_default_status() {
  local status_file=$1
  local summary=${2:-"Iteration completed (no status written by agent)"}
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Ensure parent directory exists
  local status_dir=$(dirname "$status_file")
  [ -n "$status_dir" ] && [ "$status_dir" != "." ] && mkdir -p "$status_dir"

  jq -n \
    --arg summary "$summary" \
    --arg ts "$timestamp" \
    '{
      decision: "continue",
      reason: "Agent did not write status - assuming continue",
      summary: $summary,
      work: {items_completed: [], files_touched: []},
      errors: [],
      timestamp: $ts
    }' > "$status_file"
}

# Extract status data for state history
# Usage: status_to_history_json "$status_file"
# Returns: JSON object suitable for appending to state history
status_to_history_json() {
  local status_file=$1

  if [ ! -f "$status_file" ]; then
    echo '{"decision": "continue"}'
    return
  fi

  # Extract relevant fields for history
  jq -c '{
    decision: (.decision // "continue"),
    reason: (.reason // ""),
    summary: (.summary // ""),
    files_touched: (.work.files_touched // []),
    items_completed: (.work.items_completed // []),
    errors: (.errors // [])
  }' "$status_file" 2>/dev/null || echo '{"decision": "continue"}'
}
