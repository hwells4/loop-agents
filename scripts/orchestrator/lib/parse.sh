#!/bin/bash
# Pipeline YAML Parser
# Parses pipeline definitions into queryable format
#
# Uses a simple approach: convert YAML to a flat key-value format
# that can be queried with get_* functions.

# Parsed pipeline data (associative arrays require bash 4+)
declare -A PIPELINE_DATA
declare -a PIPELINE_STAGES
PIPELINE_RAW=""

# Parse a pipeline YAML file
parse_pipeline() {
  local file=$1
  PIPELINE_RAW=$(cat "$file")

  # Check for jq (required for reliable YAML→JSON parsing)
  if ! command -v yq &>/dev/null; then
    # Fallback: simple line-by-line parsing
    _parse_yaml_simple "$file"
  else
    # Use yq for robust parsing
    _parse_yaml_yq "$file"
  fi
}

# Simple YAML parser (no dependencies beyond bash)
# Handles our pipeline format specifically
_parse_yaml_simple() {
  local file=$1
  local current_section=""
  local current_stage=-1
  local in_prompt=false
  local prompt_indent=0
  local prompt_content=""
  local in_array=false
  local array_name=""
  local array_items=""

  while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments (unless in prompt)
    if [ "$in_prompt" = false ]; then
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// /}" ]] && continue
    fi

    # Check for prompt block end
    if [ "$in_prompt" = true ]; then
      local line_indent=$(echo "$line" | sed -E 's/^( *).*/\1/' | wc -c)
      line_indent=$((line_indent - 1))

      if [ "$line_indent" -lt "$prompt_indent" ] && [ -n "${line// /}" ]; then
        # End of prompt block
        PIPELINE_DATA["stage.${current_stage}.prompt"]="$prompt_content"
        in_prompt=false
        prompt_content=""
      else
        # Continue prompt content
        prompt_content="${prompt_content}${line}
"
        continue
      fi
    fi

    # Check for array end
    if [ "$in_array" = true ]; then
      if [[ "$line" =~ ^[[:space:]]*-[[:space:]](.+)$ ]]; then
        local item="${BASH_REMATCH[1]}"
        array_items="${array_items}${item}|"
        continue
      else
        # End of array
        PIPELINE_DATA["${array_name}"]="${array_items%|}"
        in_array=false
        array_items=""
      fi
    fi

    # Parse key: value pairs
    if [[ "$line" =~ ^([[:space:]]*)([a-zA-Z_][a-zA-Z0-9_.-]*):(.*)$ ]]; then
      local indent="${BASH_REMATCH[1]}"
      local key="${BASH_REMATCH[2]}"
      local value="${BASH_REMATCH[3]}"

      # Trim value
      value=$(echo "$value" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

      # Check for multiline prompt indicator
      if [ "$key" = "prompt" ] && [ "$value" = "|" ]; then
        in_prompt=true
        prompt_indent=${#indent}
        prompt_indent=$((prompt_indent + 2))  # prompt content is indented further
        continue
      fi

      # Check for array start (empty value followed by - items)
      if [ -z "$value" ]; then
        # Peek at next non-empty line
        array_name=""
        if [ "$current_stage" -ge 0 ]; then
          array_name="stage.${current_stage}.${key}"
        else
          array_name="$key"
        fi
        in_array=true
        continue
      fi

      # Handle section markers
      case "$key" in
        name)
          if [ "$current_section" = "stages" ] && [ "$current_stage" -ge 0 ]; then
            PIPELINE_DATA["stage.${current_stage}.name"]="$value"
          else
            PIPELINE_DATA["name"]="$value"
          fi
          ;;
        stages)
          current_section="stages"
          ;;
        defaults)
          current_section="defaults"
          ;;
        *)
          # Store value with appropriate prefix
          if [ "$current_section" = "defaults" ]; then
            PIPELINE_DATA["defaults.${key}"]="$value"
          elif [ "$current_stage" -ge 0 ]; then
            PIPELINE_DATA["stage.${current_stage}.${key}"]="$value"
          else
            PIPELINE_DATA["$key"]="$value"
          fi
          ;;
      esac
    fi

    # Check for new stage (- name:)
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
      current_stage=$((current_stage + 1))
      PIPELINE_DATA["stage.${current_stage}.name"]="${BASH_REMATCH[1]}"
      PIPELINE_DATA["stage_count"]=$((current_stage + 1))
    fi

  done < "$file"

  # Handle any remaining prompt or array
  if [ "$in_prompt" = true ]; then
    PIPELINE_DATA["stage.${current_stage}.prompt"]="$prompt_content"
  fi
  if [ "$in_array" = true ]; then
    PIPELINE_DATA["${array_name}"]="${array_items%|}"
  fi
}

