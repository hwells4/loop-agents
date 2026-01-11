# State Files Reference

Complete reference for state file schemas and operations.

## Session State Files (Unified)

**Location:** `.claude/pipeline-runs/{session}/state.json`

**Purpose:** Track iteration history for any session (loop or pipeline). Created by `engine.sh`. All sessions now use this unified path.

> **Note:** Loops are now "single-stage pipelines" and use the same directory structure as multi-stage pipelines.

### Schema

```json
{
  "session": "myfeature",
  "type": "loop",
  "started_at": "2025-01-10T10:00:00Z",
  "status": "running",
  "iteration": 5,
  "iteration_completed": 4,
  "iteration_started": "2025-01-10T10:05:00Z",
  "current_stage": 0,
  "stages": [],
  "history": [
    {
      "iteration": 1,
      "timestamp": "2025-01-10T10:01:00Z",
      "plateau": false
    },
    {
      "iteration": 2,
      "timestamp": "2025-01-10T10:05:00Z",
      "plateau": true,
      "reasoning": "No significant improvements found"
    }
  ],
  "completed_at": null,
  "completion_reason": null
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Session name |
| `type` | string | `"loop"` or `"pipeline"` |
| `started_at` | ISO8601 | When session started |
| `status` | string | `running`, `complete`, `failed` |
| `iteration` | number | Current iteration (for loops) |
| `iteration_completed` | number | Last fully completed iteration (for crash recovery) |
| `iteration_started` | ISO8601 | When current iteration began (null if not in progress) |
| `current_stage` | number | Current stage index (for pipelines) |
| `stages` | array | Per-stage status (for pipelines) |
| `history` | array | Per-iteration data with parsed output fields |
| `completed_at` | ISO8601 | When finished (if applicable) |
| `completion_reason` | string | Why session stopped (e.g., "beads-empty", "plateau", "max_iterations") |

### Reading Session State

```bash
# Current status
cat .claude/pipeline-runs/myfeature/state.json | jq '.status'

# Current iteration
cat .claude/pipeline-runs/myfeature/state.json | jq '.iteration'

# Check crash recovery info
cat .claude/pipeline-runs/myfeature/state.json | jq '{iteration, iteration_completed, status}'

# Get completion reason
cat .claude/pipeline-runs/myfeature/state.json | jq '.completion_reason'
```

---

## Multi-Stage Pipeline State

**Location:** `.claude/pipeline-runs/{session-name}/state.json`

**Purpose:** Track multi-stage pipeline progress. Created by `engine.sh`.

### Schema

```json
{
  "session": "myrefine",
  "pipeline": "full-refine",
  "started_at": "2025-01-10T10:00:00Z",
  "status": "running",
  "current_stage": 2,
  "stages": [
    {
      "name": "improve-plan",
      "loop": "improve-plan",
      "runs": 5,
      "status": "completed",
      "started_at": "2025-01-10T10:00:00Z",
      "completed_at": "2025-01-10T10:15:00Z",
      "iterations_run": 3,
      "reason": "plateau"
    },
    {
      "name": "refine-beads",
      "loop": "refine-beads",
      "runs": 5,
      "status": "running",
      "started_at": "2025-01-10T10:15:00Z"
    }
  ],
  "completed_at": null
}
```

### Reading Pipeline State

```bash
# Current stage
cat .claude/pipeline-runs/myrefine/state.json | jq '.current_stage'

# Stage names and status
cat .claude/pipeline-runs/myrefine/state.json | jq '.stages[] | {name, status}'

# Check if complete
cat .claude/pipeline-runs/myrefine/state.json | jq '.status'
```

---

## Progress Files

**Location:** `.claude/pipeline-runs/{session}/progress-{session}.md`

**Purpose:** Accumulated context for fresh agents each iteration. Markdown format. Each iteration's agent reads this to maintain context without degradation.

### Structure

```markdown
# Progress: myfeature

Verify: npm test && npm run build

## Codebase Patterns
(Patterns discovered during implementation)

---

## 2025-01-10 - beads-123
- Implemented user authentication
- Files: src/auth/login.ts, src/auth/middleware.ts
- Learning: Token refresh needs to handle concurrent requests

---

## 2025-01-10 - beads-124
- Added password reset flow
- Files: src/auth/reset.ts, src/email/templates/reset.html
- Learning: Email templates should be tested with real SMTP

---
```

### Reading Progress

```bash
# Full progress file
cat .claude/pipeline-runs/myfeature/progress-myfeature.md

# Just the learnings (everything after first ---)
awk '/^---$/{found=1; next} found' .claude/pipeline-runs/myfeature/progress-myfeature.md
```

---

## Directory Structure

All sessions (loops AND pipelines) now use the unified `pipeline-runs/` directory:

```
.claude/
├── locks/                          # Session lock files
│   └── {session}.lock              # Per-session lock with heartbeat
└── pipeline-runs/                  # ALL sessions go here now
    └── {session}/                  # Same structure for loops AND pipelines
        ├── state.json              # Iteration tracking, crash recovery
        ├── progress-{session}.md   # Accumulated context
        ├── pipeline.yaml           # Copy of pipeline config (pipelines only)
        └── stage-{N}-{name}/       # Per-stage directories (multi-stage only)
            ├── progress.md         # Stage-specific progress
            └── output.md           # Stage output
```

---

## Lock Files

**Location:** `.claude/locks/{session}.lock`

**Purpose:** Prevent concurrent sessions with the same name. Automatically created when a loop/pipeline starts, released when it ends.

### Schema

```json
{
  "session": "auth",
  "pid": 12345,
  "started_at": "2025-01-10T10:00:00Z",
  "heartbeat": "2025-01-10T10:05:30Z",
  "heartbeat_epoch": 1736503530
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Session name |
| `pid` | number | Process ID holding the lock |
| `started_at` | ISO8601 | When the lock was acquired |
| `heartbeat` | ISO8601 | Last heartbeat timestamp (updated every 30s) |
| `heartbeat_epoch` | number | Heartbeat as Unix epoch (for stale detection) |

### Operations

**Check if locked:**
```bash
test -f .claude/locks/myfeature.lock && echo "locked" || echo "available"
```

**View lock details:**
```bash
cat .claude/locks/myfeature.lock | jq
```

**Check if PID is still alive:**
```bash
pid=$(jq -r .pid .claude/locks/myfeature.lock)
kill -0 "$pid" 2>/dev/null && echo "alive" || echo "dead (stale lock)"
```

**Clear a stale lock:**
```bash
rm .claude/locks/myfeature.lock
```

**Find all stale locks:**
```bash
for lock_file in .claude/locks/*.lock; do
  [ -f "$lock_file" ] || continue
  pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
  session=$(jq -r '.session // empty' "$lock_file" 2>/dev/null)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "Stale: $session (PID $pid)"
  fi
done
```

---

## Cleanup Operations

**Remove old session directories:**
```bash
# Find sessions older than 7 days
find .claude/pipeline-runs -maxdepth 1 -type d -mtime +7

# Remove specific session
rm -rf .claude/pipeline-runs/{session-name}
```

**Find orphaned locks (PID not running):**
```bash
for lock_file in .claude/locks/*.lock; do
  [ -f "$lock_file" ] || continue
  pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
  session=$(jq -r '.session // empty' "$lock_file" 2>/dev/null)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "Stale: $session (PID $pid)"
  fi
done
```
