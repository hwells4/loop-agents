#!/bin/bash
# Multi-Provider Execution
#
# Abstracts execution across different AI providers:
#   - claude-code: Claude Code CLI
#   - codex: OpenAI Codex CLI (future)
#   - gemini: Google Gemini CLI (future)

# Execute a prompt with specified provider and model
# Returns output to stdout and writes to output_file
execute_prompt() {
  local prompt=$1
  local provider=$2
  local model=$3
  local output_file=$4

  local output=""

  case "$provider" in
    claude-code|claude)
      output=$(execute_claude_code "$prompt" "$model")
      ;;
    codex|openai)
      output=$(execute_codex "$prompt" "$model")
      ;;
    gemini|google)
      output=$(execute_gemini "$prompt" "$model")
      ;;
    *)
      echo "Error: Unknown provider: $provider" >&2
      echo "Supported providers: claude-code, codex, gemini" >&2
      return 1
      ;;
  esac

  # Write to output file if specified
  if [ -n "$output_file" ]; then
    mkdir -p "$(dirname "$output_file")"
    echo "$output" > "$output_file"
  fi

  echo "$output"
}

# Execute via Claude Code CLI
execute_claude_code() {
  local prompt=$1
  local model=${2:-"sonnet"}

  # Map model names to Claude Code format
  case "$model" in
    opus|claude-opus|opus-4)
      model="opus"
      ;;
    sonnet|claude-sonnet|sonnet-4)
      model="sonnet"
      ;;
    haiku|claude-haiku)
      model="haiku"
      ;;
  esac

  # Execute with Claude Code
  echo "$prompt" | claude --model "$model" --dangerously-skip-permissions 2>&1
}

# Execute via Codex CLI (stub - implement when ready)
execute_codex() {
  local prompt=$1
  local model=${2:-"o3"}

  # Check if codex CLI is available
  if ! command -v codex &>/dev/null; then
    echo "Error: Codex CLI not found. Install with: npm install -g @openai/codex" >&2
    return 1
  fi

  # Map model names
  case "$model" in
    o3|o3-mini)
      model="$model"
      ;;
    gpt-4|gpt-4o)
      model="$model"
      ;;
    *)
      model="o3"
      ;;
  esac

  # Execute with Codex
  # Note: Adjust command syntax based on actual Codex CLI interface
  codex --model "$model" "$prompt" 2>&1
}

# Execute via Gemini CLI (stub - implement when ready)
execute_gemini() {
  local prompt=$1
  local model=${2:-"gemini-2.0-flash"}

  # Check if gemini CLI is available
  if ! command -v gemini &>/dev/null; then
    echo "Error: Gemini CLI not found." >&2
    return 1
  fi

  # Map model names
  case "$model" in
    flash|gemini-flash)
      model="gemini-2.0-flash"
      ;;
    pro|gemini-pro)
      model="gemini-2.0-pro"
      ;;
    *)
      model="$model"
      ;;
  esac

  # Execute with Gemini
  # Note: Adjust command syntax based on actual Gemini CLI interface
  gemini --model "$model" "$prompt" 2>&1
}

# Check if a provider is available
check_provider() {
  local provider=$1

  case "$provider" in
    claude-code|claude)
      command -v claude &>/dev/null
      ;;
    codex|openai)
      command -v codex &>/dev/null
      ;;
    gemini|google)
      command -v gemini &>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# List available providers
list_providers() {
  echo "Available providers:"

  if check_provider "claude-code"; then
    echo "  ✓ claude-code (models: opus, sonnet, haiku)"
  else
    echo "  ✗ claude-code (not installed)"
  fi

  if check_provider "codex"; then
    echo "  ✓ codex (models: o3, o3-mini, gpt-4o)"
  else
    echo "  ✗ codex (not installed)"
  fi

  if check_provider "gemini"; then
    echo "  ✓ gemini (models: flash, pro)"
  else
    echo "  ✗ gemini (not installed)"
  fi
}
