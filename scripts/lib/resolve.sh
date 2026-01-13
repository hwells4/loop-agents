#!/bin/bash
# Unified Variable Resolution
# Resolves all variables in prompt templates for both loops and pipelines
#
# v3 Variables (preferred):
#   ${CTX}                        - Path to context.json (full context)
#   ${STATUS}                     - Path to write status.json
#   ${PROGRESS}                   - Path to progress file
#   ${OUTPUT}                     - Path to write output
#
# v2 Variables (deprecated, still supported):
#   ${SESSION} / ${SESSION_NAME}  - Session name
#   ${ITERATION}                  - Current iteration (1-based)
#   ${INDEX}                      - Current run index (0-based)
#   ${PERSPECTIVE}                - Current perspective (for fan-out)
#   ${OUTPUT_PATH}                - Path for tracked output (if configured in stage.yaml)
#   ${PROGRESS_FILE}              - Alias for ${PROGRESS}
#
# Note: Inter-stage inputs are handled via context.json (see inputs.from_stage)
# Agents should read ${CTX} and parse .inputs.from_stage for previous stage outputs

# Resolve all variables in a prompt template
# Usage: resolve_prompt "$template" "$vars"
# $vars: context.json path (v3 mode) OR JSON object (legacy mode)
#
# Note: The v3 file-based mode (when $vars is a .json file path) is currently
# unused by engine.sh but retained for potential direct usage and testing.
resolve_prompt() {
  local template=$1
  local vars=$2

  local resolved="$template"

  # v3 mode: second arg is a context.json file path
  if [ -f "$vars" ] && [[ "$vars" == *.json ]]; then
    local context_file="$vars"
    local ctx_json=$(cat "$context_file" 2>/dev/null || echo "{}")

    # Resolve v3 convenience paths
    local ctx_progress=$(echo "$ctx_json" | jq -r '.paths.progress // ""')
    local ctx_output=$(echo "$ctx_json" | jq -r '.paths.output // ""')
    local ctx_status=$(echo "$ctx_json" | jq -r '.paths.status // ""')

    resolved="${resolved//\$\{CTX\}/$context_file}"
    resolved="${resolved//\$\{STATUS\}/$ctx_status}"
    resolved="${resolved//\$\{PROGRESS\}/$ctx_progress}"
    resolved="${resolved//\$\{OUTPUT\}/$ctx_output}"

    # DEPRECATED: Keep old variables working during migration
    local ctx_session=$(echo "$ctx_json" | jq -r '.session // ""')
    local ctx_iteration=$(echo "$ctx_json" | jq -r '.iteration // ""')
    resolved="${resolved//\$\{SESSION\}/$ctx_session}"
    resolved="${resolved//\$\{SESSION_NAME\}/$ctx_session}"
    resolved="${resolved//\$\{ITERATION\}/$ctx_iteration}"
    resolved="${resolved//\$\{PROGRESS_FILE\}/$ctx_progress}"

    echo "$resolved"
    return
  fi

  # Legacy mode: second arg is a JSON object with variables
  local vars_json="$vars"

  # Extract variables from JSON
  local session=$(echo "$vars_json" | jq -r '.session // empty')
  local iteration=$(echo "$vars_json" | jq -r '.iteration // empty')
  local index=$(echo "$vars_json" | jq -r '.index // empty')
  local perspective=$(echo "$vars_json" | jq -r '.perspective // empty')
  local output_file=$(echo "$vars_json" | jq -r '.output // empty')
  local output_path=$(echo "$vars_json" | jq -r '.output_path // empty')
  local progress_file=$(echo "$vars_json" | jq -r '.progress // empty')
  local run_dir=$(echo "$vars_json" | jq -r '.run_dir // empty')
  local stage_idx=$(echo "$vars_json" | jq -r '.stage_idx // "0"')
  local context_file=$(echo "$vars_json" | jq -r '.context_file // empty')
  local status_file=$(echo "$vars_json" | jq -r '.status_file // empty')

  # v3 variables (if context_file provided)
  if [ -n "$context_file" ]; then
    resolved="${resolved//\$\{CTX\}/$context_file}"
  fi
  if [ -n "$status_file" ]; then
    resolved="${resolved//\$\{STATUS\}/$status_file}"
  fi

  # Standard substitutions (bash parameter expansion for multi-line safety)
  resolved="${resolved//\$\{SESSION\}/$session}"
  resolved="${resolved//\$\{SESSION_NAME\}/$session}"
  resolved="${resolved//\$\{ITERATION\}/$iteration}"
  resolved="${resolved//\$\{INDEX\}/$index}"
  resolved="${resolved//\$\{PERSPECTIVE\}/$perspective}"
  resolved="${resolved//\$\{OUTPUT\}/$output_file}"
  resolved="${resolved//\$\{OUTPUT_PATH\}/$output_path}"
  resolved="${resolved//\$\{PROGRESS\}/$progress_file}"
  resolved="${resolved//\$\{PROGRESS_FILE\}/$progress_file}"

  echo "$resolved"
}

# Load prompt from file and resolve variables
# Usage: load_and_resolve_prompt "$prompt_file" "$vars_json"
load_and_resolve_prompt() {
  local prompt_file=$1
  local vars_json=$2

  if [ ! -f "$prompt_file" ]; then
    echo "Error: Prompt file not found: $prompt_file" >&2
    return 1
  fi

  local template=$(cat "$prompt_file")
  resolve_prompt "$template" "$vars_json"
}
