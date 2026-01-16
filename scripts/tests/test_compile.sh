#!/bin/bash
# Tests for plan compilation (scripts/lib/compile.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/compile.sh"

restore_compile_env() {
  local prev_root=$1
  local prev_stages=$2
  local prev_pipelines=$3
  local prev_timestamp=$4
  local prev_created_at=$5

  if [ -n "$prev_root" ]; then
    export PROJECT_ROOT="$prev_root"
  else
    unset PROJECT_ROOT
  fi

  if [ -n "$prev_stages" ]; then
    export STAGES_DIR="$prev_stages"
  else
    unset STAGES_DIR
  fi

  if [ -n "$prev_pipelines" ]; then
    export PIPELINES_DIR="$prev_pipelines"
  else
    unset PIPELINES_DIR
  fi

  if [ -n "$prev_timestamp" ]; then
    export COMPILE_TIMESTAMP="$prev_timestamp"
  else
    unset COMPILE_TIMESTAMP
  fi

  if [ -n "$prev_created_at" ]; then
    export SESSION_CREATED_AT="$prev_created_at"
  else
    unset SESSION_CREATED_AT
  fi
}

set_compile_env() {
  local root=$1

  export PROJECT_ROOT="$root"
  export STAGES_DIR="$root/scripts/stages"
  export PIPELINES_DIR="$root/scripts/pipelines"
  export COMPILE_TIMESTAMP="2026-01-14T00:00:00Z"
  export SESSION_CREATED_AT="2026-01-13T00:00:00Z"
}

set_compile_fixture_env() {
  local root=$1

  export PROJECT_ROOT="$root"
  export STAGES_DIR="$root/scripts/tests/fixtures/stages"
  export PIPELINES_DIR="$root/scripts/tests/fixtures/pipelines"
  export COMPILE_TIMESTAMP="2026-01-14T00:00:00Z"
  export SESSION_CREATED_AT="2026-01-13T00:00:00Z"
}

#-------------------------------------------------------------------------------
# Compile Pipeline Tests
#-------------------------------------------------------------------------------

test_compile_merges_termination_and_defaults() {
  local tmp
  tmp=$(create_test_dir "compile-merge")
  local prev_root=${PROJECT_ROOT:-}
  local prev_stages=${STAGES_DIR:-}
  local prev_pipelines=${PIPELINES_DIR:-}
  local prev_timestamp=${COMPILE_TIMESTAMP:-}
  local prev_created_at=${SESSION_CREATED_AT:-}

  set_compile_env "$tmp"

  mkdir -p "$STAGES_DIR/alpha"
  cat > "$STAGES_DIR/alpha/stage.yaml" << 'EOF'
name: alpha
description: Alpha stage
termination:
  type: judgment
  min_iterations: 2
  consensus: 3
prompt: prompt.md
EOF

  cat > "$STAGES_DIR/alpha/prompt.md" << 'EOF'
Alpha prompt
EOF

  mkdir -p "$PIPELINES_DIR"
  local pipeline_file="$PIPELINES_DIR/compile-alpha.yaml"
  cat > "$pipeline_file" << 'EOF'
name: compile-alpha
description: pipeline for compile tests
defaults:
  provider: openai
stages:
  - name: first
    stage: alpha
    runs: 5
    termination:
      min_iterations: 4
EOF

  local plan_file="$tmp/plan.json"
  compile_pipeline_file "$pipeline_file" "$plan_file" "session-alpha"
  local exit_code=$?

  assert_eq "0" "$exit_code" "compile_pipeline_file succeeds"
  assert_file_exists "$plan_file" "plan.json written"

  local term_type
  term_type=$(jq -r '.nodes[0].termination.type' "$plan_file")
  local term_min
  term_min=$(jq -r '.nodes[0].termination.min_iterations' "$plan_file")
  local term_consensus
  term_consensus=$(jq -r '.nodes[0].termination.consensus' "$plan_file")
  local term_max
  term_max=$(jq -r '.nodes[0].termination.max' "$plan_file")
  local prompt_path
  prompt_path=$(jq -r '.nodes[0].prompt_path' "$plan_file")
  local provider
  provider=$(jq -r '.nodes[0].provider.type' "$plan_file")
  local model
  model=$(jq -r '.nodes[0].provider.model' "$plan_file")
  local source_path
  source_path=$(jq -r '.source.path' "$plan_file")
  local compiled_at
  compiled_at=$(jq -r '.compiled_at' "$plan_file")
  local session_created_at
  session_created_at=$(jq -r '.session.created_at' "$plan_file")
  local sha_len
  sha_len=$(jq -r '.source.sha256 | length' "$plan_file")

  assert_eq "judgment" "$term_type" "termination type from stage config"
  assert_eq "4" "$term_min" "termination override applied"
  assert_eq "3" "$term_consensus" "termination consensus preserved"
  assert_eq "5" "$term_max" "runs mapped to termination max"
  assert_eq "scripts/stages/alpha/prompt.md" "$prompt_path" "prompt path resolved relative to project root"
  assert_eq "codex" "$provider" "provider normalized from defaults"
  assert_eq "gpt-5.2-codex" "$model" "model defaulted from provider"
  assert_eq "scripts/pipelines/compile-alpha.yaml" "$source_path" "source path stored relative to project root"
  assert_eq "2026-01-14T00:00:00Z" "$compiled_at" "compile timestamp uses COMPILE_TIMESTAMP"
  assert_eq "2026-01-13T00:00:00Z" "$session_created_at" "session created at uses env override"
  assert_eq "64" "$sha_len" "source sha256 length"

  cleanup_test_dir "$tmp"
  restore_compile_env "$prev_root" "$prev_stages" "$prev_pipelines" "$prev_timestamp" "$prev_created_at"
}

