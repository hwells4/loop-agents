#!/bin/bash
# Shared Utilities
# Common helper functions used across multiple libraries.
# Source this file to avoid duplicating these patterns.

#-------------------------------------------------------------------------------
# Integer validation and conversion
#-------------------------------------------------------------------------------

# Check if a value is a non-negative integer
# Usage: utils_is_int "123" && echo "yes"
utils_is_int() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# Return the value if it's an integer, otherwise return fallback
# Usage: val=$(utils_int_or_default "$input" 0)
utils_int_or_default() {
  local value=$1
  local fallback=$2
  if utils_is_int "$value"; then
    echo "$value"
  else
    echo "$fallback"
  fi
}

#-------------------------------------------------------------------------------
# Index formatting
#-------------------------------------------------------------------------------

# Format an integer with leading zeros (3 digits by default)
# Usage: idx=$(utils_format_index 5)    # "005"
# Usage: idx=$(utils_format_index 5 4)  # "0005"
utils_format_index() {
  local idx=$1
  local width=${2:-3}
  printf "%0${width}d" "$idx"
}

#-------------------------------------------------------------------------------
# Atomic file operations
#-------------------------------------------------------------------------------

# Write content atomically (via temp file + mv)
# Usage: utils_write_atomic "/path/to/file" "content"
utils_write_atomic() {
  local path=$1
  local content=$2
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"
  local tmp_file
  tmp_file=$(mktemp)
  printf '%s\n' "$content" > "$tmp_file"
  mv "$tmp_file" "$path"
}

#-------------------------------------------------------------------------------
# JSON helpers
#-------------------------------------------------------------------------------

# Normalize JSON: return {} if input is empty/null/invalid
# Usage: json=$(utils_safe_json "$raw_json")
utils_safe_json() {
  local candidate=$1

  if [ -z "$candidate" ] || [ "$candidate" = "null" ]; then
    echo "{}"
    return 0
  fi

  if ! echo "$candidate" | jq -e . >/dev/null 2>&1; then
    echo "{}"
    return 0
  fi

  echo "$candidate"
}

#-------------------------------------------------------------------------------
# Directory helpers
#-------------------------------------------------------------------------------

# Ensure parent directory exists
# Usage: utils_ensure_parent_dir "/path/to/file"
utils_ensure_parent_dir() {
  local path=$1
  local dir
  dir=$(dirname "$path")
  mkdir -p "$dir"
}
