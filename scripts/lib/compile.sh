#!/bin/bash
set -euo pipefail

COMPILE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${LIB_DIR:-$COMPILE_SCRIPT_DIR}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$COMPILE_SCRIPT_DIR/../.." && pwd)}"
STAGES_DIR="${STAGES_DIR:-$PROJECT_ROOT/scripts/stages}"
PIPELINES_DIR="${PIPELINES_DIR:-$PROJECT_ROOT/scripts/pipelines}"

source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/deps.sh"
source "$LIB_DIR/provider.sh"

print_compile_usage() {
  cat >&2 <<'EOF'
Usage:
  compile.sh <pipeline.yaml> <session> <run_dir>
  compile.sh <pipeline.yaml> <output_file> [--session name]
Options:
  --session <name>   Session name override
  --output <path>    Write plan.json to explicit path
  --run-dir <dir>    Write plan.json to <dir>/plan.json
EOF
}

strip_project_root() {
  local path=$1
  if [ -n "$PROJECT_ROOT" ] && [[ "$path" == "$PROJECT_ROOT/"* ]]; then
    echo "${path#$PROJECT_ROOT/}"
  else
    echo "$path"
  fi
}

compile_timestamp() {
  if [ -n "${COMPILE_TIMESTAMP:-}" ]; then
    echo "$COMPILE_TIMESTAMP"
  else
    date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
  fi
}

sha256_file() {
  local file=$1

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi

  compile_error "source_hash" "Missing sha256 tool (sha256sum or shasum)" "[]" ""
  return 1
}

compile_error() {
  local phase=$1
  local message=$2
  local searched_json=${3:-"[]"}
  local suggestion=${4:-""}

  local error_json
  error_json=$(jq -n \
    --arg phase "$phase" \
    --arg message "$message" \
    --argjson searched "$searched_json" \
    --arg suggestion "$suggestion" \
    '{
      error: "compilation_failed",
      phase: $phase,
      message: $message,
      searched: $searched
    } + (if $suggestion != "" then {suggestion: $suggestion} else {} end)')
  echo "$error_json" >&2
}

normalize_termination_from_config() {
  local config_json=$1
  local fallback_type=${2:-""}

  echo "$config_json" | jq -c --arg fallback "$fallback_type" '
    def completion_to_type:
      if . == "beads-empty" then "queue"
      elif . == "plateau" then "judgment"
      elif . == "fixed-n" then "fixed"
      else .
      end;

    (if (.termination? != null) then .termination
     elif (.completion? != null and .completion != "") then
       {type: (.completion | completion_to_type)}
       + (if .consensus then {consensus: .consensus} else {} end)
       + (if .min_iterations then {min_iterations: .min_iterations} else {} end)
     else {} end)
    | if ($fallback | length) > 0 and (.type == null or .type == "") then
        . + {type: $fallback}
      else
        .
      end
  '
}

