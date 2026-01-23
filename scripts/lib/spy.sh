#!/bin/bash
# Spy Framework for Tracking Function Calls in Tests
#
# Enables tracking which functions are called during test execution.
# Used for contract tests that verify code paths call required functions.
#
# Usage:
#   source "$LIB_DIR/spy.sh"
#   init_spies
#   spy_function "mark_iteration_started"
#   # ... run code that should call the function ...
#   assert_spy_called "mark_iteration_started" "Should track iteration start"
#   reset_spies
#
# Note: Uses file-based logging for bash 3.x compatibility and cross-subshell tracking.

# Spy state - uses temp directory for call logs (bash 3.x compatible)
SPY_LOG_DIR=""
SPY_FUNCTIONS_FILE=""

#-------------------------------------------------------------------------------
# Spy Setup
#-------------------------------------------------------------------------------

# Initialize spy framework with a temp directory for call logs
# Usage: init_spies
init_spies() {
  SPY_LOG_DIR=$(mktemp -d -t "spy-logs.XXXXXX")
  SPY_FUNCTIONS_FILE="$SPY_LOG_DIR/_spied_functions.txt"
  : > "$SPY_FUNCTIONS_FILE"
  export SPY_LOG_DIR SPY_FUNCTIONS_FILE
}

# Wrap a function to track calls
# Usage: spy_function "mark_iteration_started"
spy_function() {
  local fn_name=$1

  # Ensure spy framework is initialized
  if [ -z "$SPY_LOG_DIR" ]; then
    init_spies
  fi

  # Check function exists
  if ! type "$fn_name" 2>/dev/null | head -1 | grep -q "function"; then
    echo "Warning: Cannot spy on undefined function: $fn_name" >&2
    return 1
  fi

  # Save original function to a file
  local original_file="$SPY_LOG_DIR/_original_${fn_name}.sh"
  declare -f "$fn_name" > "$original_file"

  # Record that we're spying on this function
  echo "$fn_name" >> "$SPY_FUNCTIONS_FILE"

  # Create call log file
  local log_file="$SPY_LOG_DIR/${fn_name}.log"
  : > "$log_file"

  # Create wrapper function that logs calls then invokes original
  # We source the original definition with a renamed function, then call it
  eval "
    _spy_original_${fn_name}() {
      # Source original function definition
      source \"$original_file\"
      # Call it
      $fn_name \"\$@\"
    }
    ${fn_name}() {
      # Log call with arguments to file (works across subshells)
      echo \"\$*\" >> \"$log_file\"
      # Call original function via helper
      _spy_original_${fn_name} \"\$@\"
    }
  "
}

#-------------------------------------------------------------------------------
# Spy Queries
#-------------------------------------------------------------------------------

# Get all calls to a spied function (one per line)
# Usage: calls=$(get_spy_calls "mark_iteration_started")
get_spy_calls() {
  local fn_name=$1
  local log_file="$SPY_LOG_DIR/${fn_name}.log"

  if [ -f "$log_file" ]; then
    cat "$log_file"
  fi
}

# Get call count for a spied function
# Usage: count=$(get_spy_call_count "mark_iteration_started")
get_spy_call_count() {
  local fn_name=$1
  local log_file="$SPY_LOG_DIR/${fn_name}.log"

  if [ -f "$log_file" ] && [ -s "$log_file" ]; then
    wc -l < "$log_file" | tr -d ' '
  else
    echo "0"
  fi
}

# Check if a function was called with specific arguments
# Usage: spy_called_with "mark_iteration_started" "/path/to/state.json 1"
spy_called_with() {
  local fn_name=$1
  local expected_args=$2
  local log_file="$SPY_LOG_DIR/${fn_name}.log"

  if [ -f "$log_file" ]; then
    grep -qF "$expected_args" "$log_file"
  else
    return 1
  fi
}

#-------------------------------------------------------------------------------
# Spy Assertions
#-------------------------------------------------------------------------------