test_compile_inline_prompt_infers_dependencies() {
  local tmp
  tmp=$(create_test_dir "compile-inline")
  local prev_root=${PROJECT_ROOT:-}
  local prev_stages=${STAGES_DIR:-}
  local prev_pipelines=${PIPELINES_DIR:-}
  local prev_timestamp=${COMPILE_TIMESTAMP:-}
  local prev_created_at=${SESSION_CREATED_AT:-}

  set_compile_env "$tmp"

  mkdir -p "$PIPELINES_DIR"
  local pipeline_file="$PIPELINES_DIR/compile-inline.yaml"
  cat > "$pipeline_file" << 'EOF'
name: compile-inline
tmux: true
stages:
  - name: queue-stage
    prompt: Inline prompt text.
    runs: 2
    termination:
      type: queue
EOF

  local plan_file="$tmp/plan.json"
  compile_pipeline_file "$pipeline_file" "$plan_file" "session-inline"
  local exit_code=$?

  assert_eq "0" "$exit_code" "compile_pipeline_file succeeds with inline prompt"
  assert_file_exists "$plan_file" "plan.json written"

  local prompt_inline
  prompt_inline=$(jq -r '.nodes[0].prompt' "$plan_file")
  local term_type
  term_type=$(jq -r '.nodes[0].termination.type' "$plan_file")
  local term_max
  term_max=$(jq -r '.nodes[0].termination.max' "$plan_file")
  local deps_bd
  deps_bd=$(jq -r '.dependencies.bd' "$plan_file")
  local deps_tmux
  deps_tmux=$(jq -r '.dependencies.tmux' "$plan_file")

  assert_eq "Inline prompt text." "$prompt_inline" "inline prompt stored in plan"
  assert_eq "queue" "$term_type" "termination type preserved"
  assert_eq "2" "$term_max" "runs mapped to termination max"
  assert_eq "true" "$deps_bd" "queue termination requires bd dependency"
  assert_eq "true" "$deps_tmux" "tmux requirement inferred from pipeline"

  cleanup_test_dir "$tmp"
  restore_compile_env "$prev_root" "$prev_stages" "$prev_pipelines" "$prev_timestamp" "$prev_created_at"
}

