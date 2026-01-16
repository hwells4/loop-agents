#!/bin/bash
# Deterministic artifact path helpers for v3 runtime.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

paths_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

paths_int_or_default() {
  local value=$1
  local fallback=$2
  if paths_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

paths_format_index() {
  local value
  value=$(paths_int_or_default "$1" 0)
  printf '%04d' "$value"
}

paths_default_run_root() {
  echo "${PIPELINE_RUN_ROOT:-${PROJECT_ROOT:-$(pwd)}/.claude/pipeline-runs}"
}

# Usage: get_session_dir "$session" ["$run_root"]
get_session_dir() {
  local session=$1
  local run_root=${2:-"$(paths_default_run_root)"}

  if [ -z "$session" ]; then
    return 1
  fi

  if [[ "$session" = /* ]]; then
    echo "$session"
    return 0
  fi

  echo "$run_root/$session"
}

# Usage: get_node_dir "$session" "$node_path"
get_node_dir() {
  local session=$1
  local node_path=$2
  local session_dir
  session_dir=$(get_session_dir "$session")
  echo "$session_dir/artifacts/node-${node_path}"
}

# Usage: get_run_dir "$session" "$node_path" "$run"
get_run_dir() {
  local session=$1
  local node_path=$2
  local node_run=$3
  local node_dir
  node_dir=$(get_node_dir "$session" "$node_path")
  echo "$node_dir/run-$(paths_format_index "$node_run")"
}

# Usage: get_iteration_dir "$session" "$node_path" "$run" "$iteration"
get_iteration_dir() {
  local session=$1
  local node_path=$2
  local node_run=$3
  local iteration=$4
  local run_dir
  run_dir=$(get_run_dir "$session" "$node_path" "$node_run")
  echo "$run_dir/iteration-$(paths_format_index "$iteration")"
}

# Usage: ensure_dir "$path"
ensure_dir() {
  local dir=$1
  if [ -z "$dir" ]; then
    return 1
  fi
  if [ -d "$dir" ]; then
    return 0
  fi
  mkdir -p "$dir"
}
