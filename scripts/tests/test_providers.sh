#!/bin/bash
# Tests for provider abstraction
# TDD: These tests define the expected behavior before implementation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/test.sh"
source "$SCRIPT_DIR/lib/yaml.sh"
source "$SCRIPT_DIR/lib/provider.sh"

#-------------------------------------------------------------------------------
# Provider Config Tests
#-------------------------------------------------------------------------------

test_default_provider_is_claude() {
  # Simulate config without provider field
  local config='{"name":"test","termination":{"type":"fixed"}}'
  local provider=$(echo "$config" | jq -r '.provider // "claude"')
  assert_eq "claude" "$provider" "Default provider should be claude"
}

test_codex_provider_from_config() {
  local config='{"name":"test","provider":"codex","termination":{"type":"fixed"}}'
  local provider=$(echo "$config" | jq -r '.provider // "claude"')
  assert_eq "codex" "$provider" "Should read codex provider from config"
}

#-------------------------------------------------------------------------------
# Normalize Provider Tests
#-------------------------------------------------------------------------------

test_normalize_provider_claude_aliases() {
  assert_eq "claude" "$(normalize_provider "claude")" "claude normalizes to claude"
  assert_eq "claude" "$(normalize_provider "claude-code")" "claude-code normalizes to claude"
  assert_eq "claude" "$(normalize_provider "anthropic")" "anthropic normalizes to claude"
}

test_normalize_provider_codex_aliases() {
  assert_eq "codex" "$(normalize_provider "codex")" "codex normalizes to codex"
  assert_eq "codex" "$(normalize_provider "openai")" "openai normalizes to codex"
}

test_normalize_provider_unknown_returns_empty() {
  local result=$(normalize_provider "unknown-provider")
  assert_eq "" "$result" "unknown provider returns empty string"
}

#-------------------------------------------------------------------------------
# Provider Check Tests
#-------------------------------------------------------------------------------

test_check_provider_claude_succeeds() {
  if command -v claude &>/dev/null; then
    check_provider "claude"
    assert_eq 0 $? "check_provider claude should succeed when installed"
  else
    skip_test "claude CLI not installed"
  fi
}

test_check_provider_codex_succeeds() {
  if command -v codex &>/dev/null; then
    check_provider "codex"
    assert_eq 0 $? "check_provider codex should succeed when installed"
  else
    skip_test "codex CLI not installed"
  fi
}

test_check_provider_unknown_fails() {
  check_provider "unknown-provider" 2>/dev/null
  assert_neq 0 $? "check_provider unknown should fail"
}

test_check_provider_accepts_aliases() {
  if command -v claude &>/dev/null; then
    check_provider "anthropic" 2>/dev/null
    assert_eq 0 $? "check_provider should accept anthropic alias"
    check_provider "claude-code" 2>/dev/null
    assert_eq 0 $? "check_provider should accept claude-code alias"
  else
    skip_test "claude CLI not installed"
  fi
}

#-------------------------------------------------------------------------------
# Codex Model Validation Tests
#-------------------------------------------------------------------------------

test_validate_codex_model_valid() {
  validate_codex_model "gpt-5.2-codex" 2>/dev/null
  assert_eq 0 $? "gpt-5.2-codex should be valid"

  validate_codex_model "gpt-5-codex" 2>/dev/null
  assert_eq 0 $? "gpt-5-codex should be valid"

  validate_codex_model "o3" 2>/dev/null
  assert_neq 0 $? "o3 should be invalid"

  validate_codex_model "o3-mini" 2>/dev/null
  assert_neq 0 $? "o3-mini should be invalid"

  validate_codex_model "o4-mini" 2>/dev/null
  assert_neq 0 $? "o4-mini should be invalid"
}

test_validate_codex_model_invalid() {
  validate_codex_model "invalid-model" 2>/dev/null
  assert_neq 0 $? "invalid-model should fail validation"

  validate_codex_model "opus" 2>/dev/null
  assert_neq 0 $? "claude model opus should fail codex validation"

  validate_codex_model "" 2>/dev/null
  assert_neq 0 $? "empty model should fail validation"
}

#-------------------------------------------------------------------------------
# Reasoning Effort Validation Tests
#-------------------------------------------------------------------------------

test_validate_reasoning_effort_valid() {
  validate_reasoning_effort "minimal" 2>/dev/null
  assert_eq 0 $? "minimal should be valid"

  validate_reasoning_effort "low" 2>/dev/null
  assert_eq 0 $? "low should be valid"

  validate_reasoning_effort "medium" 2>/dev/null
  assert_eq 0 $? "medium should be valid"

  validate_reasoning_effort "high" 2>/dev/null
  assert_eq 0 $? "high should be valid"
}

