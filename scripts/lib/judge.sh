#!/bin/bash
# Judge module for judgment-based termination.

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

JUDGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$JUDGE_SCRIPT_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$JUDGE_SCRIPT_DIR/../.." && pwd)}"

source "$LIB_DIR/events.sh"
source "$LIB_DIR/provider.sh"
source "$LIB_DIR/resolve.sh"

judge_int_or_default() {
  local value=$1
  local fallback=$2
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

judge_prompt_path() {
  local override="${JUDGE_PROMPT_PATH:-}"
  if [ -n "$override" ]; then
    if [[ "$override" != /* ]]; then
      override="$PROJECT_ROOT/$override"
    fi
    echo "$override"
    return 0
  fi

  local user_prompt="${HOME}/.config/agent-pipelines/prompts/judge.md"
  if [ -f "$user_prompt" ]; then
    echo "$user_prompt"
    return 0
  fi

  local builtin="$PROJECT_ROOT/scripts/prompts/judge.md"
  if [ -f "$builtin" ]; then
    echo "$builtin"
    return 0
  fi

  echo ""
}

judge_read_json_file() {
  local path=$1
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    echo "{}"
    return 0
  fi

  if jq -e '.' "$path" >/dev/null 2>&1; then
    cat "$path"
  else
    echo "{}"
  fi
}

judge_read_text_file() {
  local path=$1
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    echo ""
    return 0
  fi

  cat "$path"
}

judge_write_atomic() {
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

judge_count_recent_failures() {
  local session=$1
  local node_path=$2
  local node_run=$3
  local count=0

  if [ -z "$session" ] || [ -z "$node_path" ]; then
    echo "0"
    return 0
  fi

  node_run=$(judge_int_or_default "$node_run" 0)

  while IFS= read -r status; do
    [ -z "$status" ] && continue
    if [ "$status" = "failed" ]; then
      count=$((count + 1))
    else
      break
    fi
  done < <(
    read_events "$session" | jq -r \
      --arg path "$node_path" \
      --argjson run "$node_run" \
      '[.[] | select(.type == "judge_complete"
        and .cursor.node_path == $path
        and .cursor.node_run == $run)
      | .data.status] | reverse | .[]'
  )

  echo "$count"
}

render_judge_prompt() {
  local input_json=$1
  local prompt_file
  prompt_file=$(judge_prompt_path)

  if [ -z "$prompt_file" ] || [ ! -f "$prompt_file" ]; then
    echo "Error: Judge prompt file not found" >&2
    return 1
  fi

  local template
  template=$(cat "$prompt_file")

  local stage_name
  stage_name=$(echo "$input_json" | jq -r '.node.id // "stage"')
  local iteration
  iteration=$(echo "$input_json" | jq -r '.cursor.iteration // 0')
  local termination_json
  termination_json=$(echo "$input_json" | jq -c '.termination // {}')

  local result_path
  result_path=$(echo "$input_json" | jq -r '.paths.result // empty')
  local progress_path
  progress_path=$(echo "$input_json" | jq -r '.paths.progress // empty')

  local result_json
  result_json=$(judge_read_json_file "$result_path")
  local progress_md
  progress_md=$(judge_read_text_file "$progress_path")

  local node_output=""
  if [ -n "$result_path" ]; then
    local iter_dir
    iter_dir=$(dirname "$result_path")
    local output_md="$iter_dir/output.md"
    local node_run_dir
    node_run_dir=$(dirname "$iter_dir")
    local output_json="$node_run_dir/output.json"

    if [ -f "$output_json" ]; then
      node_output=$(judge_read_text_file "$output_json")
    elif [ -f "$output_md" ]; then
      node_output=$(judge_read_text_file "$output_md")
    fi
  fi

  local rendered="$template"
  rendered="${rendered//\$\{STAGE_NAME\}/$stage_name}"
  rendered="${rendered//\$\{ITERATION\}/$iteration}"
  rendered="${rendered//\$\{TERMINATION_CRITERIA\}/$termination_json}"
  rendered="${rendered//\$\{RESULT_JSON\}/$result_json}"
  rendered="${rendered//\$\{PROGRESS_MD\}/$progress_md}"
  rendered="${rendered//\$\{NODE_OUTPUT\}/$node_output}"

  echo "$rendered"
}

invoke_judge() {
  local prompt=$1
  local provider=$2
  local model=$3
  local output_file=${4:-""}

  execute_agent "$provider" "$prompt" "$model" "$output_file"
}

judge_emit_event() {
  local type=$1
  local session=$2
  local cursor_json=${3:-"null"}
  local data_json=${4:-"{}"}

  if [ -z "$session" ]; then
    return 0
  fi

  append_event "$type" "$session" "$cursor_json" "$data_json" || true
}

judge_decision() {
  local input_json=$1

  if [ -z "$input_json" ]; then
    echo '{"stop":false,"reason":"missing_input","confidence":0}'
    return 0
  fi

  local session
  session=$(echo "$input_json" | jq -r '.session // empty')
  local cursor_json
  cursor_json=$(echo "$input_json" | jq -c '.cursor // null')
  local node_path
  node_path=$(echo "$input_json" | jq -r '.cursor.node_path // empty')
  local node_run
  node_run=$(echo "$input_json" | jq -r '.cursor.node_run // 0')

  local failure_count
  failure_count=$(judge_count_recent_failures "$session" "$node_path" "$node_run")
  failure_count=$(judge_int_or_default "$failure_count" 0)

  if [ "$failure_count" -ge 3 ]; then
    judge_emit_event "judge_complete" "$session" "$cursor_json" \
      "$(jq -n --arg status "skipped" --arg reason "judge_unreliable" '{status: $status, reason: $reason}')"
    echo '{"stop":false,"reason":"judge_unreliable","confidence":0}'
    return 0
  fi

  local prompt
  prompt=$(render_judge_prompt "$input_json") || return 1

  local provider
  provider=$(echo "$input_json" | jq -r '.termination.judge.provider // empty')
  if [ -z "$provider" ]; then
    provider="${JUDGE_PROVIDER:-claude}"
  fi

  local model
  model=$(echo "$input_json" | jq -r '.termination.judge.model // empty')
  if [ -z "$model" ]; then
    if [ "$provider" = "claude" ]; then
      model="${JUDGE_MODEL:-haiku}"
    else
      model="${JUDGE_MODEL:-$(get_default_model "$provider")}"
    fi
  fi

  local result_path
  result_path=$(echo "$input_json" | jq -r '.paths.result // empty')
  local iter_dir=""
  if [ -n "$result_path" ]; then
    iter_dir=$(dirname "$result_path")
  fi
  local judge_log=""
  local judge_json=""
  if [ -n "$iter_dir" ]; then
    judge_log="$iter_dir/judge.log"
    judge_json="$iter_dir/judge.json"
  fi

  judge_emit_event "judge_start" "$session" "$cursor_json" \
    "$(jq -n --arg provider "$provider" --arg model "$model" '{provider: $provider, model: $model}')"

  local output=""
  local exit_code=0
  local attempt
  for attempt in 1 2; do
    set +e
    output=$(invoke_judge "$prompt" "$provider" "$model" "$judge_log")
    exit_code=$?
    set -e
    if [ "$exit_code" -eq 0 ]; then
      break
    fi
  done

  if [ "$exit_code" -ne 0 ]; then
    echo "Warning: Judge invocation failed (exit $exit_code)" >&2
    judge_emit_event "judge_complete" "$session" "$cursor_json" \
      "$(jq -n --arg status "failed" --arg reason "invoke_failed" --argjson code "$exit_code" '{status: $status, reason: $reason, exit_code: $code}')"
    echo '{"stop":false,"reason":"invoke_failed","confidence":0}'
    return 0
  fi

  if ! echo "$output" | jq -e '.' >/dev/null 2>&1; then
    echo "Warning: Judge returned invalid JSON" >&2
    judge_emit_event "judge_complete" "$session" "$cursor_json" \
      "$(jq -n --arg status "failed" --arg reason "invalid_json" --arg output "$output" '{status: $status, reason: $reason, output: $output}')"
    echo '{"stop":false,"reason":"invalid_json","confidence":0}'
    return 0
  fi

  local normalized
  normalized=$(echo "$output" | jq -c \
    '. + {stop: (.stop // false), reason: (.reason // ""), confidence: (.confidence // 0)}')

  judge_emit_event "judge_complete" "$session" "$cursor_json" \
    "$(jq -n --arg status "success" --argjson result "$normalized" '{status: $status, result: $result}')"

  if [ -n "$judge_json" ]; then
    judge_write_atomic "$judge_json" "$normalized"
  fi

  echo "$normalized"
}
