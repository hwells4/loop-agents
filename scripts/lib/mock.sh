#!/bin/bash
# Mock Execution Mode for Agent Pipelines
#
# Enables testing loop execution without calling Claude API.
# Uses fixture files to provide mock responses.
#
# Usage:
#   source "$LIB_DIR/mock.sh"
#   enable_mock_mode "scripts/stages/work/fixtures"
#   response=$(get_mock_response 1)
#
# Fixture structure:
#   fixtures/
#   ├── default.txt         # Fallback response
#   ├── iteration-1.txt     # Response for iteration 1
#   ├── iteration-2.txt     # Response for iteration 2
#   └── status.json         # Expected status format (for validation)

# Mock mode state
MOCK_MODE=${MOCK_MODE:-false}
MOCK_FIXTURES_DIR=""
MOCK_ITERATION=0
MOCK_DELAY=${MOCK_DELAY:-0}  # Simulated delay between iterations

#-------------------------------------------------------------------------------
# Mock Mode Control
#-------------------------------------------------------------------------------

# Enable mock mode with fixtures directory
# Usage: enable_mock_mode "/path/to/fixtures"
enable_mock_mode() {
  local fixtures_dir=$1

  if [ ! -d "$fixtures_dir" ]; then
    echo "Warning: Fixtures directory not found: $fixtures_dir" >&2
    echo "Creating with default fixture..." >&2
    mkdir -p "$fixtures_dir"
    create_default_fixture "$fixtures_dir"
  fi

  MOCK_MODE=true
  MOCK_FIXTURES_DIR="$fixtures_dir"
  MOCK_ITERATION=0

  export MOCK_MODE MOCK_FIXTURES_DIR
}

# Disable mock mode
disable_mock_mode() {
  MOCK_MODE=false
  MOCK_FIXTURES_DIR=""
  MOCK_ITERATION=0
}

# Check if mock mode is enabled
is_mock_mode() {
  [ "$MOCK_MODE" = true ]
}

#-------------------------------------------------------------------------------
# Mock Response Generation
#-------------------------------------------------------------------------------

# Get mock response for an iteration
# Usage: response=$(get_mock_response 1)
get_mock_response() {
  local iteration=${1:-1}
  MOCK_ITERATION=$iteration

  # Simulate delay if configured
  [ "$MOCK_DELAY" -gt 0 ] && sleep "$MOCK_DELAY"

  # Try iteration-specific fixture first
  local iter_fixture="$MOCK_FIXTURES_DIR/iteration-${iteration}.txt"
  if [ -f "$iter_fixture" ]; then
    cat "$iter_fixture"
    return 0
  fi

  # Fall back to default fixture
  local default_fixture="$MOCK_FIXTURES_DIR/default.txt"
  if [ -f "$default_fixture" ]; then
    cat "$default_fixture"
    return 0
  fi

  # Generate minimal valid response if no fixture exists
  generate_minimal_response
}

# Generate a minimal valid response (fallback)
generate_minimal_response() {
  cat << 'EOF'
Mock response - no fixture found.

Completed mock iteration.

## Status
Written to status.json with decision: continue
EOF
}

# Create a default fixture file
# Usage: create_default_fixture "/path/to/fixtures"
create_default_fixture() {
  local fixtures_dir=$1

  cat > "$fixtures_dir/default.txt" << 'EOF'
# Mock Response

This is a mock response for testing purposes.

## Actions Taken
- Read progress file
- Simulated work
- Updated state

## Status
Written to status.json with decision: continue
EOF
}

#-------------------------------------------------------------------------------
# v3 Status File Support
#-------------------------------------------------------------------------------

# Get mock status.json content for an iteration
# Usage: status_json=$(get_mock_status 1)
get_mock_status() {
  local iteration=${1:-1}

  # Try iteration-specific status
  local iter_status="$MOCK_FIXTURES_DIR/status-${iteration}.json"
  if [ -f "$iter_status" ]; then
    cat "$iter_status"
    return 0
  fi

  # Try fixture directory's status.json template
  local status_template="$MOCK_FIXTURES_DIR/status.json"
  if [ -f "$status_template" ]; then
    cat "$status_template"
    return 0
  fi

  # Generate default continue status
  generate_default_status "continue"
}

# Generate a status.json with given decision
# Usage: generate_default_status "continue|stop|error"
generate_default_status() {
  local decision=${1:-"continue"}
  local reason=""
  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  case "$decision" in
    continue)
      reason="Mock execution - more work simulated"
      ;;
    stop)
      reason="Mock execution - plateau simulated"
      ;;
    error)
      reason="Mock execution - error simulated"
      ;;
  esac

  cat << EOF
{
  "decision": "$decision",
  "reason": "$reason",
  "summary": "Mock iteration $MOCK_ITERATION completed",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "errors": [],
  "timestamp": "$timestamp"
}
EOF
}

# Write mock status to a file
# Usage: write_mock_status "/path/to/status.json" 1
write_mock_status() {
  local status_file=$1
  local iteration=${2:-1}

  get_mock_status "$iteration" > "$status_file"
}

#-------------------------------------------------------------------------------
# Fixture Management
#-------------------------------------------------------------------------------

