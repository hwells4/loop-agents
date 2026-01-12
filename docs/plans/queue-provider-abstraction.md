# Queue Provider Abstraction

## Overview

Generalize the queue/work system to support multiple providers (beads, file-based todos, custom commands, APIs) instead of hardcoding to the beads CLI. This enables work stages to consume tasks from any source: files, GitHub Issues, Linear, Jira, or custom scripts.

**Current state:** The work stage is hardcoded to use `bd` (beads CLI) in three places:
- `scripts/lib/completions/beads-empty.sh:20` - completion check
- `scripts/stages/work/prompt.md` - agent instructions (4 locations)
- `scripts/engine.sh:88` - termination type mapping

**Target state:** Provider-agnostic queue interface where providers are pluggable and prompts receive injected commands.

## Problem Statement / Motivation

The agent-pipelines system currently only works with beads for task management. Users want to:
1. **Use file-based todos** - Track tasks in `todos/*.md` with YAML frontmatter
2. **Integrate with external systems** - GitHub Issues, Linear, Jira
3. **Create custom providers** - Wrap any CLI/API as a work source
4. **Keep beads working** - Zero breaking changes for existing workflows

This was explicitly planned in `docs/plans/potential-plan-updates.md` Section 7 but not implemented in v3.

## Proposed Solution

### Provider Interface Contract

Providers are directories in `scripts/lib/providers/` containing executable scripts:

```
scripts/lib/providers/
├── beads/
│   ├── provider.yaml     # Metadata and config schema
│   ├── list              # List available items → stdout (one per line or JSON)
│   ├── count             # Count available items → stdout (number)
│   ├── claim             # Claim item → exit 0 success, 1 already claimed
│   ├── show              # Show item details → stdout (JSON)
│   ├── complete          # Mark complete → exit 0 success
│   └── release           # Release claim (optional)
├── file/
│   └── ...
└── cmd/
    └── ...
```

**Environment variables passed to all commands:**
```bash
QUEUE_SESSION="my-session"        # Session name
QUEUE_LABEL="loop/my-session"     # Label for filtering (convention)
QUEUE_ITEM_ID="task-123"          # Item ID (for claim/show/complete/release)
QUEUE_CONFIG='{"dir":"todos"}'    # Provider-specific config as JSON
```

**Standard output format for `list` and `show`:**
```json
{"id": "task-123", "title": "Fix auth bug", "status": "ready"}
```

### Configuration Schema

```yaml
# scripts/stages/work/stage.yaml
name: work
description: Implement features from queue until done

termination:
  type: queue

queue:
  provider: beads              # Provider name (directory in providers/)
  config:                      # Provider-specific config (passed as QUEUE_CONFIG)
    label_prefix: "pipeline/"      # Beads-specific: label prefix
```

**File provider example:**
```yaml
queue:
  provider: file
  config:
    directory: "todos"
    pattern: "*-pending-*.md"
    status_field: "status"     # YAML frontmatter field
```

**Command provider example:**
```yaml
queue:
  provider: cmd
  config:
    list: "./scripts/my-list.sh"
    claim: "./scripts/my-claim.sh"
    complete: "./scripts/my-complete.sh"
```

### Prompt Command Injection

Commands are injected into `context.json` for agent use:

```json
{
  "session": "auth",
  "queue": {
    "provider": "beads",
    "commands": {
      "list": "bd ready --label=pipeline/auth",
      "claim": "bd update {{id}} --status=in_progress",
      "show": "bd show {{id}}",
      "complete": "bd close {{id}}"
    },
    "current_item": null
  }
}
```

Prompts reference these via `${CTX}`:
```markdown
Read context from: ${CTX}

The context.json contains queue commands. Use `jq '.queue.commands.list' ${CTX}`
to get the list command, then execute it.
```

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         engine.sh                                │
│  load_stage() → load_queue_provider() → validate_provider()     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      lib/queue.sh                                │
│  load_queue_provider()    queue_list()      queue_count()       │
│  validate_provider()      queue_claim()     queue_complete()    │
│  get_provider_commands()  queue_show()      queue_release()     │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐    ┌──────────┐    ┌──────────┐
        │  beads/  │    │  file/   │    │  cmd/    │
        │  list    │    │  list    │    │  list    │
        │  claim   │    │  claim   │    │  claim   │
        │  ...     │    │  ...     │    │  ...     │
        └──────────┘    └──────────┘    └──────────┘
```

### Implementation Phases

#### Phase 1: Provider Abstraction Layer
**Files:** `scripts/lib/queue.sh` (new)

```bash
# Load provider and validate
load_queue_provider() {
  local provider=$1
  local config=$2
  local provider_dir="$LIB_DIR/providers/$provider"

  if [ ! -d "$provider_dir" ]; then
    echo "Error: Unknown queue provider: $provider" >&2
    return 1
  fi

  # Validate required commands exist
  for cmd in list count claim complete; do
    if [ ! -x "$provider_dir/$cmd" ]; then
      echo "Error: Provider '$provider' missing command: $cmd" >&2
      return 1
    fi
  done

  export QUEUE_PROVIDER="$provider"
  export QUEUE_PROVIDER_DIR="$provider_dir"
  export QUEUE_CONFIG="$config"
}

