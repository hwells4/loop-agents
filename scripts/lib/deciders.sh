#!/bin/bash
# Engine-owned termination deciders for v3 runtime.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

DECIDERS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$DECIDERS_SCRIPT_DIR}"

source "$LIB_DIR/events.sh"

decider_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

decider_int_or_default() {
  local value=$1
  local fallback=$2
  if decider_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

decider_safe_json() {
  local candidate=$1

  if [ -z "$candidate" ] || [ "$candidate" = "null" ]; then
    echo "{}"
    return 0
  fi

  if echo "$candidate" | jq -e '.' >/dev/null 2>&1; then
    echo "$candidate"
  else
    echo "{}"
  fi
}

decider_result() {
  local decision=$1
  local reason=$2
  local term_type=$3
  local details_json=${4:-"{}"}

  details_json=$(decider_safe_json "$details_json")

  jq -c -n \
    --arg decision "$decision" \
    --arg reason "$reason" \
    --arg term "$term_type" \
    --argjson details "$details_json" \
    '{
      decision: $decision,
      reason: $reason,
      termination_type: $term
    } + (if $details != {} then {details: $details} else {} end)'
}

decider_count_recent_stops() {
  local session=$1
  local node_path=$2
  local node_run=$3
  local term_type=$4
  local count=0
  node_run=$(decider_int_or_default "$node_run" 0)

  while IFS= read -r decision; do
    [ -z "$decision" ] && continue
    if [ "$decision" = "stop" ]; then
      count=$((count + 1))
    else
      break
    fi
  done < <(
    read_events "$session" | jq -r \
      --arg path "$node_path" \
      --argjson run "$node_run" \
      --arg term "$term_type" \
      '[.[] | select(.type == "decision"
        and .cursor.node_path == $path
        and .cursor.node_run == $run
        and (.data.termination_type // "") == $term)
      | .data.decision] | reverse | .[]'
  )

  echo "$count"
}

decider_fixed() {
  local iteration=$1
  local max_iters=$2

  iteration=$(decider_int_or_default "$iteration" 0)
  max_iters=$(decider_int_or_default "$max_iters" 1)

  if [ "$iteration" -ge "$max_iters" ]; then
    decider_result "stop" "max_iterations" "fixed"
  else
    decider_result "continue" "under_max" "fixed"
  fi
}

decider_queue() {
  local command=$1

  if [ -z "$command" ]; then
    echo "Warning: queue termination missing command" >&2
    decider_result "continue" "queue_command_missing" "queue" \
      '{"error":"missing_command"}'
    return 0
  fi

  local output=""
  local exit_code=0
  set +e
  output=$(bash -lc "$command" 2>&1)
  exit_code=$?
  set -e

  if [ "$exit_code" -ne 0 ]; then
    echo "Warning: queue command failed with exit $exit_code" >&2
    decider_result "continue" "queue_command_failed" "queue" \
      "$(jq -n --argjson code "$exit_code" --arg output "$output" '{exit_code: $code, output: $output}')"
    return 0
  fi

  local trimmed
  trimmed=$(printf '%s' "$output" | tr -d '[:space:]')

  if [ -z "$trimmed" ]; then
    decider_result "stop" "queue_empty" "queue"
  else
    local item_count
    item_count=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
    decider_result "continue" "queue_has_items" "queue" \
      "$(jq -n --argjson count "${item_count:-0}" '{items: $count}')"
  fi
}

decider_load_judge() {
  if type judge_decision >/dev/null 2>&1; then
    return 0
  fi

  if [ -f "$LIB_DIR/judge.sh" ]; then
    source "$LIB_DIR/judge.sh"
  fi

  if ! type judge_decision >/dev/null 2>&1; then
    return 1
  fi
}

decider_format_index() {
  printf '%04d' "$1"
}

