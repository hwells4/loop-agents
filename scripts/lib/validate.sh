#!/bin/bash
# Validation Library
# Validates loop and pipeline configurations before execution
#
# Usage:
#   source "$LIB_DIR/validate.sh"
#   validate_loop "work"        # Returns 0 if valid, 1 if errors
#   validate_pipeline "full-refine"
#   lint_all                    # Validate all loops and pipelines

VALIDATE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$VALIDATE_SCRIPT_DIR/yaml.sh"

# Validate a session name for safety
# Usage: validate_session_name "session-name"
# Returns: 0 if valid, 1 if invalid
validate_session_name() {
  local name=$1

  # Check for empty
  if [ -z "$name" ]; then
    echo "Error: Session name cannot be empty" >&2
    return 1
  fi

  # Check length (max 64 chars)
  if [ ${#name} -gt 64 ]; then
    echo "Error: Session name too long (max 64 characters)" >&2
    return 1
  fi

  # Check for valid characters (alphanumeric, underscore, hyphen)
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Session name must contain only alphanumeric characters, underscores, and hyphens" >&2
    return 1
  fi

  return 0
}

# Known template variables (including v3 variables: CTX, STATUS, CONTEXT)
KNOWN_VARS="SESSION SESSION_NAME ITERATION INDEX PERSPECTIVE OUTPUT OUTPUT_PATH PROGRESS PROGRESS_FILE INPUTS CTX STATUS RESULT CONTEXT"

yaml_line_for_path() {
  local file=$1
  local path=$2

  if ! command -v yq >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  local line
  line=$(yq e "${path} | line" "$file" 2>/dev/null || true)
  if [ -z "$line" ] || [ "$line" = "0" ] || [ "$line" = "null" ]; then
    echo ""
  else
    echo "$line"
  fi
}

format_line_suffix() {
  local line=$1
  if [ -n "$line" ]; then
    echo " (line $line)"
  else
    echo ""
  fi
}

resolve_pipeline_path() {
  local pipeline_ref=$1
  local pipelines_base="${PIPELINES_DIR:-${VALIDATE_SCRIPT_DIR}/../pipelines}"

  if [[ "$pipeline_ref" == /* ]] && [ -f "$pipeline_ref" ]; then
    echo "$pipeline_ref"
    return 0
  fi
  if [ -f "$pipeline_ref" ]; then
    echo "$pipeline_ref"
    return 0
  fi
  if [ -f "$pipelines_base/$pipeline_ref" ]; then
    echo "$pipelines_base/$pipeline_ref"
    return 0
  fi
  if [ -f "$pipelines_base/$pipeline_ref.yaml" ]; then
    echo "$pipelines_base/$pipeline_ref.yaml"
    return 0
  fi

  return 1
}

# Validate a loop configuration
# Usage: validate_stage "stage-name" [--quiet]
# Returns: 0 if valid, 1 if errors found
validate_loop() {
  local name=$1
  local quiet=${2:-""}
  local stages_dir="${VALIDATE_SCRIPT_DIR}/../stages"
  local dir="$stages_dir/$name"
  local errors=()
  local warnings=()

  # L001: Directory exists
  if [ ! -d "$dir" ]; then
    errors+=("Loop directory not found: $dir")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L002: stage.yaml exists
  local config_file="$dir/stage.yaml"
  if [ ! -f "$config_file" ]; then
    errors+=("Missing stage.yaml")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L003: YAML parses correctly
  local config
  config=$(yaml_to_json "$config_file" 2>&1)
  if [ $? -ne 0 ] || [ -z "$config" ] || [ "$config" = "{}" ]; then
    errors+=("Invalid YAML syntax in stage.yaml")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L004: name field present
  local loop_name=$(json_get "$config" ".name" "")
  if [ -z "$loop_name" ]; then
    errors+=("Missing 'name' field in stage.yaml")
  fi

  # L005: name matches directory (warning)
  if [ -n "$loop_name" ] && [ "$loop_name" != "$name" ]; then
    warnings+=("Loop name '$loop_name' doesn't match directory name '$name'")
  fi

  # L006: termination block present (v3) OR completion field (v2 legacy)
  local term_type=$(json_get "$config" ".termination.type" "")
  local completion=$(json_get "$config" ".completion" "")

  if [ -z "$term_type" ] && [ -z "$completion" ]; then
    errors+=("Missing 'termination.type' field in stage.yaml (v3 schema)")
  fi

  # L007: termination type maps to completion strategy
  local strategy=""
  if [ -n "$term_type" ]; then
    # v3 schema: map termination type to strategy file
    case "$term_type" in
      queue) strategy="beads-empty" ;;
      judgment) strategy="plateau" ;;
      fixed) strategy="fixed-n" ;;
      *) strategy="$term_type" ;;
    esac
  else
    # v2 legacy: use completion field directly
    strategy="$completion"
  fi

  if [ -n "$strategy" ]; then
    local completion_file="$VALIDATE_SCRIPT_DIR/completions/${strategy}.sh"
    if [ ! -f "$completion_file" ]; then
      errors+=("Unknown termination type: $term_type (strategy file not found: $completion_file)")
    fi
  fi

  # L008: prompt.md exists
  local prompt_file=$(json_get "$config" ".prompt" "prompt.md")
  if [ ! -f "$dir/$prompt_file" ]; then
    errors+=("Missing prompt file: $prompt_file")
  fi

  # L009: v3 judgment loops need consensus (v2 plateau needs output_parse - legacy)
  if [ "$strategy" = "plateau" ]; then
    if [ -n "$term_type" ]; then
      # v3: judgment loops should have consensus
      local consensus=$(json_get "$config" ".termination.consensus" "")
      if [ -z "$consensus" ]; then
        warnings+=("Judgment loops should specify 'termination.consensus' (defaulting to 2)")
      fi
    else
      # v2 legacy: plateau loops need output_parse with PLATEAU
      local output_parse=$(json_get "$config" ".output_parse" "")
      if [ -z "$output_parse" ]; then
        errors+=("Plateau loops require 'output_parse' field")
      elif [[ "$output_parse" != *"PLATEAU"* ]]; then
        errors+=("Plateau loops require 'plateau:PLATEAU' in output_parse")
      fi
    fi
  fi

  # L010: Judgment/plateau loops should have min_iterations >= 2 (warning)
  if [ "$strategy" = "plateau" ]; then
    local min_iter
    if [ -n "$term_type" ]; then
      min_iter=$(json_get "$config" ".termination.min_iterations" "1")
    else
      min_iter=$(json_get "$config" ".min_iterations" "1")
    fi
    if [ "$min_iter" -lt 2 ]; then
      warnings+=("Judgment loops should have min_iterations >= 2 (current: $min_iter)")
    fi
  fi

  # L011: Check template variables in prompt (warning)
  if [ -f "$dir/$prompt_file" ]; then
    local prompt_content=$(cat "$dir/$prompt_file")
    # Extract ${VAR} patterns
    local found_vars=$(echo "$prompt_content" | grep -oE '\$\{[A-Z_]+\}' | sed 's/\${//g; s/}//g' | sort -u)
    for var in $found_vars; do
      # Check if it's a known var or INPUTS.something
      if [[ "$var" == INPUTS.* ]]; then
        continue  # INPUTS.stage-name is valid
      fi
      if [[ ! " $KNOWN_VARS " =~ " $var " ]]; then
        warnings+=("Unknown template variable: \${$var}")
      fi
    done
  fi

  # Print result
  if [ ${#errors[@]} -gt 0 ]; then
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}" "${warnings[@]}"
    return 1
  else
    [ -z "$quiet" ] && print_result "PASS" "$name" "" "${warnings[@]}"
    return 0
  fi
}

# Validate a pipeline configuration by file path
# Usage: validate_pipeline_file "/path/to/pipeline.yaml" [--quiet]
# Returns: 0 if valid, 1 if errors found
validate_pipeline_file() {
  local file=$1
  local quiet=${2:-""}
  local name=$(basename "$file" .yaml)
  local errors=()
  local warnings=()

  # P001: Pipeline file exists
  if [ ! -f "$file" ]; then
    errors+=("Pipeline file not found: $file")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # Delegate to common validation logic
  _validate_pipeline_impl "$file" "$name" "$quiet"
}

# Validate a pipeline configuration by name (looks in pipelines directory)
# Usage: validate_pipeline "pipeline-name" [--quiet]
# Returns: 0 if valid, 1 if errors found
validate_pipeline() {
  local name=$1
  local quiet=${2:-""}
  local pipelines_dir="${VALIDATE_SCRIPT_DIR}/../pipelines"
  local file="$pipelines_dir/${name}.yaml"

  # P001: Pipeline file exists
  if [ ! -f "$file" ]; then
    # Try without .yaml extension
    if [ ! -f "$pipelines_dir/$name" ]; then
      [ -z "$quiet" ] && print_result "FAIL" "$name" "Pipeline file not found: $file"
      return 1
    fi
    file="$pipelines_dir/$name"
  fi

  # Delegate to common validation logic
  _validate_pipeline_impl "$file" "$name" "$quiet"
}

# Internal: Validate a parallel block
# Usage: _validate_parallel_block "$node_json" "$node_name" "$node_idx" "$file" "$nodes_key"
# Outputs lines prefixed with ERROR:, WARNING:, or STAGE: for the caller to parse
# Returns 0 if valid, 1 if errors found
_validate_parallel_block() {
  local stage_json=$1
  local stage_name=$2
  local stage_idx=$3
  local file=$4
  local nodes_key=$5
  local had_error=0

  local parallel=$(echo "$stage_json" | jq '.parallel')
  local block_line
  block_line=$(yaml_line_for_path "$file" ".${nodes_key}[$stage_idx].parallel")
  local block_suffix
  block_suffix=$(format_line_suffix "$block_line")

  # P012: parallel.providers required and non-empty
  local providers=$(echo "$parallel" | jq -r '.providers // empty')
  if [ -z "$providers" ] || [ "$providers" = "null" ]; then
    echo "ERROR:Parallel block '$stage_name': missing 'providers' array${block_suffix}"
    return 1
  fi

  local providers_len=$(echo "$parallel" | jq '.providers | length')
  if [ "$providers_len" -eq 0 ]; then
    echo "ERROR:Parallel block '$stage_name': 'providers' array cannot be empty${block_suffix}"
    return 1
  fi

  # P013: parallel.stages required and non-empty
  local block_stages=$(echo "$parallel" | jq -r '.stages // empty')
  if [ -z "$block_stages" ] || [ "$block_stages" = "null" ]; then
    echo "ERROR:Parallel block '$stage_name': missing 'stages' array${block_suffix}"
    return 1
  fi

  local block_stages_len=$(echo "$parallel" | jq '.stages | length')
  if [ "$block_stages_len" -eq 0 ]; then
    echo "ERROR:Parallel block '$stage_name': 'stages' array cannot be empty${block_suffix}"
    return 1
  fi

  # Track stage names within this block for uniqueness
  local block_stage_names=""

  # Validate each stage in the parallel block
  for ((j=0; j<block_stages_len; j++)); do
    local block_stage=$(echo "$parallel" | jq -r ".stages[$j]")
    local block_stage_name=$(echo "$block_stage" | jq -r '.id // .name // empty')
    local stage_line
    stage_line=$(yaml_line_for_path "$file" ".${nodes_key}[$stage_idx].parallel.stages[$j]")
    local stage_suffix
    stage_suffix=$(format_line_suffix "$stage_line")

    # Each block stage needs a name
    if [ -z "$block_stage_name" ]; then
      echo "ERROR:Parallel block '$stage_name', stage $j: missing 'id' field${stage_suffix}"
      had_error=1
      continue
    fi

    # P016: Stage names unique within block (use string matching for bash 3.x compat)
    if [[ " $block_stage_names " == *" $block_stage_name "* ]]; then
      echo "ERROR:Parallel block '$stage_name': duplicate stage name '$block_stage_name'${stage_suffix}"
      had_error=1
    fi
    block_stage_names="$block_stage_names $block_stage_name"
    echo "STAGE:$block_stage_name"

    # P014: No nested parallel blocks
    local nested_parallel=$(echo "$block_stage" | jq -e '.parallel' 2>/dev/null)
    if [ "$nested_parallel" != "null" ] && [ -n "$nested_parallel" ]; then
      echo "ERROR:Parallel block '$stage_name': nested parallel blocks not allowed (found in '$block_stage_name')${stage_suffix}"
      had_error=1
    fi

    # P015: No provider override within block stages
    local stage_provider=$(echo "$block_stage" | jq -r '.provider // empty')
    if [ -n "$stage_provider" ] && [ "$stage_provider" != "null" ]; then
      echo "ERROR:Parallel block '$stage_name': stage '$block_stage_name' cannot override provider (block controls provider)${stage_suffix}"
      had_error=1
    fi

    # Validate stage reference exists
    local stage_ref=$(echo "$block_stage" | jq -r '.stage // empty')
    local stage_prompt=$(echo "$block_stage" | jq -r '.prompt // empty')
    if [ -z "$stage_ref" ] && [ -z "$stage_prompt" ]; then
      echo "ERROR:Parallel block '$stage_name': stage '$block_stage_name' missing 'stage' or 'prompt'${stage_suffix}"
      had_error=1
    fi
    if [ -n "$stage_ref" ]; then
      local stages_base="${STAGES_DIR:-${VALIDATE_SCRIPT_DIR}/../stages}"
      local stage_dir="$stages_base/$stage_ref"
      if [ ! -d "$stage_dir" ]; then
        echo "ERROR:Parallel block '$stage_name', stage '$block_stage_name': references unknown stage '$stage_ref'${stage_suffix}"
        had_error=1
      fi
    fi
  done

  return $had_error
}

# Internal: Common pipeline validation logic
# Usage: _validate_pipeline_impl "/path/to/file.yaml" "display-name" [--quiet]
_validate_pipeline_impl() {
  local file=$1
  local name=$2
  local quiet=${3:-""}
  local errors=()
  local warnings=()

  # P002: YAML parses correctly
  local config
  config=$(yaml_to_json "$file" 2>&1)
  if [ $? -ne 0 ] || [ -z "$config" ] || [ "$config" = "{}" ]; then
    errors+=("Invalid YAML syntax")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # P003: name field present
  local pipeline_name=$(json_get "$config" ".name" "")
  if [ -z "$pipeline_name" ]; then
    errors+=("Missing 'name' field")
  fi

  # P004: nodes array present (stages deprecated)
  local nodes_len=$(json_array_len "$config" ".nodes")
  local stages_len=$(json_array_len "$config" ".stages")
  local nodes_key=""
  local nodes_len_used=0
  local nodes_line
  nodes_line=$(yaml_line_for_path "$file" ".nodes")

  if [ "$nodes_len" -gt 0 ]; then
    nodes_key="nodes"
    nodes_len_used=$nodes_len
    if [ "$stages_len" -gt 0 ]; then
      local stages_line
      stages_line=$(yaml_line_for_path "$file" ".stages")
      warnings+=("Both 'nodes' and 'stages' present; ignoring 'stages'$(format_line_suffix "$stages_line")")
    fi
  elif [ "$stages_len" -gt 0 ]; then
    nodes_key="stages"
    nodes_len_used=$stages_len
    local stages_line
    stages_line=$(yaml_line_for_path "$file" ".stages")
    local stages_suffix
    stages_suffix=$(format_line_suffix "$stages_line")
    warnings+=("Deprecated 'stages' key used; rename to 'nodes'${stages_suffix}")
    if [ -n "$stages_suffix" ]; then
      echo "Warning: Pipeline '$name' uses deprecated 'stages' key${stages_suffix}." >&2
    else
      echo "Warning: Pipeline '$name' uses deprecated 'stages' key." >&2
    fi
  else
    if [ -n "$nodes_line" ]; then
      errors+=("Empty 'nodes' array$(format_line_suffix "$nodes_line")")
    else
      errors+=("Missing 'nodes' array (line 1)")
    fi
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # Collect node ids for reference validation
  local node_ids=()
  # Collect parallel block stage names for from_parallel validation
  local parallel_stage_names=()

  # Validate each node
  for ((i=0; i<nodes_len_used; i++)); do
    local node=$(echo "$config" | jq -r ".${nodes_key}[$i]")
    local node_id=$(echo "$node" | jq -r ".id // .name // empty")
    local node_line
    node_line=$(yaml_line_for_path "$file" ".${nodes_key}[$i]")
    local node_suffix
    node_suffix=$(format_line_suffix "$node_line")

    # P005: Each node has id
    if [ -z "$node_id" ]; then
      errors+=("Node $i: missing 'id' field${node_suffix}")
      continue
    fi

    # P006: Node ids are unique
    if [[ " ${node_ids[*]} " =~ " $node_id " ]]; then
      errors+=("Duplicate node id: $node_id${node_suffix}")
    fi
    node_ids+=("$node_id")

    # Check if this is a parallel block
    local is_parallel=$(echo "$node" | jq -e '.parallel' 2>/dev/null)
    if [ "$is_parallel" != "null" ] && [ -n "$is_parallel" ]; then
      # Validate parallel block and parse output
      local block_output
      block_output=$(_validate_parallel_block "$node" "$node_id" "$i" "$file" "$nodes_key")
      local block_result=$?

      # Parse output lines
      while IFS= read -r line; do
        case "$line" in
          ERROR:*)
            errors+=("${line#ERROR:}")
            ;;
          WARNING:*)
            warnings+=("${line#WARNING:}")
            ;;
          STAGE:*)
            parallel_stage_names+=("${line#STAGE:}")
            ;;
        esac
      done <<< "$block_output"

      continue
    fi

    # P007: Each node has pipeline or stage/prompt
    local pipeline_ref=$(echo "$node" | jq -r ".pipeline // empty")
    local stage_ref=$(echo "$node" | jq -r ".stage // empty")
    # Support legacy .loop keyword (Bug fix: parallel to loop-agents-sam)
    [ -z "$stage_ref" ] && stage_ref=$(echo "$node" | jq -r ".loop // empty")
    local stage_prompt=$(echo "$node" | jq -r ".prompt // empty")

    if [ -n "$pipeline_ref" ] && { [ -n "$stage_ref" ] || [ -n "$stage_prompt" ]; }; then
      errors+=("Node '$node_id': cannot mix 'pipeline' with 'stage' or 'prompt'${node_suffix}")
      continue
    fi

    if [ -n "$pipeline_ref" ]; then
      if ! resolve_pipeline_path "$pipeline_ref" >/dev/null; then
        errors+=("Node '$node_id': references unknown pipeline '$pipeline_ref'${node_suffix}")
      fi
      local runs_type
      runs_type=$(echo "$node" | jq -r '.runs | type' 2>/dev/null || echo "null")
      if [ "$runs_type" = "string" ]; then
        local runs_value
        runs_value=$(echo "$node" | jq -r '.runs')
        if [[ ! "$runs_value" =~ ^[0-9]+$ ]]; then
          errors+=("Node '$node_id': runs must be numeric${node_suffix}")
        fi
      elif [ "$runs_type" != "number" ] && [ "$runs_type" != "null" ]; then
        errors+=("Node '$node_id': runs must be numeric${node_suffix}")
      fi
      continue
    fi

    if [ -z "$stage_ref" ] && [ -z "$stage_prompt" ]; then
      errors+=("Node '$node_id': needs 'stage' or 'prompt' field${node_suffix}")
    fi

    # P008: Referenced stages exist
    # Use STAGES_DIR if set (for tests), otherwise use default path
    if [ -n "$stage_ref" ]; then
      local stages_base="${STAGES_DIR:-${VALIDATE_SCRIPT_DIR}/../stages}"
      local stage_dir="$stages_base/$stage_ref"
      if [ ! -d "$stage_dir" ]; then
        errors+=("Node '$node_id': references unknown stage '$stage_ref'${node_suffix}")
      fi
    fi

    # P011: Each stage node should have runs field (warning)
    local runs_type
    runs_type=$(echo "$node" | jq -r ".runs | type" 2>/dev/null || echo "null")
    if [ "$runs_type" = "null" ]; then
      warnings+=("Node '$node_id': missing 'runs' field (will use default)${node_suffix}")
    fi
  done

  # P009: Check INPUTS references (need all nodes collected first)
  for ((i=0; i<nodes_len_used; i++)); do
    local node=$(echo "$config" | jq -r ".${nodes_key}[$i]")
    local node_id=$(echo "$node" | jq -r ".id // .name // empty")
    local node_prompt=$(echo "$node" | jq -r ".prompt // empty")
    local node_line
    node_line=$(yaml_line_for_path "$file" ".${nodes_key}[$i]")
    local node_suffix
    node_suffix=$(format_line_suffix "$node_line")

    # Check for ${INPUTS.node-id} references
    if [ -n "$node_prompt" ]; then
      local refs=$(echo "$node_prompt" | grep -oE '\$\{INPUTS\.[a-zA-Z0-9_-]+\}' | sed 's/\${INPUTS\.//g; s/}//g')
      for ref in $refs; do
        if [[ ! " ${node_ids[*]} " =~ " $ref " ]]; then
          errors+=("Node '$node_id': references unknown node '\${INPUTS.$ref}'${node_suffix}")
        fi
      done
    fi

    # P010: First node shouldn't use INPUTS (warning)
    if [ $i -eq 0 ] && [ -n "$node_prompt" ]; then
      if [[ "$node_prompt" == *'${INPUTS'* ]]; then
        warnings+=("Node '$node_id': first node uses \${INPUTS} which will be empty${node_suffix}")
      fi
    fi

    # P017: Check from_parallel references
    local from_parallel=$(echo "$node" | jq -r '.inputs.from_parallel // empty')
    if [ -n "$from_parallel" ] && [ "$from_parallel" != "null" ]; then
      # Handle both shorthand (string) and full object form
      local ref_stage=""
      # If it doesn't start with {, it's a simple string reference
      if [[ "$from_parallel" != "{"* ]]; then
        ref_stage="$from_parallel"
      else
        ref_stage=$(echo "$from_parallel" | jq -r '.stage // empty')
      fi

      # Check reference exists (use string matching for bash 3.x compatibility)
      local parallel_names_str=" ${parallel_stage_names[*]} "
      if [ -n "$ref_stage" ] && [[ "$parallel_names_str" != *" $ref_stage "* ]]; then
        errors+=("Node '$node_id': from_parallel references unknown stage '$ref_stage'${node_suffix}")
      fi
    fi
  done

  # Print result
  if [ ${#errors[@]} -gt 0 ]; then
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}" "${warnings[@]}"
    return 1
  else
    [ -z "$quiet" ] && print_result "PASS" "$name" "" "${warnings[@]}"
    return 0
  fi
}

# Print validation result
# Usage: print_result "PASS|FAIL" "name" "errors..." "warnings..."
print_result() {
  local result_status=$1
  local name=$2
  shift 2

  # Separate errors and warnings (errors come first, then warnings)
  local errors=()
  local warnings=()
  local in_warnings=false

  for arg in "$@"; do
    if [ -z "$arg" ]; then
      in_warnings=true
      continue
    fi
    if [ "$in_warnings" = true ]; then
      warnings+=("$arg")
    else
      errors+=("$arg")
    fi
  done

  if [ "$result_status" = "PASS" ]; then
    echo "  $name"
    echo "    [PASS] All checks passed"
  else
    echo "  $name"
    echo "    [FAIL] Validation failed"
  fi

  for err in "${errors[@]}"; do
    echo "    [ERROR] $err"
  done

  for warn in "${warnings[@]}"; do
    echo "    [WARN] $warn"
  done
}

# Lint all loops and pipelines
# Usage: lint_all [--json] [--strict]
lint_all() {
  local json_output=false
  local strict=false
  local target_type=""
  local target_name=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --json) json_output=true; shift ;;
      --strict) strict=true; shift ;;
      loop|pipeline)
        target_type=$1
        target_name=$2
        shift 2
        ;;
      *) shift ;;
    esac
  done

  local total=0
  local passed=0
  local failed=0
  local warn_count=0

  # Single target validation
  if [ -n "$target_type" ] && [ -n "$target_name" ]; then
    if [ "$target_type" = "loop" ]; then
      validate_loop "$target_name"
      return $?
    elif [ "$target_type" = "pipeline" ]; then
      # If target_name contains a path separator or ends with .yaml, treat as file path
      if [[ "$target_name" == */* ]] || [[ "$target_name" == *.yaml ]]; then
        validate_pipeline_file "$target_name"
      else
        validate_pipeline "$target_name"
      fi
      return $?
    fi
  fi

  # Validate all loops
  echo "Validating loops..."
  echo ""
  local stages_dir="${VALIDATE_SCRIPT_DIR}/../stages"
  for dir in "$stages_dir"/*/; do
    [ -d "$dir" ] || continue
    local name=$(basename "$dir")
    total=$((total + 1))
    if validate_loop "$name"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  echo ""
  echo "Validating pipelines..."
  echo ""

  # Validate all pipelines
  local pipelines_dir="${VALIDATE_SCRIPT_DIR}/../pipelines"
  for file in "$pipelines_dir"/*.yaml; do
    [ -f "$file" ] || continue
    local name=$(basename "$file" .yaml)
    total=$((total + 1))
    if validate_pipeline "$name"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  echo ""
  echo "Summary: $total targets, $passed passed, $failed failed"

  if [ $failed -gt 0 ]; then
    return 1
  fi
  return 0
}

# Generate a dry-run preview for a loop
# Usage: dry_run_stage "stage-name" "session-name"
dry_run_loop() {
  local name=$1
  local session=${2:-"preview"}
  local stages_dir="${VALIDATE_SCRIPT_DIR}/../stages"
  local dir="$stages_dir/$name"

  # First validate
  echo "# Dry Run: Loop $name"
  echo ""
  echo "## Validation"
  echo ""
  if ! validate_loop "$name"; then
    echo ""
    echo "**Cannot proceed: validation failed**"
    return 1
  fi
  echo ""

  # Load config
  local config=$(yaml_to_json "$dir/stage.yaml")
  local description=$(json_get "$config" ".description" "")
  local delay=$(json_get "$config" ".delay" "3")
  local prompt_file=$(json_get "$config" ".prompt" "prompt.md")

  # v3 termination fields
  local term_type=$(json_get "$config" ".termination.type" "")
  local consensus=$(json_get "$config" ".termination.consensus" "2")
  local min_iter=$(json_get "$config" ".termination.min_iterations" "2")

  echo "## Configuration"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| name | $name |"
  echo "| description | $description |"
  if [ -n "$term_type" ]; then
    echo "| termination.type | $term_type |"
    [ "$term_type" = "judgment" ] && echo "| termination.consensus | $consensus |"
    [ "$term_type" = "judgment" ] && echo "| termination.min_iterations | $min_iter |"
  fi
  echo "| delay | ${delay}s |"
  echo ""

  echo "## Files"
  echo ""
  echo "| Purpose | Path |"
  echo "|---------|------|"
  echo "| Run directory | .claude/pipeline-runs/${session}/ |"
  echo "| State file | .claude/pipeline-runs/${session}/state.json |"
  echo "| Progress file | .claude/pipeline-runs/${session}/stage-00-${name}/progress.md |"
  echo "| Iteration dir | .claude/pipeline-runs/${session}/stage-00-${name}/iterations/001/ |"
  echo "| Context file | .claude/pipeline-runs/${session}/stage-00-${name}/iterations/001/context.json |"
  echo "| Result file | .claude/pipeline-runs/${session}/stage-00-${name}/iterations/001/result.json |"
  echo "| Lock file | .claude/locks/${session}.lock |"
  echo ""

  echo "## Resolved Prompt (Iteration 1)"
  echo ""
  echo '```markdown'

  # Use resolve.sh to resolve the prompt
  source "$VALIDATE_SCRIPT_DIR/resolve.sh"
  local vars_json=$(cat <<EOF
{
  "session": "$session",
  "iteration": "1",
  "index": "0",
  "progress": ".claude/pipeline-runs/${session}/progress-${session}.md"
}
EOF
)
  load_and_resolve_prompt "$dir/$prompt_file" "$vars_json"
  echo '```'
  echo ""

  echo "## Termination Strategy"
  echo ""
  echo "**Type:** $term_type"
  echo ""
  case $term_type in
    queue)
      echo "The loop will stop when:"
      echo "- \`bd ready --label=pipeline/${session}\` returns 0 results"
      echo "- Engine-owned decider continues while queue has items"
      ;;
    judgment)
      echo "The loop will stop when:"
      echo "- $consensus consecutive iterations set \`signals.plateau_suspected: true\` in result.json"
      echo "- Minimum iterations before checking: $min_iter"
      ;;
    fixed)
      echo "The loop will stop when:"
      echo "- N iterations have completed (N specified at runtime)"
      ;;
  esac
}

# Generate a dry-run preview for a pipeline
# Usage: dry_run_pipeline "pipeline-name" "session-name"
dry_run_pipeline() {
  local name=$1
  local session=${2:-"preview"}
  local pipelines_dir="${VALIDATE_SCRIPT_DIR}/../pipelines"
  local file="$pipelines_dir/${name}.yaml"

  if [ ! -f "$file" ]; then
    file="$pipelines_dir/$name"
  fi

  # First validate
  echo "# Dry Run: Pipeline $name"
  echo ""
  echo "## Validation"
  echo ""
  if ! validate_pipeline "$name"; then
    echo ""
    echo "**Cannot proceed: validation failed**"
    return 1
  fi
  echo ""

  # Compile the pipeline to get merged config with overrides applied
  source "$VALIDATE_SCRIPT_DIR/compile.sh"
  local tmp_plan=$(mktemp)
  trap "rm -f '$tmp_plan'" EXIT
  if ! compile_pipeline_file "$file" "$tmp_plan" "$session" 2>/dev/null; then
    echo "**Warning: Could not compile pipeline, falling back to raw config**"
    local plan_json="{}"
  else
    local plan_json=$(cat "$tmp_plan")
  fi

  # Load raw config for basic info
  local config=$(yaml_to_json "$file")
  local description=$(json_get "$config" ".description" "")
  local nodes_key="nodes"
  local nodes_len=$(json_array_len "$config" ".nodes")
  if [ "$nodes_len" -eq 0 ]; then
    nodes_key="stages"
    nodes_len=$(json_array_len "$config" ".stages")
  fi
  local plan_nodes_len
  plan_nodes_len=$(echo "$plan_json" | jq -r '.nodes | length' 2>/dev/null || echo "0")
  if [[ "$plan_nodes_len" =~ ^[0-9]+$ ]] && [ "$plan_nodes_len" -gt 0 ]; then
    nodes_len="$plan_nodes_len"
  fi

  echo "## Configuration"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| name | $name |"
  echo "| description | $description |"
  echo "| nodes | $nodes_len |"
  echo ""

  echo "## Nodes"
  echo ""
  for ((i=0; i<nodes_len; i++)); do
    local node=$(echo "$config" | jq -r ".${nodes_key}[$i]")
    local node_id=$(echo "$node" | jq -r ".id // .name")
    local node_pipeline=$(echo "$node" | jq -r ".pipeline // empty")
    local node_parallel=$(echo "$node" | jq -e '.parallel' 2>/dev/null || true)
    local stage_loop=$(echo "$node" | jq -r ".stage // empty")
    [ -z "$stage_loop" ] && stage_loop=$(echo "$node" | jq -r ".loop // empty")

    # Get termination info from compiled plan (which has overrides merged)
    local compiled_node=$(echo "$plan_json" | jq -r ".nodes[$i] // {}")
    local node_kind=$(echo "$compiled_node" | jq -r '.kind // empty')
    local node_ref=$(echo "$compiled_node" | jq -r '.ref // empty')
    if [ -z "$node_kind" ] || [ "$node_kind" = "null" ]; then
      if [ -n "$node_pipeline" ]; then
        node_kind="pipeline"
      elif [ -n "$node_parallel" ] && [ "$node_parallel" != "null" ]; then
        node_kind="parallel"
      else
        node_kind="stage"
      fi
    fi

    echo "### Node $((i+1)): $node_id"
    echo ""
    case "$node_kind" in
      stage)
        local term_type=$(echo "$compiled_node" | jq -r '.termination.type // empty')
        local term_max=$(echo "$compiled_node" | jq -r '.termination.max // empty')
        if [ -n "$stage_loop" ]; then
          echo "- **Stage:** $stage_loop"
          echo "- **Max iterations:** ${term_max:-1}"
          if [ -n "$term_type" ]; then
            echo "- **Termination:** $term_type"
          fi
        else
          echo "- **Inline prompt node**"
          echo "- **Runs:** ${term_max:-1}"
        fi
        ;;
      pipeline)
        local node_runs=$(echo "$node" | jq -r '.runs // 1')
        if [ -z "$node_pipeline" ]; then
          node_pipeline="$node_ref"
        fi
        echo "- **Pipeline:** $node_pipeline"
        echo "- **Runs:** ${node_runs:-1}"
        ;;
      parallel)
        local providers
        providers=$(echo "$node" | jq -r '.parallel.providers // [] | join(", ")')
        echo "- **Parallel block**"
        [ -n "$providers" ] && [ "$providers" != "null" ] && echo "- **Providers:** $providers"
        ;;
      *)
        echo "- **Node kind:** $node_kind"
        ;;
    esac
    echo ""
  done

  echo "## Output Directory"
  echo ""
  echo "\`.claude/pipeline-runs/${session}/\`"
  echo ""
  echo "Each node creates:"
  echo "- \`stage-{N}-{name}/\` - Node outputs"
  echo "- \`stage-{N}-{name}/progress.md\` - Node progress file"
}
