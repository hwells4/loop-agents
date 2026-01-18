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

# Get the timeout command (platform-specific)
# Returns: timeout command name or empty if unavailable
_get_timeout_cmd() {
  if command -v timeout &>/dev/null; then
    echo "timeout"
  elif command -v gtimeout &>/dev/null; then
    echo "gtimeout"
  else
    echo ""
  fi
}

# Check if a status file indicates work completion
# Usage: _status_indicates_completion "$status_file"
# Returns: 0 if work complete (continue/stop), 1 if not ready or error
_status_indicates_completion() {
  local status_file=$1

  [ -f "$status_file" ] || return 1

  # Check if valid JSON
  jq -e '.' "$status_file" &>/dev/null || return 1

  # Check decision field
  local decision
  decision=$(jq -r '.decision // "missing"' "$status_file" 2>/dev/null)

  case "$decision" in
    continue|stop) return 0 ;;  # Work completed successfully
    *) return 1 ;;              # Not ready, error, or invalid
  esac
}

# Watchdog runner for Codex - monitors for completion and kills process when done
# Usage: _run_codex_with_watchdog "$prompt" "$model" "$reasoning" "$output_file" "$timeout" "$status_file"
# Environment:
#   CODEX_POLL_INTERVAL - seconds between checks (default: 15)
#   CODEX_GRACE_PERIOD - seconds to wait after completion before kill (default: 5)
_run_codex_with_watchdog() {
  local prompt=$1
  local model=$2
  local reasoning=$3
  local output_file=$4
  local timeout_seconds=$5
  local status_file=$6
  local poll_interval=${CODEX_POLL_INTERVAL:-15}
  local grace_period=${CODEX_GRACE_PERIOD:-5}

  local temp_output
  temp_output=$(mktemp)
  trap "rm -f '$temp_output'" EXIT

  # Start Codex in background
  printf '%s' "$prompt" | codex exec \
    --dangerously-bypass-approvals-and-sandbox \
    -m "$model" \
    -c "model_reasoning_effort=\"$reasoning\"" \
    >"$temp_output" 2>&1 &
  local codex_pid=$!

  echo "Codex started (PID: $codex_pid), watching for completion..." >&2

  local elapsed=0
  local work_completed=false
  local codex_exited=false
  local codex_exit_code=0

  # Poll until timeout, completion, or process exit
  while [ $elapsed -lt $timeout_seconds ]; do
    # Check if Codex exited on its own
    if ! kill -0 "$codex_pid" 2>/dev/null; then
      wait "$codex_pid" 2>/dev/null
      codex_exit_code=$?
      codex_exited=true
      echo "Codex exited on its own (code: $codex_exit_code)" >&2
      break
    fi

    # Check if status file indicates completion
    if [ -n "$status_file" ] && _status_indicates_completion "$status_file"; then
      work_completed=true
      local decision
      decision=$(jq -r '.decision' "$status_file" 2>/dev/null)
      echo "✓ Work completed (decision: $decision) - terminating Codex in ${grace_period}s..." >&2

      # Brief grace period for any final writes
      sleep "$grace_period"

      # Kill the process tree
      if kill -0 "$codex_pid" 2>/dev/null; then
        kill -TERM "$codex_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$codex_pid" 2>/dev/null || true
        wait "$codex_pid" 2>/dev/null || true
      fi
      break
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # Handle timeout
  if [ $elapsed -ge $timeout_seconds ] && [ "$work_completed" = false ] && [ "$codex_exited" = false ]; then
    echo "Warning: Codex timed out after ${timeout_seconds}s" >&2
    kill -TERM "$codex_pid" 2>/dev/null || true
    sleep 2
    kill -KILL "$codex_pid" 2>/dev/null || true
    wait "$codex_pid" 2>/dev/null || true

    # Copy output before returning
    [ -n "$output_file" ] && cp "$temp_output" "$output_file"
    cat "$temp_output"
    return 124
  fi

  # Copy output
  [ -n "$output_file" ] && cp "$temp_output" "$output_file"
  cat "$temp_output"

  # Determine exit code
  if [ "$work_completed" = true ]; then
    # Work completed - success regardless of how Codex exited
    return 0
  elif [ "$codex_exited" = true ]; then
    # Codex exited on its own - check if work was completed despite exit code
    if [ -n "$status_file" ] && _status_indicates_completion "$status_file"; then
      echo "Notice: Work completed despite exit code $codex_exit_code" >&2
      return 0
    fi
    return $codex_exit_code
  fi

  return 0
}