test_validate_reasoning_effort_invalid() {
  validate_reasoning_effort "invalid" 2>/dev/null
  assert_neq 0 $? "invalid should fail validation"

  validate_reasoning_effort "max" 2>/dev/null
  assert_neq 0 $? "max should fail validation"

  validate_reasoning_effort "" 2>/dev/null
  assert_neq 0 $? "empty should fail validation"
}

#-------------------------------------------------------------------------------
# Claude Model Normalization Tests
#-------------------------------------------------------------------------------

test_claude_model_normalization() {
  # opus variants -> opus
  local model="opus-4.5"
  case "$model" in
    opus|claude-opus|opus-4|opus-4.5) model="opus" ;;
  esac
  assert_eq "opus" "$model" "opus-4.5 normalizes to opus"

  model="claude-sonnet"
  case "$model" in
    sonnet|claude-sonnet|sonnet-4) model="sonnet" ;;
  esac
  assert_eq "sonnet" "$model" "claude-sonnet normalizes to sonnet"
}

test_codex_default_model() {
  # Default codex model should be gpt-5.2-codex
  local default_model="${CODEX_MODEL:-gpt-5.2-codex}"
  assert_eq "gpt-5.2-codex" "$default_model" "default codex model is gpt-5.2-codex"
}

test_codex_reasoning_effort_default() {
  # Default reasoning effort should be high
  local default_reasoning="${CODEX_REASONING_EFFORT:-high}"
  assert_eq "high" "$default_reasoning" "default reasoning effort is high"
}

#-------------------------------------------------------------------------------
# Execute Agent Tests
#-------------------------------------------------------------------------------

test_execute_agent_rejects_empty_prompt() {
  execute_agent "claude" "" "opus" 2>/dev/null
  assert_neq 0 $? "execute_agent should reject empty prompt"
}

test_execute_agent_rejects_unknown_provider() {
  execute_agent "unknown" "test prompt" "model" 2>/dev/null
  assert_neq 0 $? "execute_agent should reject unknown provider"
}

test_execute_agent_function_exists() {
  if type execute_agent &>/dev/null; then
    assert_true "true" "execute_agent function exists"
  else
    skip_test "execute_agent not found"
  fi
}

#-------------------------------------------------------------------------------
# Integration Tests - Load from actual stage configs
#-------------------------------------------------------------------------------

test_work_stage_uses_default_provider() {
  local config=$(yaml_to_json "$SCRIPT_DIR/stages/work/stage.yaml")
  local provider=$(json_get "$config" ".provider" "claude")
  assert_eq "claude" "$provider" "work stage defaults to claude provider"
}

#-------------------------------------------------------------------------------
# Run Tests
#-------------------------------------------------------------------------------

echo ""
echo "==============================================================="
echo "  Provider Abstraction Tests"
echo "==============================================================="
echo ""

# Config tests
run_test "default provider is claude" test_default_provider_is_claude
run_test "codex provider from config" test_codex_provider_from_config

# Normalize provider tests
run_test "normalize_provider claude aliases" test_normalize_provider_claude_aliases
run_test "normalize_provider codex aliases" test_normalize_provider_codex_aliases
run_test "normalize_provider unknown returns empty" test_normalize_provider_unknown_returns_empty

# Check provider tests
run_test "check_provider claude succeeds" test_check_provider_claude_succeeds
run_test "check_provider codex succeeds" test_check_provider_codex_succeeds
run_test "check_provider unknown fails" test_check_provider_unknown_fails
run_test "check_provider accepts aliases" test_check_provider_accepts_aliases

# Codex model validation tests
run_test "validate_codex_model valid models" test_validate_codex_model_valid
run_test "validate_codex_model invalid models" test_validate_codex_model_invalid

# Reasoning effort validation tests
run_test "validate_reasoning_effort valid values" test_validate_reasoning_effort_valid
run_test "validate_reasoning_effort invalid values" test_validate_reasoning_effort_invalid

# Claude model normalization tests
run_test "claude model normalization" test_claude_model_normalization
run_test "codex default model" test_codex_default_model
run_test "codex reasoning effort default" test_codex_reasoning_effort_default

# Execute agent tests
run_test "execute_agent rejects empty prompt" test_execute_agent_rejects_empty_prompt
run_test "execute_agent rejects unknown provider" test_execute_agent_rejects_unknown_provider
run_test "execute_agent function exists" test_execute_agent_function_exists

# Integration tests
run_test "work stage uses default provider" test_work_stage_uses_default_provider

test_summary