# Assert a function was called at least once
# Usage: assert_spy_called "mark_iteration_started" "Should track iteration start"
assert_spy_called() {
  local fn_name=$1
  local message=${2:-"$fn_name should have been called"}
  local count=$(get_spy_call_count "$fn_name")

  if [ "$count" -gt 0 ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message (called $count times)"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected: $fn_name to be called"
    echo "    Actual: never called"
    return 1
  fi
}

# Assert a function was NOT called
# Usage: assert_spy_not_called "some_function" "Should not be invoked"
assert_spy_not_called() {
  local fn_name=$1
  local message=${2:-"$fn_name should not have been called"}
  local count=$(get_spy_call_count "$fn_name")

  if [ "$count" -eq 0 ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected: $fn_name not to be called"
    echo "    Actual: called $count times"
    return 1
  fi
}

# Assert a function was called exactly N times
# Usage: assert_spy_call_count "mark_iteration_started" 3 "Should track 3 iterations"
assert_spy_call_count() {
  local fn_name=$1
  local expected=$2
  local message=${3:-"$fn_name should be called $expected times"}
  local actual=$(get_spy_call_count "$fn_name")

  if [ "$actual" -eq "$expected" ]; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected: $expected calls"
    echo "    Actual: $actual calls"
    if [ -f "$SPY_LOG_DIR/${fn_name}.log" ]; then
      echo "    Call log:"
      head -5 "$SPY_LOG_DIR/${fn_name}.log" | sed 's/^/      /'
      local total=$(wc -l < "$SPY_LOG_DIR/${fn_name}.log" | tr -d ' ')
      [ "$total" -gt 5 ] && echo "      ... and $((total - 5)) more"
    fi
    return 1
  fi
}

# Assert a function was called with specific arguments
# Usage: assert_spy_called_with "mark_iteration_started" "/path 1" "Should start iteration 1"
assert_spy_called_with() {
  local fn_name=$1
  local expected_args=$2
  local message=${3:-"$fn_name should be called with: $expected_args"}

  if spy_called_with "$fn_name" "$expected_args"; then
    ((TESTS_PASSED++))
    echo -e "  ${GREEN}✓${NC} $message"
    return 0
  else
    ((TESTS_FAILED++))
    echo -e "  ${RED}✗${NC} $message"
    echo "    Expected args containing: $expected_args"
    echo "    Actual calls:"
    get_spy_calls "$fn_name" | head -5 | sed 's/^/      /'
    return 1
  fi
}

#-------------------------------------------------------------------------------
# Spy Cleanup
#-------------------------------------------------------------------------------

# Restore original function and clear spy
# Usage: restore_spy "mark_iteration_started"
restore_spy() {
  local fn_name=$1
  local original_file="$SPY_LOG_DIR/_original_${fn_name}.sh"

  if [ -f "$original_file" ]; then
    # Source the original function definition (restores it)
    source "$original_file"
    # Clean up the helper function
    unset -f "_spy_original_${fn_name}" 2>/dev/null
  fi
}

# Reset all spies and clean up
# Usage: reset_spies
reset_spies() {
  # Restore all original functions
  if [ -f "$SPY_FUNCTIONS_FILE" ]; then
    while IFS= read -r fn_name; do
      [ -n "$fn_name" ] && restore_spy "$fn_name"
    done < "$SPY_FUNCTIONS_FILE"
  fi

  # Clean up log directory
  if [ -n "$SPY_LOG_DIR" ] && [ -d "$SPY_LOG_DIR" ]; then
    rm -rf "$SPY_LOG_DIR"
  fi

  SPY_LOG_DIR=""
  SPY_FUNCTIONS_FILE=""
}

# Clear call logs but keep spies active
# Usage: clear_spy_logs
clear_spy_logs() {
  if [ -n "$SPY_LOG_DIR" ] && [ -d "$SPY_LOG_DIR" ]; then
    for log_file in "$SPY_LOG_DIR"/*.log; do
      [ -f "$log_file" ] && : > "$log_file"
    done
  fi
}