merge_termination() {
  local base_json=$1
  local override_json=$2
  local runs=${3:-""}
  local default_type=${4:-"fixed"}

  local merged
  merged=$(jq -n --argjson base "$base_json" --argjson override "$override_json" '$base * $override')

  if [[ "$runs" =~ ^[0-9]+$ ]]; then
    merged=$(echo "$merged" | jq --argjson runs "$runs" '
      if .max == null and .iterations == null then
        . + {max: $runs}
      elif .iterations != null and .max == null then
        . + {max: (.iterations | tonumber)}
      else
        .
      end
      | del(.iterations)
    ')
  else
    merged=$(echo "$merged" | jq 'del(.iterations)')
  fi

  merged=$(echo "$merged" | jq --arg default_type "$default_type" '
    if .type == null or .type == "" then . + {type: $default_type} else . end
  ')

  echo "$merged"
}

resolve_stage_dir() {
  local stage_ref=$1
  local stage_dir="$STAGES_DIR/$stage_ref"

  if [ -d "$stage_dir" ]; then
    echo "$stage_dir"
    return 0
  fi

  local searched
  searched=$(jq -n --arg path "$stage_dir" '[$path]')
  compile_error "stage_resolution" "Stage '$stage_ref' not found" "$searched" "Run 'library list' to see available stages"
  return 1
}

resolve_stage_prompt_path() {
  local stage_dir=$1
  local stage_config_json=$2

  local prompt_value
  prompt_value=$(echo "$stage_config_json" | jq -r '.prompt // empty')

  local candidates=()
  if [ -n "$prompt_value" ] && [ "$prompt_value" != "null" ]; then
    local prompt_path="${prompt_value#./}"
    if [[ "$prompt_path" == /* ]]; then
      candidates+=("$prompt_path")
    elif [[ "$prompt_path" == */* ]]; then
      [[ "$prompt_path" == *.md ]] || prompt_path="${prompt_path}.md"
      candidates+=("$stage_dir/$prompt_path")
    else
      local prompt_name="$prompt_path"
      [[ "$prompt_name" == *.md ]] || prompt_name="${prompt_name}.md"
      candidates+=("$stage_dir/$prompt_name")
      candidates+=("$stage_dir/prompts/$prompt_name")
    fi
  fi

  candidates+=("$stage_dir/prompts/prompt.md")
  candidates+=("$stage_dir/prompt.md")

  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      strip_project_root "$candidate"
      return 0
    fi
  done

  return 1
}

infer_dependencies() {
  local nodes_json=$1
  local pipeline_json=$2

  local needs_bd=false
  needs_bd=$(echo "$nodes_json" | jq -r '[.. | objects | select(has("termination")) | .termination.type == "queue"] | any')

  local needs_tmux=false
  needs_tmux=$(echo "$pipeline_json" | jq -r '[.. | objects | select(has("tmux")) | .tmux == true] | any')

  jq -n \
    --argjson needs_tmux "$needs_tmux" \
    --argjson needs_bd "$needs_bd" \
    '{
      jq: true,
      yq: true,
      tmux: $needs_tmux,
      bd: $needs_bd
    }'
}

validate_plan_json() {
  local plan_json=$1

  echo "$plan_json" | jq -e '
    .version == 1
    and (.nodes | type == "array")
    and (.dependencies.jq == true)
    and (.dependencies.yq == true)
    and (.session.name | length > 0)
    and (.nodes | all(.path != null and .id != null and .kind != null))
  ' >/dev/null
}

compile_stage_node() {
  local stage_json=$1
  local stage_idx=$2
  local default_provider=$3
  local default_model=$4

  local stage_name
  stage_name=$(echo "$stage_json" | jq -r '.name // empty')
  local stage_ref
  stage_ref=$(echo "$stage_json" | jq -r '.stage // .loop // empty')
  local stage_prompt_inline
  stage_prompt_inline=$(echo "$stage_json" | jq -r '.prompt // empty')
  local stage_desc_override
  stage_desc_override=$(echo "$stage_json" | jq -r '.description // empty')
  local stage_context_override
  stage_context_override=$(echo "$stage_json" | jq -r '.context // empty')
  local stage_inputs
  stage_inputs=$(echo "$stage_json" | jq -c '.inputs // {}')
  local stage_runs
  stage_runs=$(echo "$stage_json" | jq -r '.runs // 1')
  local stage_provider_override
  stage_provider_override=$(echo "$stage_json" | jq -r '.provider // empty')
  local stage_model_override
  stage_model_override=$(echo "$stage_json" | jq -r '.model // empty')

  local stage_config="{}"
  local stage_desc_default=""
  local stage_context_default=""
  local stage_output_path=""
  local stage_delay=""
  local stage_prompt_path=""
  local stage_provider_default=""
  local stage_model_default=""

  if [ -n "$stage_ref" ]; then
    local stage_dir
    stage_dir=$(resolve_stage_dir "$stage_ref") || return 1
    stage_config=$(yaml_to_json "$stage_dir/stage.yaml")
    stage_desc_default=$(echo "$stage_config" | jq -r '.description // empty')
    stage_context_default=$(echo "$stage_config" | jq -r '.context // empty')
    stage_output_path=$(echo "$stage_config" | jq -r '.output_path // empty')
    stage_delay=$(echo "$stage_config" | jq -r '.delay // empty')
    stage_provider_default=$(echo "$stage_config" | jq -r '.provider // empty')
    stage_model_default=$(echo "$stage_config" | jq -r '.model // empty')

    if [ -z "$stage_prompt_inline" ]; then
      if ! stage_prompt_path=$(resolve_stage_prompt_path "$stage_dir" "$stage_config"); then
        local searched
        searched=$(jq -n --arg path "$stage_dir" '[$path]')
        compile_error "prompt_resolution" "No prompt found for stage '$stage_ref'" "$searched" ""
        return 1
      fi
    fi
  fi

  if [ -z "$stage_ref" ] && [ -z "$stage_prompt_inline" ]; then
    compile_error "stage_resolution" "Stage '$stage_name' missing 'stage' or 'prompt'" "[]" ""
    return 1
  fi

  local stage_desc="$stage_desc_override"
  [ -z "$stage_desc" ] && stage_desc="$stage_desc_default"

  local stage_context="$stage_context_override"
  [ -z "$stage_context" ] && stage_context="$stage_context_default"

  local base_term
  base_term=$(normalize_termination_from_config "$stage_config" "")
  local override_term
  override_term=$(normalize_termination_from_config "$stage_json" "")
  local termination
  termination=$(merge_termination "$base_term" "$override_term" "$stage_runs" "fixed")

  local provider="$stage_provider_override"
  if [ -z "$provider" ]; then
    provider="$stage_provider_default"
  fi
  if [ -z "$provider" ]; then
    provider="$default_provider"
  fi
  if [ -z "$provider" ]; then
    provider="claude"
  fi
  local normalized_provider=""
  if type normalize_provider >/dev/null 2>&1; then
    normalized_provider=$(normalize_provider "$provider")
  fi
  [ -n "$normalized_provider" ] && provider="$normalized_provider"

  local model="$stage_model_override"
  if [ -z "$model" ]; then
    model="$stage_model_default"
  fi
  if [ -z "$model" ]; then
    if [ -n "$stage_provider_override" ] || [ -n "$stage_provider_default" ]; then
      model=$(get_default_model "$provider")
    elif [ -n "$default_model" ]; then
      model="$default_model"
    else
      model=$(get_default_model "$provider")
    fi
  fi

  jq -n \
    --arg path "$stage_idx" \
    --arg id "$stage_name" \
    --arg ref "$stage_ref" \
    --arg desc "$stage_desc" \
    --arg provider "$provider" \
    --arg model "$model" \
    --arg prompt_path "$stage_prompt_path" \
    --arg prompt_inline "$stage_prompt_inline" \
    --arg context "$stage_context" \
    --arg output_path "$stage_output_path" \
    --arg delay "$stage_delay" \
    --argjson termination "$termination" \
    --argjson inputs "$stage_inputs" \
    '{
      path: $path,
      id: $id,
      kind: "stage",
      termination: $termination,
      inputs: $inputs
    }
    + (if $ref != "" then {ref: $ref} else {} end)
    + (if $desc != "" then {description: $desc} else {} end)
    + (if $provider != "" then {provider: {type: $provider, model: $model}} else {} end)
    + (if $prompt_path != "" then {prompt_path: $prompt_path} elif $prompt_inline != "" then {prompt: $prompt_inline} else {} end)
    + (if $context != "" then {context: $context} else {} end)
    + (if $output_path != "" then {output_path: $output_path} else {} end)
    + (if $delay != "" then {delay: ($delay | tonumber)} else {} end)
    '
}