# Provider-agnostic operations
queue_count() {
  local session=$1
  QUEUE_SESSION="$session" QUEUE_LABEL="pipeline/$session" \
    "$QUEUE_PROVIDER_DIR/count"
}
```

#### Phase 2: Extract Beads Provider
**Files:** `scripts/lib/providers/beads/{list,count,claim,show,complete,provider.yaml}`

```bash
#!/bin/bash
# scripts/lib/providers/beads/count
session=${QUEUE_SESSION:?"QUEUE_SESSION required"}
label="pipeline/$session"
bd ready --label="$label" 2>/dev/null | grep -c "^" || echo "0"
```

```bash
#!/bin/bash
# scripts/lib/providers/beads/list
session=${QUEUE_SESSION:?"QUEUE_SESSION required"}
label="pipeline/$session"
bd ready --label="$label" --json 2>/dev/null || echo "[]"
```

```yaml
# scripts/lib/providers/beads/provider.yaml
name: beads
description: Beads CLI task queue
requires:
  - bd
  - jq
config_schema:
  label_prefix:
    type: string
    default: "pipeline/"
    description: Prefix for session labels
```

#### Phase 3: Update Completion Strategy
**Files:** Rename `beads-empty.sh` → keep for compatibility, create `queue-empty.sh`

```bash
#!/bin/bash
# scripts/lib/completions/queue-empty.sh
# Generic queue completion - works with any provider

check_completion() {
  local session=$1
  local state_file=$2
  local status_file=$3

  # Check for agent error
  local decision=$(get_status_decision "$status_file" 2>/dev/null)
  if [ "$decision" = "error" ]; then
    return 1  # Don't complete on error
  fi

  # Use provider abstraction
  local remaining=$(queue_count "$session")
  [ "$remaining" -eq 0 ]
}
```

#### Phase 4: Engine Integration
**Files:** `scripts/engine.sh`, `scripts/lib/context.sh`

```bash
# engine.sh: load_stage() additions
local queue_provider=$(json_get "$STAGE_CONFIG" ".queue.provider" "beads")
local queue_config=$(json_get "$STAGE_CONFIG" ".queue.config" "{}")

if [ "$STAGE_COMPLETION" = "queue-empty" ] || [ "$STAGE_COMPLETION" = "beads-empty" ]; then
  load_queue_provider "$queue_provider" "$queue_config" || return 1
fi
```

```bash
# context.sh: Add queue commands to context.json
if [ -n "$QUEUE_PROVIDER" ]; then
  local queue_commands=$(get_provider_commands "$session")
  # Merge into context.json
fi
```

#### Phase 5: File Provider
**Files:** `scripts/lib/providers/file/{list,count,claim,show,complete,provider.yaml}`

```bash
#!/bin/bash
# scripts/lib/providers/file/list
config=${QUEUE_CONFIG:-"{}"}
dir=$(echo "$config" | jq -r '.directory // "todos"')
pattern=$(echo "$config" | jq -r '.pattern // "*-pending-*.md"')

for f in "$dir"/$pattern; do
  [ -f "$f" ] || continue
  id=$(basename "$f" .md)
  title=$(grep -m1 "^# " "$f" | sed 's/^# //')
  echo "{\"id\": \"$id\", \"title\": \"$title\", \"file\": \"$f\"}"
done
```

```bash
#!/bin/bash
# scripts/lib/providers/file/claim
config=${QUEUE_CONFIG:-"{}"}
item_id=${QUEUE_ITEM_ID:?"QUEUE_ITEM_ID required"}
dir=$(echo "$config" | jq -r '.directory // "todos"')

