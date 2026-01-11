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

# Known template variables
KNOWN_VARS="SESSION SESSION_NAME ITERATION INDEX PERSPECTIVE OUTPUT PROGRESS PROGRESS_FILE INPUTS"

# Validate a loop configuration
# Usage: validate_loop "loop-name" [--quiet]
# Returns: 0 if valid, 1 if errors found
validate_loop() {
  local name=$1
  local quiet=${2:-""}
  local loops_dir="${VALIDATE_SCRIPT_DIR}/../loops"
  local dir="$loops_dir/$name"
  local errors=()
  local warnings=()

  # L001: Directory exists
  if [ ! -d "$dir" ]; then
    errors+=("Loop directory not found: $dir")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L002: loop.yaml exists
  local config_file="$dir/loop.yaml"
  if [ ! -f "$config_file" ]; then
    errors+=("Missing loop.yaml")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L003: YAML parses correctly
  local config
  config=$(yaml_to_json "$config_file" 2>&1)
  if [ $? -ne 0 ] || [ -z "$config" ] || [ "$config" = "{}" ]; then
    errors+=("Invalid YAML syntax in loop.yaml")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # L004: name field present
  local loop_name=$(json_get "$config" ".name" "")
  if [ -z "$loop_name" ]; then
    errors+=("Missing 'name' field in loop.yaml")
  fi

  # L005: name matches directory (warning)
  if [ -n "$loop_name" ] && [ "$loop_name" != "$name" ]; then
    warnings+=("Loop name '$loop_name' doesn't match directory name '$name'")
  fi

  # L006: completion field present
  local completion=$(json_get "$config" ".completion" "")
  if [ -z "$completion" ]; then
    errors+=("Missing 'completion' field in loop.yaml")
  fi

  # L007: completion strategy exists
  if [ -n "$completion" ]; then
    local completion_file="$VALIDATE_SCRIPT_DIR/completions/${completion}.sh"
    if [ ! -f "$completion_file" ]; then
      errors+=("Unknown completion strategy: $completion (file not found: $completion_file)")
    fi
  fi

  # L008: prompt.md exists
  local prompt_file=$(json_get "$config" ".prompt" "prompt.md")
  if [ ! -f "$dir/$prompt_file" ]; then
    errors+=("Missing prompt file: $prompt_file")
  fi

  # L009: Plateau loops need output_parse with PLATEAU
  if [ "$completion" = "plateau" ]; then
    local output_parse=$(json_get "$config" ".output_parse" "")
    if [ -z "$output_parse" ]; then
      errors+=("Plateau loops require 'output_parse' field")
    elif [[ "$output_parse" != *"PLATEAU"* ]]; then
      errors+=("Plateau loops require 'plateau:PLATEAU' in output_parse")
    fi
  fi

  # L010: Plateau loops should have min_iterations >= 2 (warning)
  if [ "$completion" = "plateau" ]; then
    local min_iter=$(json_get "$config" ".min_iterations" "1")
    if [ "$min_iter" -lt 2 ]; then
      warnings+=("Plateau loops should have min_iterations >= 2 (current: $min_iter)")
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

# Validate a pipeline configuration
# Usage: validate_pipeline "pipeline-name" [--quiet]
# Returns: 0 if valid, 1 if errors found
validate_pipeline() {
  local name=$1
  local quiet=${2:-""}
  local pipelines_dir="${VALIDATE_SCRIPT_DIR}/../pipelines"
  local file="$pipelines_dir/${name}.yaml"
  local errors=()
  local warnings=()

  # P001: Pipeline file exists
  if [ ! -f "$file" ]; then
    # Try without .yaml extension
    if [ ! -f "$pipelines_dir/$name" ]; then
      errors+=("Pipeline file not found: $file")
      [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
      return 1
    fi
    file="$pipelines_dir/$name"
  fi

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

  # P004: stages array present
  local stages_len=$(json_array_len "$config" ".stages")
  if [ "$stages_len" -eq 0 ]; then
    errors+=("Missing or empty 'stages' array")
    [ -z "$quiet" ] && print_result "FAIL" "$name" "${errors[@]}"
    return 1
  fi

  # Collect stage names for reference validation
  local stage_names=()

  # Validate each stage
  for ((i=0; i<stages_len; i++)); do
    local stage=$(echo "$config" | jq -r ".stages[$i]")
    local stage_name=$(echo "$stage" | jq -r ".name // empty")

    # P005: Each stage has name
    if [ -z "$stage_name" ]; then
      errors+=("Stage $i: missing 'name' field")
      continue
    fi

    # P006: Stage names are unique
    if [[ " ${stage_names[*]} " =~ " $stage_name " ]]; then
      errors+=("Duplicate stage name: $stage_name")
    fi
    stage_names+=("$stage_name")

    # P007: Each stage has loop or prompt
    local stage_loop=$(echo "$stage" | jq -r ".loop // empty")
    local stage_prompt=$(echo "$stage" | jq -r ".prompt // empty")
    if [ -z "$stage_loop" ] && [ -z "$stage_prompt" ]; then
      errors+=("Stage '$stage_name': needs 'loop' or 'prompt' field")
    fi

    # P008: Referenced loops exist
    if [ -n "$stage_loop" ]; then
      local loop_dir="${VALIDATE_SCRIPT_DIR}/../loops/$stage_loop"
      if [ ! -d "$loop_dir" ]; then
        errors+=("Stage '$stage_name': references unknown loop '$stage_loop'")
      fi
    fi

    # P011: Each stage should have runs field (warning)
    local stage_runs=$(echo "$stage" | jq -r ".runs // empty")
    if [ -z "$stage_runs" ]; then
      warnings+=("Stage '$stage_name': missing 'runs' field (will use default)")
    fi
  done

  # P009: Check INPUTS references (need all stages collected first)
  for ((i=0; i<stages_len; i++)); do
    local stage=$(echo "$config" | jq -r ".stages[$i]")
    local stage_name=$(echo "$stage" | jq -r ".name // empty")
    local stage_prompt=$(echo "$stage" | jq -r ".prompt // empty")

    # Check for ${INPUTS.stage-name} references
    if [ -n "$stage_prompt" ]; then
      local refs=$(echo "$stage_prompt" | grep -oE '\$\{INPUTS\.[a-zA-Z0-9_-]+\}' | sed 's/\${INPUTS\.//g; s/}//g')
      for ref in $refs; do
        if [[ ! " ${stage_names[*]} " =~ " $ref " ]]; then
          errors+=("Stage '$stage_name': references unknown stage '\${INPUTS.$ref}'")
        fi
      done
    fi

    # P010: First stage shouldn't use INPUTS (warning)
    if [ $i -eq 0 ] && [ -n "$stage_prompt" ]; then
      if [[ "$stage_prompt" == *'${INPUTS'* ]]; then
        warnings+=("Stage '$stage_name': first stage uses \${INPUTS} which will be empty")
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
  local status=$1
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

  if [ "$status" = "PASS" ]; then
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
      validate_pipeline "$target_name"
      return $?
    fi
  fi

  # Validate all loops
  echo "Validating loops..."
  echo ""
  local loops_dir="${VALIDATE_SCRIPT_DIR}/../loops"
  for dir in "$loops_dir"/*/; do
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
# Usage: dry_run_loop "loop-name" "session-name"
dry_run_loop() {
  local name=$1
  local session=${2:-"preview"}
  local loops_dir="${VALIDATE_SCRIPT_DIR}/../loops"
  local dir="$loops_dir/$name"

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
  local config=$(yaml_to_json "$dir/loop.yaml")
  local completion=$(json_get "$config" ".completion" "")
  local delay=$(json_get "$config" ".delay" "3")
  local min_iter=$(json_get "$config" ".min_iterations" "1")
  local output_parse=$(json_get "$config" ".output_parse" "")
  local check_before=$(json_get "$config" ".check_before" "false")
  local description=$(json_get "$config" ".description" "")
  local prompt_file=$(json_get "$config" ".prompt" "prompt.md")

  echo "## Configuration"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| name | $name |"
  echo "| description | $description |"
  echo "| completion | $completion |"
  [ -n "$output_parse" ] && echo "| output_parse | $output_parse |"
  echo "| delay | ${delay}s |"
  [ "$completion" = "plateau" ] && echo "| min_iterations | $min_iter |"
  [ "$check_before" = "true" ] && echo "| check_before | true |"
  echo ""

  echo "## Files"
  echo ""
  echo "| Purpose | Path |"
  echo "|---------|------|"
  echo "| State file | .claude/state.json |"
  echo "| Progress file | .claude/loop-progress/progress-${session}.txt |"
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
  "progress": ".claude/loop-progress/progress-${session}.txt"
}
EOF
)
  load_and_resolve_prompt "$dir/$prompt_file" "$vars_json"
  echo '```'
  echo ""

  echo "## Completion Strategy"
  echo ""
  echo "**Strategy:** $completion"
  echo ""
  case $completion in
    beads-empty)
      echo "The loop will stop when:"
      echo "- \`bd ready --label=loop/${session}\` returns 0 results"
      ;;
    plateau)
      echo "The loop will stop when:"
      echo "- 2 consecutive iterations output \`PLATEAU: true\`"
      echo "- Minimum iterations before checking: $min_iter"
      ;;
    fixed-n)
      echo "The loop will stop when:"
      echo "- N iterations have completed (N specified at runtime)"
      ;;
    all-items)
      echo "The loop will stop when:"
      echo "- All items in the input list have been processed"
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

  # Load config
  local config=$(yaml_to_json "$file")
  local description=$(json_get "$config" ".description" "")
  local stages_len=$(json_array_len "$config" ".stages")

  echo "## Configuration"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| name | $name |"
  echo "| description | $description |"
  echo "| stages | $stages_len |"
  echo ""

  echo "## Stages"
  echo ""
  for ((i=0; i<stages_len; i++)); do
    local stage=$(echo "$config" | jq -r ".stages[$i]")
    local stage_name=$(echo "$stage" | jq -r ".name")
    local stage_loop=$(echo "$stage" | jq -r ".loop // empty")
    local stage_runs=$(echo "$stage" | jq -r ".runs // 1")

    echo "### Stage $((i+1)): $stage_name"
    echo ""
    if [ -n "$stage_loop" ]; then
      echo "- **Loop:** $stage_loop"
      echo "- **Max iterations:** $stage_runs"

      # Get loop's completion strategy
      local loop_config=$(yaml_to_json "${VALIDATE_SCRIPT_DIR}/../loops/$stage_loop/loop.yaml" 2>/dev/null)
      local loop_completion=$(json_get "$loop_config" ".completion" "unknown")
      echo "- **Completion:** $loop_completion"
    else
      echo "- **Inline prompt stage**"
      echo "- **Runs:** $stage_runs"
    fi
    echo ""
  done

  echo "## Output Directory"
  echo ""
  echo "\`.claude/pipeline-runs/${session}/\`"
  echo ""
  echo "Each stage creates:"
  echo "- \`stage-{N}-{name}/\` - Stage outputs"
  echo "- \`stage-{N}-{name}/progress.md\` - Stage progress file"
}
