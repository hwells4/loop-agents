#!/bin/bash
# Unified YAML Parser
# Converts YAML to JSON for easy querying with jq

# Internal implementation - do not call directly
_yaml_to_json_impl() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo "{}"
    return 1
  elif command -v yq >/dev/null 2>&1; then
    yq -o=json "$file" 2>/dev/null || { echo "{}"; return 1; }
  elif python3 -c "import yaml" >/dev/null 2>&1; then
    python3 -c "import sys, json, yaml; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))" "$file" 2>/dev/null || { echo "{}"; return 1; }
  else
    echo "{}"
    return 1
  fi
}

# Convert YAML file to JSON
# Usage: yaml_to_json "file.yaml"
# Note: Wrapper that suppresses bash -x trace output to prevent stdout pollution.
# Uses bash -c with +x to invoke the implementation in a trace-free environment.
yaml_to_json() {
  bash +x -c 'source "'"${BASH_SOURCE[0]}"'" && _yaml_to_json_impl "$@"' _ "$@"
}

# Query a JSON value using jq
# Usage: json_get "$json" ".key" "default"
json_get() {
  local json=$1
  local path=$2
  local default=${3:-""}

  local value=$(echo "$json" | jq -r "$path // empty" 2>/dev/null)

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# Get array length
# Usage: json_array_len "$json" ".stages"
json_array_len() {
  local json=$1
  local path=$2

  echo "$json" | jq -r "$path | length" 2>/dev/null || echo "0"
}