# Execute Codex with a prompt
# Usage: execute_codex "$prompt" "$model" "$output_file"
# Model: gpt-5.2-codex (default), or model:reasoning like gpt-5.2-codex:xhigh
# Reasoning effort: xhigh, high, medium, low, minimal (default: high)
# Environment:
#   CODEX_TIMEOUT - timeout in seconds (default: 900 = 15 minutes)
#   CODEX_STATUS_FILE - path to status.json for watchdog mode (enables early termination)
#   CODEX_POLL_INTERVAL - seconds between completion checks (default: 2)
#   CODEX_GRACE_PERIOD - seconds after completion before kill (default: 3)
#   CODEX_WATCHDOG - set to "false" to disable watchdog (default: true when status file provided)
execute_codex() {
  local prompt=$1
  local model_arg=${2:-"${CODEX_MODEL:-gpt-5.2-codex}"}
  local output_file=$3
  local timeout_seconds=${CODEX_TIMEOUT:-900}
  local status_file=${CODEX_STATUS_FILE:-""}
  local watchdog_enabled=${CODEX_WATCHDOG:-"true"}

  # Parse model:reasoning format (e.g., gpt-5.2-codex:xhigh)
  local model="${model_arg%%:*}"
  local reasoning="${CODEX_REASONING_EFFORT:-high}"
  if [[ "$model_arg" == *:* ]]; then
    reasoning="${model_arg#*:}"
  fi

  # Validate model
  validate_codex_model "$model" || return 1

  # Validate reasoning effort
  validate_reasoning_effort "$reasoning" || return 1

  # Append exit instruction to prevent follow-up waiting in pipeline mode
  local augmented_prompt="${prompt}

---
IMPORTANT: After completing this task and writing any required output files, EXIT IMMEDIATELY.
Do NOT wait for follow-up. Do NOT ask for confirmation. The pipeline handles iteration control."

  # Use watchdog mode when status file is provided (allows early termination on completion)
  if [ -n "$status_file" ] && [ "$watchdog_enabled" = "true" ]; then
    echo "Using watchdog mode (status_file: $status_file)" >&2
    _run_codex_with_watchdog "$augmented_prompt" "$model" "$reasoning" "$output_file" "$timeout_seconds" "$status_file"
    return $?
  fi

  # Fallback: traditional timeout-based execution
  local timeout_cmd
  timeout_cmd=$(_get_timeout_cmd)

  if [ -z "$timeout_cmd" ]; then
    echo "Warning: timeout/gtimeout not found. Codex will run without timeout protection." >&2
    echo "Install coreutils on macOS: brew install coreutils" >&2
  fi

  # Use pipefail to capture exit code through pipe
  set -o pipefail
  local exit_code

  if [ -n "$timeout_cmd" ]; then
    # Run with timeout wrapper
    if [ -n "$output_file" ]; then
      printf '%s' "$augmented_prompt" | "$timeout_cmd" --signal=TERM --kill-after=30s "$timeout_seconds" \
        codex exec \
          --dangerously-bypass-approvals-and-sandbox \
          -m "$model" \
          -c "model_reasoning_effort=\"$reasoning\"" \
        2>&1 | tee "$output_file"
    else
      printf '%s' "$augmented_prompt" | "$timeout_cmd" --signal=TERM --kill-after=30s "$timeout_seconds" \
        codex exec \
          --dangerously-bypass-approvals-and-sandbox \
          -m "$model" \
          -c "model_reasoning_effort=\"$reasoning\"" \
        2>&1
    fi
    exit_code=$?
  else
    # Run without timeout (fallback when timeout command unavailable)
    if [ -n "$output_file" ]; then
      printf '%s' "$augmented_prompt" | codex exec \
        --dangerously-bypass-approvals-and-sandbox \
        -m "$model" \
        -c "model_reasoning_effort=\"$reasoning\"" \
        2>&1 | tee "$output_file"
    else
      printf '%s' "$augmented_prompt" | codex exec \
        --dangerously-bypass-approvals-and-sandbox \
        -m "$model" \
        -c "model_reasoning_effort=\"$reasoning\"" \
        2>&1
    fi
    exit_code=$?
  fi
  set +o pipefail

  # Handle timeout exit codes
  if [ $exit_code -eq 124 ]; then
    echo "Warning: Codex process timed out after ${timeout_seconds}s (SIGTERM)" >&2
  elif [ $exit_code -eq 137 ]; then
    echo "Warning: Codex process killed after timeout grace period (SIGKILL)" >&2
  fi

  # Final salvage check: if work completed despite bad exit, return success
  if [ $exit_code -ne 0 ] && [ -n "$status_file" ] && _status_indicates_completion "$status_file"; then
    echo "Notice: Work completed despite exit code $exit_code - treating as success" >&2
    return 0
  fi

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

    # Write mock result/status files if paths are provided
    # MOCK_RESULT_FILE / MOCK_STATUS_FILE should be set by the engine before calling execute_agent
    if [ -n "$MOCK_RESULT_FILE" ] && type write_mock_result &>/dev/null; then
      write_mock_result "$MOCK_RESULT_FILE" "$iteration"
    elif [ -n "$MOCK_STATUS_FILE" ] && type write_mock_status &>/dev/null; then
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
