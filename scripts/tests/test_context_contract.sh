#!/bin/bash
# Context contract tests - guards schema stability for context.json manifests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/context.sh"

#-------------------------------------------------------------------------------
# Contract Helpers
#-------------------------------------------------------------------------------

_create_stage_config() {
  cat << 'EOF'
{"id":"work","name":"work","index":0,"loop":"work","max_iterations":25}
EOF
}

#-------------------------------------------------------------------------------
# Contract Tests
#-------------------------------------------------------------------------------

test_context_schema_stable() {
  local test_dir
  test_dir=$(create_test_dir "ctx-contract")
  local stage_config=$(_create_stage_config)

  local context_file
  context_file=$(generate_context "contract-session" "1" "$stage_config" "$test_dir")

  local top_keys
  top_keys=$(jq -r 'keys_unsorted | sort | join(",")' "$context_file")
  assert_eq "commands,inputs,iteration,limits,paths,pipeline,session,stage" \
    "$top_keys" "context.json exposes expected top-level keys"

  local path_keys
  path_keys=$(jq -r '.paths | keys_unsorted | sort | join(",")' "$context_file")
  assert_eq "output,progress,result,session_dir,stage_dir,status" \
    "$path_keys" "paths map retains stable schema"

  local input_keys
  input_keys=$(jq -r '.inputs | keys_unsorted | sort | join(",")' "$context_file")
  assert_eq "from_initial,from_previous_iterations,from_stage" \
    "$input_keys" "inputs object preserves contract keys"

  local limit_keys
  limit_keys=$(jq -r '.limits | keys_unsorted | sort | join(",")' "$context_file")
  assert_eq "max_iterations,remaining_seconds" \
    "$limit_keys" "limits object preserves contract keys"

  cleanup_test_dir "$test_dir"
}

test_from_initial_defaults_to_empty_array() {
  local test_dir
  test_dir=$(create_test_dir "ctx-contract")
  local stage_config=$(_create_stage_config)

  local context_file
  context_file=$(generate_context "contract-session" "1" "$stage_config" "$test_dir")

  local type
  type=$(jq -r '.inputs.from_initial | type' "$context_file")
  assert_eq "array" "$type" "from_initial remains an array when no inputs configured"

  local serialized
  serialized=$(jq -c '.inputs.from_initial' "$context_file")
  assert_eq "[]" "$serialized" "from_initial defaults to empty array"

  cleanup_test_dir "$test_dir"
}

test_from_initial_entries_are_absolute_paths() {
  local test_dir
  test_dir=$(create_test_dir "ctx-contract")
  local stage_config=$(_create_stage_config)
  local canonical_dir
  canonical_dir=$(cd "$test_dir" && pwd)

  # Create a seed plan and simulate resolved initial inputs in plan.json
  local plan_file="$canonical_dir/seed-plan.md"
  echo "# bootstrap" > "$plan_file"
  cat > "$test_dir/plan.json" << EOF
{
  "version": 1,
  "session": {
    "name": "contract-session",
    "inputs": ["$plan_file"]
  },
  "nodes": []
}
EOF

  local context_file
  context_file=$(generate_context "contract-session" "1" "$stage_config" "$test_dir")

  local recorded
  recorded=$(jq -r '.inputs.from_initial[0]' "$context_file")
  assert_eq "$plan_file" "$recorded" "from_initial preserves absolute file paths"

  local is_array
  is_array=$(jq -r '.inputs.from_initial | type' "$context_file")
  assert_eq "array" "$is_array" "from_initial stays array when populated"

  local all_absolute=true
  while IFS= read -r path; do
    [[ "$path" == /* ]] || all_absolute=false
  done < <(jq -r '.inputs.from_initial[]' "$context_file")
  assert_true "$all_absolute" "All from_initial entries are absolute paths"

  cleanup_test_dir "$test_dir"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Context Contract Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

run_test "context schema is stable" test_context_schema_stable
run_test "from_initial defaults to empty array" test_from_initial_defaults_to_empty_array
run_test "from_initial entries are absolute paths" test_from_initial_entries_are_absolute_paths

test_summary
