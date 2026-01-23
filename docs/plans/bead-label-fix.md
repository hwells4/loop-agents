# Bead Label Matching Problem

## Problem Statement

When starting a pipeline session (e.g., `./scripts/run.sh ralph auth 25`), beads must have the label `pipeline/{SESSION_NAME}` for the agent to find and work on them. However, there is no mechanism to add this label before starting. The result is that sessions immediately stop with "All beads complete" because:

1. **beads-empty.sh** checks `bd ready --label="pipeline/$session"` at line 26
2. If no beads have that label, `remaining=0` and the loop stops
3. The prompts (ralph, codex-work) tell agents to query `bd ready --label=pipeline/${SESSION_NAME}`

**Reproduction:**
```bash
# Create some beads without the pipeline label
bd create --title="Task 1" --type=task

# Start ralph
./scripts/run.sh ralph myproject 25

# Result: Immediately stops - "All beads complete"
# Because no beads have label "pipeline/myproject"
```

## Root Cause Analysis

The system assumes beads already have the correct `pipeline/{session}` label, but:

1. **create-tasks stage** (scripts/stages/create-tasks/prompt.md:72) creates beads with `--labels="pipeline/${SESSION_NAME}"` - but this stage is only used when explicitly running a pipeline that includes task creation
2. **Manual bead creation** doesn't know what session will run them
3. **Existing unlabeled beads** can't be used without manual relabeling
4. **No bootstrap mechanism** exists to label beads at session start

## Current Workarounds (Broken)

Users must manually:
1. Create beads with the exact label they'll use for the session
2. Or relabel existing beads before starting: `bd update <id> --labels=pipeline/mysession`

This is error-prone and violates the "15 seconds to start" promise of `/ralph`.

## Proposed Solution

### Option A: Session Startup Labels Existing Beads (Recommended)

Add a `--label-beads` flag or automatic behavior that labels unlabeled beads at session start.

**Changes:**
1. In `scripts/run.sh` or `engine.sh`, before starting the loop:
   - Check if beads exist with `bd ready`
   - If beads exist but none have `pipeline/{session}` label, offer to label them
   - Or: automatically label all unlabeled ready beads

**Implementation (engine.sh around line 240):**
```bash
# Before run_stage or run_pipeline
label_beads_for_session() {
  local session=$1
  local label="pipeline/$session"

  # Check if any ready beads already have this label
  local labeled_count=$(bd ready --label="$label" 2>/dev/null | wc -l)

  if [ "$labeled_count" -gt 0 ]; then
    return 0  # Already have labeled beads
  fi

  # Check for any ready beads without the label
  local unlabeled=$(bd ready 2>/dev/null | jq -r '.[].id' | head -20)

  if [ -z "$unlabeled" ]; then
    return 0  # No beads at all
  fi

  echo "Found unlabeled ready beads. Labeling for session '$session'..."
  for bead_id in $unlabeled; do
    bd update "$bead_id" --add-label="$label" 2>/dev/null || true
  done
}
```

**Pros:**
- Zero-friction for users
- Works with existing beads
- Backward compatible
- Session isolation preserved (each session labels its own beads)

**Cons:**
- Could accidentally grab unrelated beads
- Modifies beads' labels permanently

### Option B: Query All Ready Beads (Simpler)

Change the query pattern to not require the session label by default.

**Changes:**
1. Default `bd ready` without label in prompts
2. Use session label only when user explicitly wants isolation

**Problems:**
- Loses session isolation - different sessions could grab same beads
- Conflicts when running multiple concurrent sessions

### Option C: Require Label at Session Start

Add a required `--bead-label` flag:
```bash
./scripts/run.sh ralph myproject 25 --bead-label=pipeline/myproject
```

**Problems:**
- More friction
- Redundant (session name == label suffix in most cases)
- Doesn't help create-tasks → ralph workflow

### Option D: Hybrid with Smart Defaults

Combine A and C:
1. Default: Auto-label unlabeled ready beads at session start
2. `--bead-label=X`: Use specific label, don't auto-label
3. `--no-auto-label`: Don't touch existing beads

## Recommended Implementation: Option A + D (Hybrid)

### Step 1: Add `label_beads_for_session` function to `scripts/lib/utils.sh`