decider_previous_iterations() {
  local node_run_dir=$1
  local iteration=$2
  local files=()

  if [ "$iteration" -gt 1 ] && [ -d "$node_run_dir" ]; then
    for ((i=1; i<iteration; i++)); do
      local candidate="$node_run_dir/iteration-$(decider_format_index "$i")/output.md"
      [ -f "$candidate" ] && files+=("$candidate")
    done
  fi

  if [ ${#files[@]} -gt 0 ]; then
    printf '%s\n' "${files[@]}" | jq -R . | jq -s .
  else
    echo "[]"
  fi
}

decider_judgment() {
  local session=$1
  local node_path=$2
  local node_run=$3
  local iteration=$4
  local min_iters=$5
  local consensus=$6
  local result_file=$7
  local progress_file=$8
  local node_id=$9
  local stage_ref=${10:-""}
  local termination_json=${11:-"{}"}
  local node_run_dir=${12:-""}

  node_run=$(decider_int_or_default "$node_run" 0)
  iteration=$(decider_int_or_default "$iteration" 0)
  min_iters=$(decider_int_or_default "$min_iters" 2)
  consensus=$(decider_int_or_default "$consensus" 2)
  termination_json=$(decider_safe_json "$termination_json")

  if [ "$iteration" -lt "$min_iters" ]; then
    decider_result "continue" "min_iterations" "judgment" \
      "$(jq -n --argjson min "$min_iters" '{min_iterations: $min}')"
    return 0
  fi

  if ! decider_load_judge; then
    echo "Warning: judge_decision not available; skipping judgment" >&2
    decider_result "continue" "judge_unavailable" "judgment"
    return 0
  fi

  local previous_iterations_json
  previous_iterations_json=$(decider_previous_iterations "$node_run_dir" "$iteration")

  local judge_input
  judge_input=$(jq -n \
    --arg session "$session" \
    --arg node_path "$node_path" \
    --argjson node_run "$node_run" \
    --argjson iteration "$iteration" \
    --arg node_id "$node_id" \
    --arg stage_ref "$stage_ref" \
    --arg result "$result_file" \
    --arg progress "$progress_file" \
    --argjson termination "$termination_json" \
    --argjson previous_iterations "$previous_iterations_json" \
    '{
      session: $session,
      cursor: {node_path: $node_path, node_run: $node_run, iteration: $iteration},
      node: {id: $node_id, ref: $stage_ref},
      paths: {result: $result, progress: $progress},
      inputs: {from_previous_iterations: $previous_iterations},
      termination: $termination
    }')

  local judge_output=""
  local exit_code=0
  set +e
  judge_output=$(judge_decision "$judge_input" 2>/dev/null)
  exit_code=$?
  set -e

  if [ "$exit_code" -ne 0 ] || ! echo "$judge_output" | jq -e '.' >/dev/null 2>&1; then
    decider_result "continue" "judge_invalid" "judgment" \
      "$(jq -n --arg output "$judge_output" --argjson code "$exit_code" '{exit_code: $code, output: $output}')"
    return 0
  fi

  local judge_stop
  judge_stop=$(echo "$judge_output" | jq -r '.stop // false')
  local judge_reason
  judge_reason=$(echo "$judge_output" | jq -r '.reason // ""')
  local confidence
  confidence=$(echo "$judge_output" | jq -r '.confidence // 0')

  local confident=false
  if awk "BEGIN {exit !($confidence >= 0.5)}"; then
    confident=true
  fi

  if [ "$judge_stop" = "true" ] && [ "$confident" = "true" ]; then
    local previous_stops
    previous_stops=$(decider_count_recent_stops "$session" "$node_path" "$node_run" "judgment")
    previous_stops=$(decider_int_or_default "$previous_stops" 0)
    local total=$((previous_stops + 1))

    if [ "$total" -ge "$consensus" ]; then
      decider_result "stop" "judgment_consensus" "judgment" \
        "$(jq -n \
          --arg reason "$judge_reason" \
          --argjson confidence "$confidence" \
          --argjson stops "$total" \
          --argjson consensus "$consensus" \
          '{judge_reason: $reason, confidence: $confidence, consecutive_stops: $stops, consensus: $consensus}')"
    else
      decider_result "continue" "judgment_waiting" "judgment" \
        "$(jq -n \
          --arg reason "$judge_reason" \
          --argjson confidence "$confidence" \
          --argjson stops "$total" \
          --argjson consensus "$consensus" \
          '{judge_reason: $reason, confidence: $confidence, consecutive_stops: $stops, consensus: $consensus}')"
    fi
  else
    decider_result "continue" "judge_continue" "judgment" \
      "$(jq -n \
        --arg reason "$judge_reason" \
        --argjson confidence "$confidence" \
        --arg stop "$judge_stop" \
        '{judge_reason: $reason, confidence: $confidence, stop: $stop}')"
  fi
}

decider_run() {
  local term_type=$1
  local iteration=$2
  local max_iters=$3
  local min_iters=$4
  local consensus=$5
  local queue_command=$6
  local session=$7
  local node_path=$8
  local node_run=$9
  local result_file=${10}
  local progress_file=${11}
  local node_id=${12}
  local stage_ref=${13}
  local termination_json=${14:-"{}"}
  local node_run_dir=${15:-""}

  case "$term_type" in
    queue)
      decider_queue "$queue_command"
      ;;
    judgment)
      decider_judgment "$session" "$node_path" "$node_run" "$iteration" "$min_iters" \
        "$consensus" "$result_file" "$progress_file" "$node_id" "$stage_ref" "$termination_json" "$node_run_dir"
      ;;
    fixed|*)
      decider_fixed "$iteration" "$max_iters"
      ;;
  esac
}
