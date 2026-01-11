# State Files Reference

Complete reference for state file schemas and operations.

## Session Tracking State

**Location:** `.claude/loop-sessions.json`

**Purpose:** Track all sessions started by Claude across conversations.

### Schema

```json
{
  "sessions": {
    "loop-feature-name": {
      "type": "loop",
      "loop_type": "work",
      "started_at": "2025-01-10T10:00:00Z",
      "project_path": "/path/to/project",
      "max_iterations": 50,
      "status": "running",
      "killed_at": null,
      "completed_at": null,
      "note": null
    },
    "pipeline-refine": {
      "type": "pipeline",
      "pipeline_file": "full-refine.yaml",
      "started_at": "2025-01-10T11:00:00Z",
      "project_path": "/path/to/project",
      "status": "running"
    }
  }
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | `"loop"` or `"pipeline"` |
| `loop_type` | string | For loops: `work`, `improve-plan`, etc. |
| `pipeline_file` | string | For pipelines: filename like `full-refine.yaml` |
| `started_at` | ISO8601 | When session was started |
| `project_path` | string | Absolute path to project |
| `max_iterations` | number | For loops: maximum iterations allowed |
| `status` | string | `running`, `completed`, `killed`, `unknown_termination` |
| `killed_at` | ISO8601 | When manually killed (if applicable) |
| `completed_at` | ISO8601 | When finished naturally (if applicable) |
| `note` | string | Optional note (e.g., "recovered from orphan") |

### Operations

**Read current state:**
```bash
cat .claude/loop-sessions.json | jq '.'
```

**Add a new session:**
```bash
jq --arg name "loop-myfeature" \
   --arg type "loop" \
   --arg loop_type "work" \
   --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   --arg path "$(pwd)" \
   --argjson max 50 \
   '.sessions[$name] = {
     type: $type,
     loop_type: $loop_type,
     started_at: $started,
     project_path: $path,
     max_iterations: $max,
     status: "running"
   }' .claude/loop-sessions.json > tmp && mv tmp .claude/loop-sessions.json
```

**Update status:**
```bash
jq --arg name "loop-myfeature" \
   --arg status "killed" \
   --arg killed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.sessions[$name].status = $status |
    .sessions[$name].killed_at = $killed' \
   .claude/loop-sessions.json > tmp && mv tmp .claude/loop-sessions.json
```

**List running sessions:**
```bash
jq -r '.sessions | to_entries[] | select(.value.status == "running") | .key' .claude/loop-sessions.json
```

**Remove a session entry:**
```bash
jq --arg name "loop-myfeature" 'del(.sessions[$name])' .claude/loop-sessions.json > tmp && mv tmp .claude/loop-sessions.json
```

---

## Loop State Files

**Location:** `.claude/loop-state-{session-name}.json`

**Purpose:** Track iteration history for a single loop run. Created by `engine.sh`.

### Schema

```json
{
  "session": "myfeature",
  "type": "loop",
  "loop_type": "work",
  "started_at": "2025-01-10T10:00:00Z",
  "status": "running",
  "iteration": 5,
  "history": [
    {
      "iteration": 1,
      "timestamp": "2025-01-10T10:01:00Z",
      "plateau": false,
      "reasoning": null
    },
    {
      "iteration": 2,
      "timestamp": "2025-01-10T10:05:00Z",
      "plateau": true,
      "reasoning": "No significant improvements found"
    }
  ],
  "completed_at": null,
  "reason": null
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Session name (without `loop-` prefix) |
| `type` | string | Always `"loop"` |
| `loop_type` | string | Loop type (work, improve-plan, etc.) |
| `started_at` | ISO8601 | When loop started |
| `status` | string | `running`, `completed`, `failed` |
| `iteration` | number | Current/final iteration count |
| `history` | array | Per-iteration data |
| `completed_at` | ISO8601 | When finished (if applicable) |
| `reason` | string | Why loop stopped (e.g., "beads-empty", "plateau") |

### Reading Loop State

```bash
# Current status
cat .claude/loop-state-myfeature.json | jq '.status'

# Current iteration
cat .claude/loop-state-myfeature.json | jq '.iteration'

# Check if complete
cat .claude/loop-state-myfeature.json | jq 'if .status == "completed" then "done" else "running" end'

# Get completion reason
cat .claude/loop-state-myfeature.json | jq '.reason'
```

---

## Pipeline State Files

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

**Location:** `.claude/loop-progress/progress-{session-name}.txt`

**Purpose:** Accumulated context for fresh agents each iteration. Markdown format.

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
cat .claude/loop-progress/progress-myfeature.txt

# Just the learnings (everything after first ---)
awk '/^---$/{found=1; next} found' .claude/loop-progress/progress-myfeature.txt
```

---

## Directory Structure

```
.claude/
├── loop-sessions.json              # Session tracking (all sessions)
├── loop-state-{session}.json       # Per-loop iteration history
├── loop-progress/
│   └── progress-{session}.txt      # Accumulated context per session
├── loop-completions.json           # Log of all completions (optional)
├── locks/                          # Session lock files
│   └── {session}.lock              # Per-session lock (prevents duplicates)
└── pipeline-runs/
    └── {session}/
        ├── state.json              # Pipeline progress
        ├── pipeline.yaml           # Copy of pipeline config
        └── stage-{N}-{name}/
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
  "started_at": "2025-01-10T10:00:00Z"
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `session` | string | Session name |
| `pid` | number | Process ID holding the lock |
| `started_at` | ISO8601 | When the lock was acquired |

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

**Remove completed entries older than 7 days:**
```bash
CUTOFF=$(date -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)

jq --arg cutoff "$CUTOFF" '
  .sessions |= with_entries(
    select(
      .value.status == "running" or
      (.value.completed_at // .value.killed_at // .value.started_at) > $cutoff
    )
  )
' .claude/loop-sessions.json > tmp && mv tmp .claude/loop-sessions.json
```

**Remove all killed/completed entries:**
```bash
jq '.sessions |= with_entries(select(.value.status == "running"))' \
  .claude/loop-sessions.json > tmp && mv tmp .claude/loop-sessions.json
```

**Find orphaned state files (no matching session):**
```bash
for f in .claude/loop-state-*.json; do
  session=$(basename "$f" | sed 's/loop-state-//; s/.json//')
  if ! jq -e ".sessions[\"loop-$session\"]" .claude/loop-sessions.json >/dev/null 2>&1; then
    echo "Orphaned: $f"
  fi
done
```
