#!/bin/bash
# Pipeline History - List all pipeline runs ordered by recency
# Usage: ./pipeline-history.sh [--json] [--limit N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_DIR="${PIPELINE_RUNS_DIR:-$SCRIPT_DIR/../.claude/pipeline-runs}"

# Parse args
JSON_OUTPUT=false
LIMIT=20
while [[ $# -gt 0 ]]; do
  case $1 in
    --json) JSON_OUTPUT=true; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --all) LIMIT=1000; shift ;;
    -h|--help)
      echo "Usage: pipeline-history.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --json     Output as JSON array"
      echo "  --limit N  Show N most recent (default: 20)"
      echo "  --all      Show all runs"
      exit 0
      ;;
    *) shift ;;
  esac
done

# Check if runs dir exists
if [ ! -d "$RUNS_DIR" ]; then
  echo "No pipeline runs found at: $RUNS_DIR" >&2
  exit 0
fi

# Use Python for reliable JSON parsing and sorting
python3 << EOF
import json
import os
from pathlib import Path
from datetime import datetime

runs_dir = Path("$RUNS_DIR")
json_output = $( [ "$JSON_OUTPUT" = "true" ] && echo "True" || echo "False" )
limit = $LIMIT
results = []

for session_dir in runs_dir.iterdir():
    if not session_dir.is_dir():
        continue
    state_file = session_dir / "state.json"
    if state_file.exists():
        try:
            with open(state_file) as f:
                state = json.load(f)
            mtime = state_file.stat().st_mtime

            # Check if actually running (PID alive)
            status = state.get("status", "unknown")
            if status == "running":
                # Could check PID here, but for now mark as stale if old
                age_hours = (datetime.now().timestamp() - mtime) / 3600
                if age_hours > 1:
                    status = "stale"

            results.append({
                "session": session_dir.name,
                "status": status,
                "type": state.get("type", state.get("stage", "unknown")),
                "iteration": state.get("iteration_completed", state.get("iteration", 0)),
                "max_iterations": state.get("max_iterations"),
                "stages_completed": len([s for s in state.get("stages", []) if s.get("status") == "complete"]),
                "stages_total": len(state.get("stages", [])),
                "started_at": state.get("started_at", ""),
                "last_modified": datetime.fromtimestamp(mtime).isoformat(),
                "mtime": mtime
            })
        except Exception as e:
            pass

results.sort(key=lambda x: x["mtime"], reverse=True)
results = results[:limit]

if json_output:
    # Remove internal mtime field
    for r in results:
        del r["mtime"]
    print(json.dumps(results, indent=2))
else:
    print(f"{'Last Modified':<18} {'Session':<22} {'Status':<10} {'Type':<10} {'Progress'}")
    print("-" * 85)
    for r in results:
        mtime_str = datetime.fromisoformat(r["last_modified"]).strftime("%Y-%m-%d %H:%M")
        if r["stages_total"]:
            progress = f"{r['stages_completed']}/{r['stages_total']} stages"
        else:
            progress = f"{r['iteration']}/{r['max_iterations'] or '?'} iter"
        print(f"{mtime_str:<18} {r['session']:<22} {r['status']:<10} {r['type']:<10} {progress}")
EOF