compile_parallel_stage_node() {
  local stage_json=$1
  local stage_path=$2

  local stage_name
  stage_name=$(echo "$stage_json" | jq -r '.name // empty')
  local stage_ref
  stage_ref=$(echo "$stage_json" | jq -r '.stage // .loop // empty')
  local stage_prompt_inline
  stage_prompt_inline=$(echo "$stage_json" | jq -r '.prompt // empty')
  local stage_desc_override
  stage_desc_override=$(echo "$stage_json" | jq -r '.description // empty')
  local stage_context_override
  stage_context_override=$(echo "$stage_json" | jq -r '.context // empty')
  local stage_inputs
  stage_inputs=$(echo "$stage_json" | jq -c '.inputs // {}')
  local stage_runs
  stage_runs=$(echo "$stage_json" | jq -r '.runs // 1')
  local stage_model_override
  stage_model_override=$(echo "$stage_json" | jq -r '.model // empty')

  local stage_config="{}"
  local stage_desc_default=""
  local stage_context_default=""
  local stage_output_path=""
  local stage_delay=""
  local stage_prompt_path=""

  if [ -n "$stage_ref" ]; then
    local stage_dir
    stage_dir=$(resolve_stage_dir "$stage_ref") || return 1
    stage_config=$(yaml_to_json "$stage_dir/stage.yaml")
    stage_desc_default=$(echo "$stage_config" | jq -r '.description // empty')
    stage_context_default=$(echo "$stage_config" | jq -r '.context // empty')
    stage_output_path=$(echo "$stage_config" | jq -r '.output_path // empty')
    stage_delay=$(echo "$stage_config" | jq -r '.delay // empty')

    if [ -z "$stage_prompt_inline" ]; then
      if ! stage_prompt_path=$(resolve_stage_prompt_path "$stage_dir" "$stage_config"); then
        local searched
        searched=$(jq -n --arg path "$stage_dir" '[$path]')
        compile_error "prompt_resolution" "No prompt found for stage '$stage_ref'" "$searched" ""
        return 1
      fi
    fi
  fi

  if [ -z "$stage_ref" ] && [ -z "$stage_prompt_inline" ]; then
    compile_error "stage_resolution" "Stage '$stage_name' missing 'stage' or 'prompt'" "[]" ""
    return 1
  fi

  local stage_desc="$stage_desc_override"
  [ -z "$stage_desc" ] && stage_desc="$stage_desc_default"

  local stage_context="$stage_context_override"
  [ -z "$stage_context" ] && stage_context="$stage_context_default"

  local base_term
  base_term=$(normalize_termination_from_config "$stage_config" "")
  local override_term
  override_term=$(normalize_termination_from_config "$stage_json" "")
  local termination
  termination=$(merge_termination "$base_term" "$override_term" "$stage_runs" "fixed")

  local model="$stage_model_override"

  jq -n \
    --arg path "$stage_path" \
    --arg id "$stage_name" \
    --arg ref "$stage_ref" \
    --arg desc "$stage_desc" \
    --arg model "$model" \
    --arg prompt_path "$stage_prompt_path" \
    --arg prompt_inline "$stage_prompt_inline" \
    --arg context "$stage_context" \
    --arg output_path "$stage_output_path" \
    --arg delay "$stage_delay" \
    --argjson termination "$termination" \
    --argjson inputs "$stage_inputs" \
    '{
      path: $path,
      id: $id,
      kind: "stage",
      termination: $termination,
      inputs: $inputs
    }
    + (if $ref != "" then {ref: $ref} else {} end)
    + (if $desc != "" then {description: $desc} else {} end)
    + (if $model != "" then {model: $model} else {} end)
    + (if $prompt_path != "" then {prompt_path: $prompt_path} elif $prompt_inline != "" then {prompt: $prompt_inline} else {} end)
    + (if $context != "" then {context: $context} else {} end)
    + (if $output_path != "" then {output_path: $output_path} else {} end)
    + (if $delay != "" then {delay: ($delay | tonumber)} else {} end)
    '
}