```bash
# Label unlabeled ready beads for a session
# Usage: label_beads_for_session "$session" [--force]
label_beads_for_session() {
  local session=$1
  local force=${2:-""}
  local label="pipeline/$session"

  # Skip if --no-auto-label environment variable set
  if [ "${PIPELINE_NO_AUTO_LABEL:-}" = "1" ]; then
    return 0
  fi

  # Check if bd is available
  if ! command -v bd &>/dev/null; then
    return 0  # Not using beads
  fi

  # Check if beads already exist with this label
  local labeled_count
  labeled_count=$(bd ready --label="$label" 2>/dev/null | jq -r '. | length' 2>/dev/null || echo "0")

  if [ "$labeled_count" -gt 0 ]; then
    echo "Found $labeled_count beads with label '$label'"
    return 0
  fi

  # Find unlabeled ready beads
  local unlabeled_ids
  unlabeled_ids=$(bd ready 2>/dev/null | jq -r '.[] | select(.labels == null or (.labels | all(. != "'$label'"))) | .id' 2>/dev/null)

  if [ -z "$unlabeled_ids" ]; then
    return 0  # No unlabeled beads
  fi

  local count
  count=$(echo "$unlabeled_ids" | wc -l | tr -d ' ')

  if [ "$force" != "--force" ]; then
    echo "Found $count ready beads without label '$label'"
    echo "Would you like to label them for this session? [Y/n]"
    read -r response
    if [[ "$response" =~ ^[Nn] ]]; then
      return 0
    fi
  fi

  echo "Labeling $count beads with '$label'..."
  while IFS= read -r bead_id; do
    [ -z "$bead_id" ] && continue
    bd update "$bead_id" --add-label="$label" 2>/dev/null && echo "  Labeled: $bead_id"
  done <<< "$unlabeled_ids"
}
```

### Step 2: Call from engine.sh before running stage

In `engine.sh`, around line 1324 (before `run_stage`):

```bash
if [ "$SINGLE_STAGE" = "true" ]; then
  mkdir -p "$RUN_DIR"

  # Auto-label beads for this session (if using beads-empty completion)
  source "$LIB_DIR/utils.sh"
  load_stage "$STAGE_TYPE" 2>/dev/null || true
  if [ "$STAGE_COMPLETION" = "beads-empty" ]; then
    label_beads_for_session "$SESSION" "--force"
  fi

  run_stage "$STAGE_TYPE" "$SESSION" "$MAX_ITERATIONS" "$RUN_DIR" "0" "$START_ITERATION"
```

### Step 3: Add `--no-auto-label` flag

In the flag parsing section (around line 1181):

```bash
--no-auto-label) export PIPELINE_NO_AUTO_LABEL=1 ;;
```

### Step 4: Update `/ralph` command documentation

Add note about auto-labeling behavior in `commands/ralph.md`.

## Alternative: Pre-flight Check in /ralph

The `/ralph` slash command already verifies tasks exist before starting. Enhance this:

```bash
# In commands/ralph.md step 1
bd ready --label={label} || {
  # No labeled beads, check for unlabeled
  unlabeled=$(bd ready | jq '. | length')
  if [ "$unlabeled" -gt 0 ]; then
    echo "Found $unlabeled ready beads without session label."
    echo "Labeling them for session '{session}'..."
    bd ready | jq -r '.[].id' | xargs -I{} bd update {} --add-label=pipeline/{session}
  fi
}
```

This moves the labeling to the interactive command where user consent is implicit.

## Testing Plan

1. **No beads exist:** Start session → Should not error, just report no work
2. **Unlabeled beads exist:** Start session → Should label them automatically
3. **Pre-labeled beads exist:** Start session → Should find and use them
4. **Mixed:** Some labeled, some not → Only label the unlabeled ones
5. **Concurrent sessions:** Start two sessions → Each should get its own label
6. **--no-auto-label:** Should skip labeling, session stops immediately if no matching beads

## Migration Notes

- No breaking changes to existing workflows
- Users who already label beads correctly will see no change
- Users who don't label beads will get automatic labeling (with confirmation in interactive mode)

## Files to Modify

1. `scripts/lib/utils.sh` - Add `label_beads_for_session` function
2. `scripts/engine.sh` - Call labeling function before stage start
3. `commands/ralph.md` - Document auto-labeling behavior
4. `CLAUDE.md` - Add note about bead labeling in Quick Start