test_compile_parallel_block_resolves_prompt() {
  local tmp
  tmp=$(create_test_dir "compile-parallel")
  local prev_root=${PROJECT_ROOT:-}
  local prev_stages=${STAGES_DIR:-}
  local prev_pipelines=${PIPELINES_DIR:-}
  local prev_timestamp=${COMPILE_TIMESTAMP:-}
  local prev_created_at=${SESSION_CREATED_AT:-}

  set_compile_env "$tmp"

  mkdir -p "$STAGES_DIR/beta/prompts"
  cat > "$STAGES_DIR/beta/stage.yaml" << 'EOF'
name: beta
description: Beta stage
termination:
  type: fixed
prompt: prompts/custom.md
EOF

  cat > "$STAGES_DIR/beta/prompts/custom.md" << 'EOF'
Beta prompt
EOF

  mkdir -p "$PIPELINES_DIR"
  local pipeline_file="$PIPELINES_DIR/compile-parallel.yaml"
  cat > "$pipeline_file" << 'EOF'
name: compile-parallel
stages:
  - name: group
    description: Parallel block
    parallel:
      providers:
        - claude
        - codex
      failure_mode: stop
      stages:
        - name: left
          stage: beta
          model: gpt-5.1-codex-mini
          runs: 2
EOF

  local plan_file="$tmp/plan.json"
  compile_pipeline_file "$pipeline_file" "$plan_file" "session-parallel"
  local exit_code=$?

  assert_eq "0" "$exit_code" "compile_pipeline_file succeeds with parallel block"
  assert_file_exists "$plan_file" "plan.json written"

  local kind
  kind=$(jq -r '.nodes[0].kind' "$plan_file")
  local provider_count
  provider_count=$(jq -r '.nodes[0].providers | length' "$plan_file")
  local failure_mode
  failure_mode=$(jq -r '.nodes[0].failure_mode' "$plan_file")
  local stage_path
  stage_path=$(jq -r '.nodes[0].stages[0].path' "$plan_file")
  local stage_prompt
  stage_prompt=$(jq -r '.nodes[0].stages[0].prompt_path' "$plan_file")
  local stage_model
  stage_model=$(jq -r '.nodes[0].stages[0].model' "$plan_file")
  local stage_max
  stage_max=$(jq -r '.nodes[0].stages[0].termination.max' "$plan_file")

  assert_eq "parallel" "$kind" "parallel node compiled"
  assert_eq "2" "$provider_count" "parallel providers recorded"
  assert_eq "stop" "$failure_mode" "failure mode preserved"
  assert_eq "0.0" "$stage_path" "parallel stage path recorded"
  assert_eq "scripts/stages/beta/prompts/custom.md" "$stage_prompt" "parallel prompt path resolved"
  assert_eq "gpt-5.1-codex-mini" "$stage_model" "parallel stage model recorded"
  assert_eq "2" "$stage_max" "parallel stage runs mapped to max"

  cleanup_test_dir "$tmp"
  restore_compile_env "$prev_root" "$prev_stages" "$prev_pipelines" "$prev_timestamp" "$prev_created_at"
}

test_compile_fixture_pipeline_matches_expected() {
  local tmp
  tmp=$(create_test_dir "compile-fixture")
  local prev_root=${PROJECT_ROOT:-}
  local prev_stages=${STAGES_DIR:-}
  local prev_pipelines=${PIPELINES_DIR:-}
  local prev_timestamp=${COMPILE_TIMESTAMP:-}
  local prev_created_at=${SESSION_CREATED_AT:-}

  set_compile_fixture_env "$ROOT_DIR"

  local pipeline_file="$PIPELINES_DIR/test-pipeline.yaml"
  local plan_file="$tmp/plan.json"
  compile_pipeline_file "$pipeline_file" "$plan_file" "fixture-session"
  local exit_code=$?

  assert_eq "0" "$exit_code" "compile fixture pipeline succeeds"
  assert_file_exists "$plan_file" "fixture plan.json written"

  local expected_file="$ROOT_DIR/scripts/tests/fixtures/expected/test-pipeline.plan.json"
  local expected_json
  expected_json=$(cat "$expected_file")
  local actual_sha
  actual_sha=$(jq -r '.source.sha256' "$plan_file")
  expected_json=$(echo "$expected_json" | jq --arg sha "$actual_sha" '.source.sha256 = $sha')

  local expected_sorted
  expected_sorted=$(echo "$expected_json" | jq -S '.')
  local actual_sorted
  actual_sorted=$(jq -S '.' "$plan_file")

  assert_eq "$expected_sorted" "$actual_sorted" "fixture plan matches expected output"

  cleanup_test_dir "$tmp"
  restore_compile_env "$prev_root" "$prev_stages" "$prev_pipelines" "$prev_timestamp" "$prev_created_at"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Plan Compilation"
echo "==============================================================="
echo ""

run_test "compile merges termination and defaults" test_compile_merges_termination_and_defaults
run_test "compile inline prompt infers dependencies" test_compile_inline_prompt_infers_dependencies
run_test "compile parallel block resolves prompts" test_compile_parallel_block_resolves_prompt
run_test "compile fixture pipeline matches expected" test_compile_fixture_pipeline_matches_expected

test_summary