# YQ-based YAML parser (more robust)
_parse_yaml_yq() {
  local file=$1

  # Convert to JSON and extract values
  local json=$(yq -o=json "$file")

  PIPELINE_DATA["name"]=$(echo "$json" | jq -r '.name // empty')
  PIPELINE_DATA["description"]=$(echo "$json" | jq -r '.description // empty')
  PIPELINE_DATA["version"]=$(echo "$json" | jq -r '.version // empty')
  PIPELINE_DATA["defaults.provider"]=$(echo "$json" | jq -r '.defaults.provider // empty')
  PIPELINE_DATA["defaults.model"]=$(echo "$json" | jq -r '.defaults.model // empty')

  # Parse stages
  local stage_count=$(echo "$json" | jq '.stages | length')
  PIPELINE_DATA["stage_count"]="$stage_count"

  for i in $(seq 0 $((stage_count - 1))); do
    PIPELINE_DATA["stage.${i}.name"]=$(echo "$json" | jq -r ".stages[$i].name // empty")
    PIPELINE_DATA["stage.${i}.description"]=$(echo "$json" | jq -r ".stages[$i].description // empty")
    PIPELINE_DATA["stage.${i}.runs"]=$(echo "$json" | jq -r ".stages[$i].runs // empty")
    PIPELINE_DATA["stage.${i}.model"]=$(echo "$json" | jq -r ".stages[$i].model // empty")
    PIPELINE_DATA["stage.${i}.provider"]=$(echo "$json" | jq -r ".stages[$i].provider // empty")
    PIPELINE_DATA["stage.${i}.completion"]=$(echo "$json" | jq -r ".stages[$i].completion // empty")
    PIPELINE_DATA["stage.${i}.parallel"]=$(echo "$json" | jq -r ".stages[$i].parallel // empty")
    PIPELINE_DATA["stage.${i}.prompt"]=$(echo "$json" | jq -r ".stages[$i].prompt // empty")

    # Parse perspectives array
    local perspectives=$(echo "$json" | jq -r ".stages[$i].perspectives // [] | join(\"|\")")
    PIPELINE_DATA["stage.${i}.perspectives"]="$perspectives"
  done
}

# Get a pipeline-level value
get_pipeline_value() {
  local key=$1
  local default=${2:-""}

  local value="${PIPELINE_DATA[$key]}"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Get the number of stages
get_stage_count() {
  echo "${PIPELINE_DATA[stage_count]:-0}"
}

# Get a stage-level value
get_stage_value() {
  local stage_idx=$1
  local key=$2
  local default=${3:-""}

  local value="${PIPELINE_DATA[stage.${stage_idx}.${key}]}"
  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Get stage prompt
get_stage_prompt() {
  local stage_idx=$1
  echo "${PIPELINE_DATA[stage.${stage_idx}.prompt]}"
}

# Get stage array (pipe-delimited)
get_stage_array() {
  local stage_idx=$1
  local key=$2
  echo "${PIPELINE_DATA[stage.${stage_idx}.${key}]}"
}

# Get item from pipe-delimited array
get_array_item() {
  local array=$1
  local index=$2

  if [ -z "$array" ]; then
    echo ""
    return
  fi

  echo "$array" | tr '|' '\n' | sed -n "$((index + 1))p"
}

# Update state file with stage status
update_state_stage() {
  local state_file=$1
  local stage_idx=$2
  local stage_name=$3
  local status=$4

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Create stage entry
  local stage_json=$(cat << EOF
{
  "index": $stage_idx,
  "name": "$stage_name",
  "status": "$status",
  "timestamp": "$timestamp"
}
EOF
)

  # Update or append stage
  if jq -e ".stages[$stage_idx]" "$state_file" &>/dev/null; then
    jq ".stages[$stage_idx].status = \"$status\" | .stages[$stage_idx].timestamp = \"$timestamp\" | .current_stage = $stage_idx" "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  else
    jq ".stages += [$stage_json] | .current_stage = $stage_idx" "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  fi
}