# List available fixtures for a loop
# Usage: list_fixtures "work"
list_fixtures() {
  local loop_name=$1
  local fixtures_dir="${SCRIPT_DIR:-scripts}/stages/$loop_name/fixtures"

  if [ ! -d "$fixtures_dir" ]; then
    echo "No fixtures directory for loop: $loop_name"
    return 1
  fi

  echo "Fixtures for $loop_name:"
  ls -1 "$fixtures_dir" 2>/dev/null | while read f; do
    echo "  $f"
  done
}

# Create fixture set for a stage type
# Usage: create_fixture_set "work" "beads-empty"
create_fixture_set() {
  local loop_name=$1
  local completion_type=${2:-"plateau"}
  local fixtures_dir="${SCRIPT_DIR:-scripts}/stages/$loop_name/fixtures"

  mkdir -p "$fixtures_dir"

  case "$completion_type" in
    plateau)
      # Create fixtures that simulate plateau after 3 iterations
      create_plateau_fixtures "$fixtures_dir"
      ;;
    beads-empty)
      # Create fixtures for work loop
      create_work_fixtures "$fixtures_dir"
      ;;
    fixed-n)
      # Create generic fixtures
      create_default_fixture "$fixtures_dir"
      ;;
  esac

  echo "Created fixtures in: $fixtures_dir"
}

# Create plateau-style fixtures (for improve-plan, elegance, etc.)
create_plateau_fixtures() {
  local dir=$1

  # Iteration 1: Continue
  cat > "$dir/iteration-1.txt" << 'EOF'
# Iteration 1

## Analysis
Reviewed the plan and found several areas for improvement.

## Changes Made
- Clarified section 3 requirements
- Added missing error handling details
- Fixed inconsistency in naming conventions

## Next Steps
More work needed on security considerations.

## Status
Written to status.json with decision: continue (significant issues to address)
EOF

  # Iteration 2: Suggest stop (first vote)
  cat > "$dir/iteration-2.txt" << 'EOF'
# Iteration 2

## Analysis
Minor improvements made. The plan is now quite solid.

## Changes Made
- Polished wording in introduction
- Added one clarifying example

## Assessment
The plan covers all major requirements and edge cases.

## Status
Written to status.json with decision: stop (only cosmetic improvements remain)
EOF

  # Iteration 3: Confirm stop (consensus reached)
  cat > "$dir/iteration-3.txt" << 'EOF'
# Iteration 3

## Analysis
Confirmed the plan is complete and well-structured.

## Changes Made
- No substantive changes needed

## Assessment
Agreeing with previous assessment - plan is production-ready.

## Status
Written to status.json with decision: stop (confirming - no further improvements)
EOF

  # Default (for iterations beyond 3)
  cat > "$dir/default.txt" << 'EOF'
# Default Mock Response

No changes made - plan appears complete.

## Status
Written to status.json with decision: stop
EOF

  # v3 status templates
  cat > "$dir/status-1.json" << 'EOF'
{
  "decision": "continue",
  "reason": "Found significant issues to address",
  "summary": "Reviewed plan, made improvements to section 3 and error handling",
  "work": {"items_completed": [], "files_touched": ["docs/plan.md"]},
  "errors": []
}
EOF

  cat > "$dir/status-2.json" << 'EOF'
{
  "decision": "stop",
  "reason": "Only cosmetic improvements remain",
  "summary": "Polished wording, plan is ready for implementation",
  "work": {"items_completed": [], "files_touched": ["docs/plan.md"]},
  "errors": []
}
EOF

  cat > "$dir/status-3.json" << 'EOF'
{
  "decision": "stop",
  "reason": "Confirming plateau - no further improvements identified",
  "summary": "Confirmed plan is complete and well-structured",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
EOF
}

# Create work-style fixtures (for beads-empty completion)
create_work_fixtures() {
  local dir=$1

  cat > "$dir/default.txt" << 'EOF'
# Work Iteration

## Progress
Reviewed available beads and selected next task.

## Work Done
- Claimed bead: beads-001
- Implemented feature
- Committed changes
- Closed bead

## Status
Written to status.json with decision: continue (more beads available)
EOF

  # v3 status
  cat > "$dir/status.json" << 'EOF'
{
  "decision": "continue",
  "reason": "Completed one bead, more work available",
  "summary": "Implemented feature from beads-001, committed and closed",
  "work": {
    "items_completed": ["beads-001"],
    "files_touched": ["src/feature.ts"]
  },
  "errors": []
}
EOF
}

#-------------------------------------------------------------------------------
# Recording Mode (Capture Real Responses)
#-------------------------------------------------------------------------------

RECORD_MODE=false
RECORD_DIR=""

# Enable recording mode to capture real Claude responses
enable_record_mode() {
  local loop_name=$1
  local timestamp=$(date +%Y%m%d-%H%M%S)

  RECORD_MODE=true
  RECORD_DIR="${SCRIPT_DIR:-scripts}/stages/$loop_name/fixtures/recorded/$timestamp"
  mkdir -p "$RECORD_DIR"

  echo "Recording to: $RECORD_DIR"
}

# Record a response
# Usage: record_response 1 "$output"
record_response() {
  local iteration=$1
  local output=$2

  if [ "$RECORD_MODE" = true ]; then
    echo "$output" > "$RECORD_DIR/iteration-${iteration}.txt"
  fi
}