compile_parallel_node() {
  local stage_json=$1
  local stage_idx=$2

  local stage_name
  stage_name=$(echo "$stage_json" | jq -r '.name // empty')
  local stage_desc
  stage_desc=$(echo "$stage_json" | jq -r '.description // empty')
  local stage_inputs
  stage_inputs=$(echo "$stage_json" | jq -c '.inputs // {}')

  local parallel_config
  parallel_config=$(echo "$stage_json" | jq -c '.parallel')
  local providers
  providers=$(echo "$parallel_config" | jq -c '.providers // []')
  local failure_mode
  failure_mode=$(echo "$parallel_config" | jq -r '.failure_mode // empty')

  local stages_json
  stages_json=$(echo "$parallel_config" | jq -c '.stages // []')
  local stage_count
  stage_count=$(echo "$stages_json" | jq -r 'length')

  local compiled_stages=()
  for stage_idx_inner in $(seq 0 $((stage_count - 1))); do
    local inner_stage
    inner_stage=$(echo "$stages_json" | jq -c ".[$stage_idx_inner]")
    local stage_path="${stage_idx}.${stage_idx_inner}"
    compiled_stages+=("$(compile_parallel_stage_node "$inner_stage" "$stage_path")")
  done

  local compiled_stages_json="[]"
  if [ ${#compiled_stages[@]} -gt 0 ]; then
    compiled_stages_json=$(printf '%s\n' "${compiled_stages[@]}" | jq -s '.')
  fi

  jq -n \
    --arg path "$stage_idx" \
    --arg id "$stage_name" \
    --arg desc "$stage_desc" \
    --arg failure_mode "$failure_mode" \
    --argjson providers "$providers" \
    --argjson stages "$compiled_stages_json" \
    --argjson inputs "$stage_inputs" \
    '{
      path: $path,
      id: $id,
      kind: "parallel",
      providers: $providers,
      stages: $stages,
      inputs: $inputs
    }
    + (if $desc != "" then {description: $desc} else {} end)
    + (if $failure_mode != "" then {failure_mode: $failure_mode} else {} end)
    '
}

compile_pipeline_file() {
  local pipeline_file=$1
  local output_file=$2
  local session_name=${3:-""}

  if [ -z "$pipeline_file" ] || [ -z "$output_file" ]; then
    print_compile_usage
    return 1
  fi

  check_deps || return 1

  if ! validate_pipeline_file "$pipeline_file" "--quiet"; then
    compile_error "pipeline_validation" "Pipeline validation failed" "[]" "Run './scripts/run.sh lint pipeline <name>' for details"
    return 1
  fi

  local pipeline_json
  pipeline_json=$(yaml_to_json "$pipeline_file")
  local pipeline_name
  pipeline_name=$(json_get "$pipeline_json" ".name" "pipeline")
  local pipeline_desc
  pipeline_desc=$(json_get "$pipeline_json" ".description" "")
  local pipeline_inputs
  pipeline_inputs=$(echo "$pipeline_json" | jq -c '.inputs // []')
  local pipeline_commands
  pipeline_commands=$(echo "$pipeline_json" | jq -c '.commands // {}')
  local default_provider
  default_provider=$(json_get "$pipeline_json" ".defaults.provider" "claude")
  local default_model
  default_model=$(json_get "$pipeline_json" ".defaults.model" "")
  if [ -z "$default_model" ]; then
    default_model=$(get_default_model "$default_provider")
  fi

  local stage_count
  stage_count=$(echo "$pipeline_json" | jq -r '.stages | length')
  local nodes=()

  for stage_idx in $(seq 0 $((stage_count - 1))); do
    local stage_json
    stage_json=$(echo "$pipeline_json" | jq -c ".stages[$stage_idx]")
    local is_parallel=""
    is_parallel=$(echo "$stage_json" | jq -e '.parallel' 2>/dev/null || true)

    if [ -n "$is_parallel" ] && [ "$is_parallel" != "null" ]; then
      nodes+=("$(compile_parallel_node "$stage_json" "$stage_idx")")
    else
      nodes+=("$(compile_stage_node "$stage_json" "$stage_idx" "$default_provider" "$default_model")")
    fi
  done

  local nodes_json="[]"
  if [ ${#nodes[@]} -gt 0 ]; then
    nodes_json=$(printf '%s\n' "${nodes[@]}" | jq -s '.')
  fi

  local compiled_at
  compiled_at=$(compile_timestamp)
  local source_path
  source_path=$(strip_project_root "$pipeline_file")
  local source_sha
  source_sha=$(sha256_file "$pipeline_file") || return 1
  local session_created_at="${SESSION_CREATED_AT:-$compiled_at}"
  if [ -z "$session_name" ]; then
    session_name="$pipeline_name"
  fi

  local dependencies_json
  dependencies_json=$(infer_dependencies "$nodes_json" "$pipeline_json")

  local plan_json
  plan_json=$(jq -n \
    --arg compiled_at "$compiled_at" \
    --arg source_path "$source_path" \
    --arg source_sha "$source_sha" \
    --arg session_name "$session_name" \
    --arg session_created_at "$session_created_at" \
    --arg pipeline_name "$pipeline_name" \
    --arg pipeline_desc "$pipeline_desc" \
    --argjson pipeline_inputs "$pipeline_inputs" \
    --argjson pipeline_commands "$pipeline_commands" \
    --argjson dependencies "$dependencies_json" \
    --argjson nodes "$nodes_json" \
    '{
      version: 1,
      compiled_at: $compiled_at,
      source: {path: $source_path, sha256: $source_sha},
      session: {name: $session_name, created_at: $session_created_at},
      pipeline: ({name: $pipeline_name}
        + (if $pipeline_desc != "" then {description: $pipeline_desc} else {} end)
        + (if ($pipeline_inputs | length) > 0 then {inputs: $pipeline_inputs} else {} end)
        + (if ($pipeline_commands | length) > 0 then {commands: $pipeline_commands} else {} end)),
      dependencies: $dependencies,
      nodes: $nodes
    }')

  if ! validate_plan_json "$plan_json"; then
    compile_error "plan_validation" "Compiled plan.json failed validation" "[]" ""
    return 1
  fi

  mkdir -p "$(dirname "$output_file")"
  echo "$plan_json" > "$output_file"
}

compile_plan() {
  local pipeline_file=$1
  local session_name=$2
  local run_dir=$3

  if [ -z "$pipeline_file" ] || [ -z "$session_name" ] || [ -z "$run_dir" ]; then
    print_compile_usage
    return 1
  fi

  compile_pipeline_file "$pipeline_file" "$run_dir/plan.json" "$session_name"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [ $# -lt 2 ]; then
    print_compile_usage
    exit 1
  fi

  pipeline_file=""
  session_name=""
  output_file=""
  run_dir=""
  positional=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --session)
        session_name="${2:-}"
        shift 2
        ;;
      --output)
        output_file="${2:-}"
        shift 2
        ;;
      --run-dir)
        run_dir="${2:-}"
        shift 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if [ ${#positional[@]} -ge 1 ]; then
    pipeline_file="${positional[0]}"
  fi

  if [ -n "$run_dir" ]; then
    if [ -z "$session_name" ] && [ ${#positional[@]} -ge 2 ]; then
      session_name="${positional[1]}"
    fi
    compile_plan "$pipeline_file" "$session_name" "$run_dir"
    exit $?
  fi

  if [ -z "$output_file" ]; then
    if [ ${#positional[@]} -ge 3 ]; then
      session_name="${session_name:-${positional[1]}}"
      run_dir="${positional[2]}"
      compile_plan "$pipeline_file" "$session_name" "$run_dir"
      exit $?
    fi
    if [ ${#positional[@]} -ge 2 ]; then
      output_file="${positional[1]}"
    fi
  fi

  if [ -z "$pipeline_file" ] || [ -z "$output_file" ]; then
    print_compile_usage
    exit 1
  fi

  compile_pipeline_file "$pipeline_file" "$output_file" "$session_name"
fi
