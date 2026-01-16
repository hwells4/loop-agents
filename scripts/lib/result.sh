#!/bin/bash
# Result File Management (v3)
# Handles the universal result.json format
#
# Every agent writes the same result.json:
# {
#   "summary": "what changed",
#   "work": {
#     "items_completed": [],
#     "files_touched": []
#   },
#   "artifacts": {
#     "outputs": [],
#     "paths": []
#   },
#   "signals": {
#     "plateau_suspected": false,
#     "risk": "low",
#     "notes": ""
#   }
# }

# Resolve a result or status file path, preferring the supplied path if it exists.
# Usage: result_resolve_file "/path/to/result.json"
result_resolve_file() {
  local path=$1

  if [ -n "$path" ] && [ -f "$path" ]; then
    echo "$path"
    return 0
  fi

  if [[ "$path" == */status.json ]]; then
    local alt="${path%status.json}result.json"
    if [ -f "$alt" ]; then
      echo "$alt"
      return 0
    fi
  fi

  if [[ "$path" == */result.json ]]; then
    local alt="${path%result.json}status.json"
    if [ -f "$alt" ]; then
      echo "$alt"
      return 0
    fi
  fi

  echo "$path"
  return 1
}

result_write_atomic() {
  local path=$1
  local content=$2
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"
  local tmp_file
  tmp_file=$(mktemp)
  printf '%s\n' "$content" > "$tmp_file"
  mv "$tmp_file" "$path"
}

result_is_valid_json() {
  local path=$1
  jq -e '.' "$path" >/dev/null 2>&1
}