# Find file and rename pending → in_progress
src=$(ls "$dir"/*-pending-*"$item_id"*.md 2>/dev/null | head -1)
if [ -z "$src" ]; then
  echo "Error: Item not found: $item_id" >&2
  exit 1
fi

dst="${src/pending/in_progress}"
mv "$src" "$dst"
echo "{\"id\": \"$item_id\", \"file\": \"$dst\"}"
```

#### Phase 6: Command Provider
**Files:** `scripts/lib/providers/cmd/{list,count,claim,show,complete,provider.yaml}`

Generic wrapper that delegates to user-specified commands:

```bash
#!/bin/bash
# scripts/lib/providers/cmd/list
config=${QUEUE_CONFIG:-"{}"}
cmd=$(echo "$config" | jq -r '.list // empty')

if [ -z "$cmd" ]; then
  echo "Error: cmd provider requires 'list' config" >&2
  exit 1
fi

eval "$cmd"
```

## Acceptance Criteria

### Functional Requirements
- [ ] Existing work stages with no `queue:` block default to beads provider
- [ ] `queue.provider: beads` works identically to current hardcoded behavior
- [ ] `queue.provider: file` processes todos from specified directory
- [ ] `queue.provider: cmd` delegates to user-specified commands
- [ ] Completion strategy `queue-empty` works with any provider
- [ ] context.json includes `queue.commands` for agent use
- [ ] Provider validation fails fast before agent invocation

### Non-Functional Requirements
- [ ] No breaking changes for existing beads-based work stages
- [ ] Provider commands complete in <100ms for local providers
- [ ] Clear error messages for misconfigured providers

### Quality Gates
- [ ] Unit tests for queue.sh abstraction layer
- [ ] Integration tests for each provider (beads, file, cmd)
- [ ] Validation tests for malformed provider configs
- [ ] Migration test: existing work stage unchanged behavior

## Success Metrics

1. **Zero breaking changes** - All existing beads-based work stages pass
2. **Provider parity** - File provider can process `todos/*.md` files
3. **Extensibility** - Adding new provider requires only new directory, no engine changes

## Dependencies & Prerequisites

- v3 architecture (context.json, status.json) - ✅ Complete
- Session name validation - ✅ Complete
- Atomic file operations - ✅ Complete (state.sh patterns)

## Risk Analysis & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Breaking existing beads workflows | High | Medium | Default to beads when no queue config |
| Command injection via provider config | High | Low | Validate all config values, no eval of untrusted input |
| Provider command failures mid-iteration | Medium | Medium | Clear error in status.json, agent handles gracefully |
| Orphaned work after crash | Medium | Low | Track claimed items in state.json (Phase 2) |

## Future Considerations

1. **API providers** - GitHub, Linear, Jira (requires auth handling)
2. **Caching** - Cache list results to reduce API calls
3. **Concurrency guards** - Prevent multiple agents claiming same item
4. **Provider registry** - `./scripts/run.sh providers` discovery command
5. **Heartbeat for claims** - Auto-release after timeout

## MVP Implementation Order

```
scripts/lib/
├── queue.sh                    # Phase 1: Abstraction layer
└── providers/
    ├── beads/                  # Phase 2: Extract current behavior
    │   ├── provider.yaml
    │   ├── list
    │   ├── count
    │   ├── claim
    │   ├── show
    │   └── complete
    └── file/                   # Phase 5: File-based todos
        ├── provider.yaml
        ├── list
        ├── count
        ├── claim
        ├── show
        └── complete

scripts/lib/completions/
└── queue-empty.sh              # Phase 3: Generic completion

scripts/engine.sh               # Phase 4: Integration
scripts/lib/context.sh          # Phase 4: Command injection
```

## Test Plan

### test_queue.sh
```bash
test_load_queue_provider_beads() {
  load_queue_provider "beads" "{}"
  assert_equals "$QUEUE_PROVIDER" "beads"
  assert_dir_exists "$QUEUE_PROVIDER_DIR"
}

test_load_queue_provider_invalid() {
  ! load_queue_provider "nonexistent" "{}"
  assert_equals $? 1
}

test_queue_count_beads() {
  # Mock bd ready to return 3 items
  MOCK_BD_OUTPUT="item1\nitem2\nitem3"
  load_queue_provider "beads" "{}"
  count=$(queue_count "test-session")
  assert_equals "$count" "3"
}
```

### test_file_provider.sh
```bash
test_file_list_pending() {
  mkdir -p "$TEST_DIR/todos"
  echo "---\nstatus: pending\n---\n# Task 1" > "$TEST_DIR/todos/001-pending-p1-task.md"

  QUEUE_CONFIG='{"directory":"'$TEST_DIR'/todos"}'
  output=$("$PROVIDER_DIR/file/list")

  assert_contains "$output" "001-pending-p1-task"
}

test_file_claim_renames() {
  mkdir -p "$TEST_DIR/todos"
  echo "# Task" > "$TEST_DIR/todos/001-pending-p1-task.md"

  QUEUE_CONFIG='{"directory":"'$TEST_DIR'/todos"}'
  QUEUE_ITEM_ID="001"
  "$PROVIDER_DIR/file/claim"

  assert_file_exists "$TEST_DIR/todos/001-in_progress-p1-task.md"
  assert_file_not_exists "$TEST_DIR/todos/001-pending-p1-task.md"
}
```

## References

### Internal References
- Current beads hardcoding: `scripts/lib/completions/beads-empty.sh:20`
- Planned design: `docs/plans/potential-plan-updates.md:162-178`
- v3 context generation: `scripts/lib/context.sh:66-143`
- Provider pattern (inputs): `scripts/lib/context.sh:147-215`

### External References
- Git credential helper protocol (provider pattern inspiration)
- asdf plugin structure (directory-based providers)
- AWS SQS visibility timeout (claim semantics)

### Related Work
- v3 implementation: Complete (provides foundation)
- Code review todos: `todos/001-010` (some overlap with queue abstraction)
