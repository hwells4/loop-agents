#!/bin/bash
# Provider abstraction for agent execution
# Supports: Claude Code, Codex (OpenAI)

# Normalize provider aliases to canonical name
# Usage: normalize_provider "$provider"
# Returns: canonical provider name (claude, codex) or empty string if unknown
normalize_provider() {
  case "$1" in
    claude|claude-code|anthropic) echo "claude" ;;
    codex|openai) echo "codex" ;;
    *) echo "" ;;
  esac
}

# Get the default model for a provider
# Usage: get_default_model "$provider"
get_default_model() {
  local provider=$(normalize_provider "$1")
  case "$provider" in
    claude) echo "opus" ;;
    codex) echo "gpt-5.2-codex" ;;
    *) echo "opus" ;;  # fallback
  esac
}

# Check if a provider CLI is available
# Usage: check_provider "$provider"
check_provider() {
  local provider=$(normalize_provider "$1")

  case "$provider" in
    claude)
      if ! command -v claude &>/dev/null; then
        echo "Error: Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code" >&2
        return 1
      fi
      ;;
    codex)
      if ! command -v codex &>/dev/null; then
        echo "Error: Codex CLI not found. Install with: npm install -g @openai/codex" >&2
        return 1
      fi
      ;;
    *)
      echo "Error: Unknown provider: $1" >&2
      return 1
      ;;
  esac
  return 0
}

# Validate reasoning effort for Codex
# Usage: validate_reasoning_effort "$effort"
# Values: minimal, low, medium, high, xhigh
validate_reasoning_effort() {
  case "$1" in
    minimal|low|medium|high|xhigh) return 0 ;;
    *)
      echo "Error: Invalid reasoning effort: $1 (valid: minimal, low, medium, high, xhigh)" >&2
      return 1
      ;;
  esac
}

# Validate Codex model
# Usage: validate_codex_model "$model"
validate_codex_model() {
  case "$1" in
    gpt-5.2-codex|gpt-5.1-codex-max|gpt-5.1-codex-mini|gpt-5.1-codex|gpt-5-codex|gpt-5-codex-mini) return 0 ;;
    *)
      echo "Error: Unknown Codex model: $1" >&2
      return 1
      ;;
  esac
}

# Execute Claude with a prompt
# Usage: execute_claude "$prompt" "$model" "$output_file"
execute_claude() {
  local prompt=$1
  local model=${2:-"opus"}
  local output_file=$3

  # Normalize model names
  case "$model" in
    opus|claude-opus|opus-4|opus-4.5) model="opus" ;;
    sonnet|claude-sonnet|sonnet-4) model="sonnet" ;;
    haiku|claude-haiku) model="haiku" ;;
  esac

  # Use pipefail to capture exit code through pipe
  set -o pipefail
  if [ -n "$output_file" ]; then
    printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1 | tee "$output_file"
  else
    printf '%s' "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1
  fi
  local exit_code=$?
  set +o pipefail
  return $exit_code
}

# Execute Codex with a prompt
# Usage: execute_codex "$prompt" "$model" "$output_file"
# Model: gpt-5.2-codex (default), gpt-5-codex, o3, etc.
# Reasoning effort: minimal, low, medium, high (default: high)
# Configure via env vars: CODEX_MODEL, CODEX_REASONING_EFFORT
execute_codex() {
  local prompt=$1
  local model=${2:-"${CODEX_MODEL:-gpt-5.2-codex}"}
  local output_file=$3
  local reasoning=${CODEX_REASONING_EFFORT:-"high"}

  # Validate model
  validate_codex_model "$model" || return 1

  # Validate reasoning effort
  validate_reasoning_effort "$reasoning" || return 1

  # Use pipefail to capture exit code through pipe
  set -o pipefail
  if [ -n "$output_file" ]; then
    codex exec \
      --dangerously-bypass-approvals-and-sandbox \
      -m "$model" \
      -c "model_reasoning_effort=\"$reasoning\"" \
      "$prompt" 2>&1 | tee "$output_file"
  else
    codex exec \
      --dangerously-bypass-approvals-and-sandbox \
      -m "$model" \
      -c "model_reasoning_effort=\"$reasoning\"" \
      "$prompt" 2>&1
  fi
  local exit_code=$?
  set +o pipefail
  return $exit_code
}

# Execute an agent with provider abstraction
# Usage: execute_agent "$provider" "$prompt" "$model" "$output_file"
# Set MOCK_MODE=true to return mock responses instead of calling real agent
execute_agent() {
  local provider=$1
  local prompt=$2
  local model=$3
  local output_file=$4

  # Mock mode for testing - return mock response without calling real agent
  # Requires mock.sh to be sourced first (get_mock_response, write_mock_status)
  if [ "$MOCK_MODE" = true ]; then
    local iteration=${MOCK_ITERATION:-1}
    local response
    if type get_mock_response &>/dev/null; then
      response=$(get_mock_response "$iteration")
    else
      response="Mock response for iteration $iteration"
    fi
    if [ -n "$output_file" ]; then
      echo "$response" > "$output_file"
    fi
    echo "$response"

    # Write mock status file if path is provided
    # MOCK_STATUS_FILE should be set by the engine before calling execute_agent
    if [ -n "$MOCK_STATUS_FILE" ] && type write_mock_status &>/dev/null; then
      write_mock_status "$MOCK_STATUS_FILE" "$iteration"
    fi

    return 0
  fi

  # Validate prompt is not empty
  if [ -z "$prompt" ]; then
    echo "Error: Empty prompt provided to execute_agent" >&2
    return 1
  fi

  # Normalize and dispatch
  local normalized=$(normalize_provider "$provider")
  case "$normalized" in
    claude)
      execute_claude "$prompt" "$model" "$output_file"
      ;;
    codex)
      execute_codex "$prompt" "$model" "$output_file"
      ;;
    *)
      echo "Error: Unknown provider: $provider" >&2
      return 1
      ;;
  esac
}