result_normalize_json() {
  local input_json=$1

  echo "$input_json" | jq -c '{
    summary: (.summary // ""),
    work: {
      items_completed: (if ((.work.items_completed // null) | type) == "array" then .work.items_completed else [] end),
      files_touched: (if ((.work.files_touched // null) | type) == "array" then .work.files_touched else [] end)
    },
    artifacts: {
      outputs: (if ((.artifacts.outputs // null) | type) == "array" then .artifacts.outputs else [] end),
      paths: (if ((.artifacts.paths // null) | type) == "array" then .artifacts.paths else [] end)
    },
    signals: {
      plateau_suspected: (if ((.signals.plateau_suspected // null) | type) == "boolean" then .signals.plateau_suspected else false end),
      risk: (if ((.signals.risk // null) | type) == "string" then .signals.risk else "low" end),
      notes: (if ((.signals.notes // null) | type) == "string" then .signals.notes else "" end)
    }
  }'
}

result_validate_json() {
  local input_json=$1

  echo "$input_json" | jq -e '
    type == "object"
    and (.summary | type == "string")
    and (.work | type == "object")
    and (.work.items_completed | type == "array")
    and (.work.files_touched | type == "array")
    and (.artifacts | type == "object")
    and (.artifacts.outputs | type == "array")
    and (.artifacts.paths | type == "array")
    and (.signals | type == "object")
    and (.signals.plateau_suspected | type == "boolean")
    and (.signals.risk | type == "string")
    and (.signals.notes | type == "string")
  ' >/dev/null 2>&1
}

validate_result() {
  local result_file=$1

  if [ ! -f "$result_file" ]; then
    echo "Error: Result file not found: $result_file" >&2
    return 1
  fi

  if ! result_is_valid_json "$result_file"; then
    echo "Error: Result file is not valid JSON: $result_file" >&2
    return 1
  fi

  local normalized
  normalized=$(result_normalize_json "$(cat "$result_file")")
  if ! result_validate_json "$normalized"; then
    echo "Error: Result file has invalid schema: $result_file" >&2
    return 1
  fi

  result_write_atomic "$result_file" "$normalized"
}

result_from_status() {
  local status_file=$1

  if [ ! -f "$status_file" ] || ! result_is_valid_json "$status_file"; then
    return 1
  fi

  jq -c '{
    summary: (.summary // ""),
    work: {
      items_completed: (.work.items_completed // []),
      files_touched: (.work.files_touched // [])
    },
    artifacts: {
      outputs: [],
      paths: []
    },
    signals: {
      plateau_suspected: ((.decision // "") == "stop"),
      risk: (if ((.decision // "") == "error" or (.errors // [] | length > 0)) then "high" else "low" end),
      notes: (if (.reason // "") != "" then .reason else (.errors[0] // "") end)
    }
  }' "$status_file"
}

create_error_result() {
  local result_file=$1
  local error=$2

  local summary="Iteration failed: ${error}"
  local result_json
  result_json=$(jq -n \
    --arg summary "$summary" \
    --arg notes "$error" \
    '{
      summary: $summary,
      work: {items_completed: [], files_touched: []},
      artifacts: {outputs: [], paths: []},
      signals: {plateau_suspected: false, risk: "high", notes: $notes}
    }')

  result_write_atomic "$result_file" "$result_json"
}

create_default_result() {
  local result_file=$1
  local summary=${2:-"Iteration completed (no result written by agent)"}

  local result_json
  result_json=$(jq -n \
    --arg summary "$summary" \
    '{
      summary: $summary,
      work: {items_completed: [], files_touched: []},
      artifacts: {outputs: [], paths: []},
      signals: {plateau_suspected: false, risk: "low", notes: ""}
    }')

  result_write_atomic "$result_file" "$result_json"
}

result_decision_hint() {
  local path=$1
  local resolved
  resolved=$(result_resolve_file "$path" || true)

  if [ ! -f "$resolved" ] || ! result_is_valid_json "$resolved"; then
    echo "error"
    return 1
  fi

  if jq -e 'has("decision")' "$resolved" >/dev/null 2>&1; then
    jq -r '.decision // "continue"' "$resolved" 2>/dev/null || echo "continue"
    return 0
  fi

  local plateau
  plateau=$(jq -r '.signals.plateau_suspected // false' "$resolved" 2>/dev/null)
  local risk
  risk=$(jq -r '.signals.risk // "low"' "$resolved" 2>/dev/null)

  if [ "$risk" = "high" ]; then
    echo "error"
  elif [ "$plateau" = "true" ]; then
    echo "stop"
  else
    echo "continue"
  fi
}

result_reason_hint() {
  local path=$1
  local resolved
  resolved=$(result_resolve_file "$path" || true)

  if [ ! -f "$resolved" ] || ! result_is_valid_json "$resolved"; then
    echo ""
    return 1
  fi

  if jq -e 'has("decision")' "$resolved" >/dev/null 2>&1; then
    jq -r '.reason // ""' "$resolved" 2>/dev/null || echo ""
    return 0
  fi

  jq -r '.signals.notes // .summary // ""' "$resolved" 2>/dev/null || echo ""
}

result_to_history_json() {
  local path=$1
  local resolved
  resolved=$(result_resolve_file "$path" || true)

  if [ ! -f "$resolved" ] || ! result_is_valid_json "$resolved"; then
    echo '{"decision": "error"}'
    return
  fi

  if jq -e 'has("decision")' "$resolved" >/dev/null 2>&1; then
    jq -c '{
      decision: (.decision // "continue"),
      reason: (.reason // ""),
      summary: (.summary // ""),
      files_touched: (.work.files_touched // []),
      items_completed: (.work.items_completed // []),
      errors: (.errors // [])
    }' "$resolved" 2>/dev/null || echo '{"decision": "continue"}'
    return
  fi

  local normalized
  normalized=$(result_normalize_json "$(cat "$resolved")")
  local decision
  decision=$(result_decision_hint "$resolved" 2>/dev/null || echo "continue")
  local reason
  reason=$(result_reason_hint "$resolved" 2>/dev/null || echo "")

  echo "$normalized" | jq -c \
    --arg decision "$decision" \
    --arg reason "$reason" \
    '{
      decision: $decision,
      reason: $reason,
      summary: .summary,
      files_touched: .work.files_touched,
      items_completed: .work.items_completed,
      signals: .signals
    }'
}
