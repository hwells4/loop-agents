#!/bin/bash
# Stage loading utilities
# Loads stage definitions from stages/ directory

# Load a stage definition from stages/ directory
# Sets: STAGE_CONFIG (JSON), STAGE_PROMPT, STAGE_*
load_stage() {
  local stage_type=$1
  local stage_dir="$STAGES_DIR/$stage_type"

  if [ ! -d "$stage_dir" ]; then
    echo "Error: Loop type not found: $stage_type" >&2
    echo "Available stages:" >&2
    while IFS= read -r d; do
      [ -d "$STAGES_DIR/$d" ] && echo "  $d" >&2
    done < <(ls "$STAGES_DIR" 2>/dev/null)
    return 1
  fi

  # Load config YAML as JSON
  local config_file="$stage_dir/stage.yaml"
  if [ ! -f "$config_file" ]; then
    echo "Error: No stage.yaml in $stage_dir" >&2
    return 1
  fi

  STAGE_CONFIG=$(yaml_to_json "$config_file")

  # Extract config values
  STAGE_NAME=$(json_get "$STAGE_CONFIG" ".name" "$stage_type")

  # v3 schema: read termination block first, fallback to v2 completion field
  local term_type=$(json_get "$STAGE_CONFIG" ".termination.type" "")
  if [ -n "$term_type" ]; then
    # v3: map termination type to completion strategy
    case "$term_type" in
      queue) STAGE_COMPLETION="beads-empty" ;;
      judgment) STAGE_COMPLETION="plateau" ;;
      fixed) STAGE_COMPLETION="fixed-n" ;;
      *) STAGE_COMPLETION="$term_type" ;;
    esac
    STAGE_MIN_ITERATIONS=$(json_get "$STAGE_CONFIG" ".termination.min_iterations" "1")
    STAGE_CONSENSUS=$(json_get "$STAGE_CONFIG" ".termination.consensus" "2")
  else
    # v2 legacy: use completion field directly
    STAGE_COMPLETION=$(json_get "$STAGE_CONFIG" ".completion" "fixed-n")
    STAGE_MIN_ITERATIONS=$(json_get "$STAGE_CONFIG" ".min_iterations" "1")
    STAGE_CONSENSUS="2"
  fi

  # Resolve provider first (needed for model default)
  STAGE_PROVIDER=${PIPELINE_CLI_PROVIDER:-${CLAUDE_PIPELINE_PROVIDER:-$(json_get "$STAGE_CONFIG" ".provider" "claude")}}

  # Model default is provider-aware: opus for Claude, gpt-5.2-codex for Codex
  # For Codex, model can include reasoning: gpt-5.2-codex:xhigh
  local default_model=$(get_default_model "$STAGE_PROVIDER")
  STAGE_MODEL=${PIPELINE_CLI_MODEL:-${CLAUDE_PIPELINE_MODEL:-$(json_get "$STAGE_CONFIG" ".model" "$default_model")}}

  STAGE_DELAY=$(json_get "$STAGE_CONFIG" ".delay" "3")
  STAGE_CHECK_BEFORE=$(json_get "$STAGE_CONFIG" ".check_before" "false")
  STAGE_OUTPUT_PARSE=$(json_get "$STAGE_CONFIG" ".output_parse" "")
  STAGE_ITEMS=$(json_get "$STAGE_CONFIG" ".items" "")
  STAGE_PROMPT_VALUE=$(json_get "$STAGE_CONFIG" ".prompt" "")
  STAGE_OUTPUT_PATH=$(json_get "$STAGE_CONFIG" ".output_path" "")
  STAGE_CONTEXT=${PIPELINE_CLI_CONTEXT:-${CLAUDE_PIPELINE_CONTEXT:-$(json_get "$STAGE_CONFIG" ".context" "")}}

  # Export for completion strategies
  export MIN_ITERATIONS="$STAGE_MIN_ITERATIONS"
  export CONSENSUS="$STAGE_CONSENSUS"
  export ITEMS="$STAGE_ITEMS"

  # Load prompt
  local prompt_candidates=()
  local prompt_file=""

  if [ -n "$STAGE_PROMPT_VALUE" ] && [ "$STAGE_PROMPT_VALUE" != "null" ]; then
    local prompt_path="${STAGE_PROMPT_VALUE#./}"
    if [[ "$prompt_path" == /* ]]; then
      prompt_candidates+=("$prompt_path")
    elif [[ "$prompt_path" == */* ]]; then
      [[ "$prompt_path" == *.md ]] || prompt_path="${prompt_path}.md"
      prompt_candidates+=("$stage_dir/$prompt_path")
    else
      local prompt_name="$prompt_path"
      [[ "$prompt_name" == *.md ]] || prompt_name="${prompt_name}.md"
      prompt_candidates+=("$stage_dir/$prompt_name")
      prompt_candidates+=("$stage_dir/prompts/$prompt_name")
    fi
  fi

  prompt_candidates+=("$stage_dir/prompts/prompt.md")
  prompt_candidates+=("$stage_dir/prompt.md")

  for candidate in "${prompt_candidates[@]}"; do
    if [ -f "$candidate" ]; then
      prompt_file="$candidate"
      break
    fi
  done

  if [ -z "$prompt_file" ]; then
    echo "Error: No prompt found for loop: $stage_type" >&2
    return 1
  fi

  STAGE_PROMPT=$(cat "$prompt_file")
  STAGE_DIR="$stage_dir"
}
