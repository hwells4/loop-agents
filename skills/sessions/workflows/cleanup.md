# Workflow: Cleanup Sessions

Find and handle stale, orphaned, or completed sessions and lock files.

## Step 1: Gather Session Data

```bash
# Get all tmux sessions
TMUX_SESSIONS=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E "^(loop-|pipeline-)" || echo "")

# Load state file
if [ -f .claude/loop-sessions.json ]; then
  STATE=$(cat .claude/loop-sessions.json)
else
  STATE='{"sessions":{}}'
fi

# Get all lock files
LOCK_FILES=$(ls .claude/locks/*.lock 2>/dev/null || echo "")
```

## Step 2: Identify Orphaned Sessions

Sessions in tmux but not in our state file:

```bash
TRACKED=$(echo "$STATE" | jq -r '.sessions | keys[]')

ORPHANS=""
for sess in $TMUX_SESSIONS; do
  if ! echo "$TRACKED" | grep -q "^$sess$"; then
    ORPHANS="$ORPHANS $sess"
  fi
done
```

## Step 3: Identify Stale Sessions

Sessions running > 2 hours:

```bash
echo "$STATE" | jq -r '
  .sessions | to_entries[] |
  select(.value.status == "running") |
  "\(.key)|\(.value.started_at)"
' | while IFS="|" read name started; do
  START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" "+%s" 2>/dev/null || date -d "$started" "+%s" 2>/dev/null || echo "0")
  NOW_EPOCH=$(date "+%s")
  AGE_MINS=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
  if [ $AGE_MINS -gt 120 ]; then
    echo "STALE|$name|$AGE_MINS"
  fi
done
```

## Step 4: Identify Zombie State Entries

Sessions in state file marked "running" but not in tmux:

```bash
echo "$STATE" | jq -r '
  .sessions | to_entries[] |
  select(.value.status == "running") |
  .key
' | while read name; do
  if ! tmux has-session -t "$name" 2>/dev/null; then
    echo "ZOMBIE: $name"
  fi
done
```

## Step 4b: Identify Stale Locks

Lock files where the PID is no longer running:

```bash
for lock_file in .claude/locks/*.lock; do
  [ -f "$lock_file" ] || continue
  pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
  session=$(jq -r '.session // empty' "$lock_file" 2>/dev/null)
  started=$(jq -r '.started_at // empty' "$lock_file" 2>/dev/null)

  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "STALE_LOCK: $session (PID $pid, started $started)"
  fi
done
```

## Step 5: Present Findings

Show what was found:

```
Cleanup Report
==============

Orphaned Sessions (in tmux, not tracked):
{list orphans or "None found"}

Stale Sessions (running > 2 hours):
{list stale with ages or "None found"}

Zombie Entries (in state file, not running):
{list zombies or "None found"}

Stale Locks (lock file exists, PID dead):
{list stale locks or "None found"}
```

## Step 6: Handle Orphans

If orphans found:

```json
{
  "questions": [{
    "question": "Found {N} orphaned sessions. What should we do?",
    "header": "Orphans",
    "options": [
      {"label": "Kill all orphans", "description": "Terminate and don't track"},
      {"label": "Add to tracking", "description": "Start tracking these sessions"},
      {"label": "Review each", "description": "Decide per session"},
      {"label": "Leave them", "description": "Don't touch orphans"}
    ],
    "multiSelect": false
  }]
}
```

**Kill all orphans:**
```bash
for sess in $ORPHANS; do
  tmux kill-session -t "$sess"
  echo "Killed: $sess"
done
```

**Add to tracking:**
```bash
for sess in $ORPHANS; do
  TYPE="loop"
  [[ "$sess" == pipeline-* ]] && TYPE="pipeline"

  STATE=$(echo "$STATE" | jq --arg name "$sess" \
    --arg type "$TYPE" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg path "$(pwd)" \
    '.sessions[$name] = {
      "type": $type,
      "started_at": $started,
      "project_path": $path,
      "status": "running",
      "note": "recovered from orphan"
    }')
done
echo "$STATE" > .claude/loop-sessions.json
```

