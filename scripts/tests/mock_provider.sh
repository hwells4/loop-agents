#!/bin/bash
# Mock provider for tests.
#
# Usage:
#   MOCK_EXIT_CODE=0 RESULT_PATH=/tmp/result.json \
#     MOCK_OUTPUT_FILE=/tmp/output.md \
#     scripts/tests/mock_provider.sh
#
# Environment:
#   MOCK_EXIT_CODE   Exit code to return (default: 0)
#   MOCK_OUTPUT      Text to print to stdout (default: "Mock provider output")
#   MOCK_OUTPUT_FILE Optional file to write output to
#   RESULT_PATH      Optional path to write a result.json payload
#   STATUS_PATH      Optional path to write a status.json payload
#   MOCK_ITERATION   Optional iteration number to embed in default JSON

set -euo pipefail

# Drain stdin to emulate CLI behavior without hanging.
cat >/dev/null || true

output=${MOCK_OUTPUT:-"Mock provider output"}

if [ -n "${MOCK_OUTPUT_FILE:-}" ]; then
  printf %sn "$output" > "$MOCK_OUTPUT_FILE"
fi

printf %sn "$output"

iteration=${MOCK_ITERATION:-1}

if [ -n "${RESULT_PATH:-}" ]; then
  cat > "$RESULT_PATH" <<EOF_RESULT
{
  "summary": "Mock iteration $iteration",
  "work": {"items_completed": [], "files_touched": []},
  "artifacts": {"outputs": [], "paths": []},
  "signals": {"plateau_suspected": false, "risk": "low", "notes": ""}
}
EOF_RESULT
elif [ -n "${STATUS_PATH:-}" ]; then
  cat > "$STATUS_PATH" <<EOF_STATUS
{
  "decision": "continue",
  "reason": "mock",
  "summary": "Mock iteration $iteration",
  "work": {"items_completed": [], "files_touched": []},
  "errors": []
}
EOF_STATUS
fi

exit "${MOCK_EXIT_CODE:-0}"