**Review each:** Loop through and ask about each one individually.

## Step 7: Handle Stale Sessions

If stale found:

```json
{
  "questions": [{
    "question": "Found {N} sessions running > 2 hours. What should we do?",
    "header": "Stale",
    "options": [
      {"label": "Kill all stale", "description": "Terminate long-running sessions"},
      {"label": "Review each", "description": "Decide per session"},
      {"label": "Leave them", "description": "They might still be working"}
    ],
    "multiSelect": false
  }]
}
```

For each stale session, offer to:
1. Monitor it (see what it's doing)
2. Kill it
3. Leave it running

## Step 8: Handle Zombies

Zombie entries are state file records for sessions that aren't running. These need to be updated:

```bash
echo "$STATE" | jq '
  .sessions |= with_entries(
    if .value.status == "running" then
      .value.status = "unknown_termination" |
      .value.cleaned_at = now | todate
    else
      .
    end
  )
' > .claude/loop-sessions.json
```

Or offer to remove them entirely:

```json
{
  "questions": [{
    "question": "Found {N} zombie entries. What should we do?",
    "header": "Zombies",
    "options": [
      {"label": "Mark as terminated", "description": "Update status to 'unknown_termination'"},
      {"label": "Remove entries", "description": "Delete from state file entirely"},
      {"label": "Leave them", "description": "Don't modify state file"}
    ],
    "multiSelect": false
  }]
}
```

## Step 8b: Handle Stale Locks

If stale locks found:

```json
{
  "questions": [{
    "question": "Found {N} stale lock files (PIDs no longer running). What should we do?",
    "header": "Stale Locks",
    "options": [
      {"label": "Remove all stale locks", "description": "Delete lock files for dead processes"},
      {"label": "Review each", "description": "Decide per lock file"},
      {"label": "Leave them", "description": "Don't touch lock files"}
    ],
    "multiSelect": false
  }]
}
```

**Remove all stale locks:**
```bash
for lock_file in .claude/locks/*.lock; do
  [ -f "$lock_file" ] || continue
  pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null)
  session=$(jq -r '.session // empty' "$lock_file" 2>/dev/null)

  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    echo "Removing stale lock: $session (PID $pid)"
    rm -f "$lock_file"
  fi
done
```

## Step 9: Prune Old Entries

Optionally clean up old completed/killed entries:

```json
{
  "questions": [{
    "question": "Remove old completed entries from state file? (> 7 days old)",
    "header": "Prune",
    "options": [
      {"label": "Yes, clean up", "description": "Remove entries older than 7 days"},
      {"label": "No, keep all", "description": "Preserve history"}
    ],
    "multiSelect": false
  }]
}
```

If yes:
```bash
CUTOFF=$(date -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)

jq --arg cutoff "$CUTOFF" '
  .sessions |= with_entries(
    select(
      .value.status == "running" or
      (.value.completed_at // .value.killed_at // .value.started_at) > $cutoff
    )
  )
' .claude/loop-sessions.json > .claude/loop-sessions.json.tmp
mv .claude/loop-sessions.json.tmp .claude/loop-sessions.json
```

## Step 10: Final Summary

```
Cleanup Complete
================

Actions taken:
- Killed {X} orphaned sessions
- Killed {Y} stale sessions
- Updated {Z} zombie entries
- Removed {L} stale locks
- Pruned {W} old entries

Current state:
- Running sessions: {count}
- Active locks: {count}
- State file entries: {count}

Run '/loop-agents:sessions → List' to see current status.
```

## Success Criteria

- [ ] Orphans identified and handled
- [ ] Stale sessions identified and handled
- [ ] Zombie entries cleaned up
- [ ] Stale locks cleaned up
- [ ] State file is consistent with tmux reality
- [ ] Lock files are consistent with running processes
- [ ] User informed of all actions taken
