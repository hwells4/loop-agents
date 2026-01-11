# Plan: Session Lifecycle Hooks

> NOTE: This feature is deprioritized - focus on quality of life improvements first.
> This comprehensive plan exists to circle back to later.

## Overview

Add extensibility points to engine.sh that allow users to customize behavior at key session moments without forking the engine.

## Problem

Users can't customize behavior at key session moments:
- Send a Slack message on completion
- Run cleanup on failure
- Back up progress file between iterations
- Custom logging or metrics
- Integration with external tools

Currently requires forking the engine, which creates maintenance burden.

## Solution

Add hook points that execute shell commands at key moments in the session lifecycle.

## Hook Points

| Hook | When | Use Cases |
|------|------|-----------|
| `on_session_start` | Before first iteration | Initialize resources, send "started" notification |
| `on_iteration_start` | Before each Claude call | Log iteration start, check prerequisites |
| `on_iteration_complete` | After each successful iteration | Backup progress, log metrics, intermediate notifications |
| `on_session_complete` | When loop finishes (success or max) | Send completion notification, cleanup, reporting |
| `on_error` | When iteration fails | Error notifications, cleanup, retry logic |

## Configuration

### Per-Loop Configuration (loop.yaml)

```yaml
name: my-loop
description: Loop with hooks

hooks:
  on_session_start: "./scripts/notify.sh started ${SESSION}"
  on_iteration_complete: "./scripts/backup-progress.sh ${PROGRESS_FILE}"
  on_session_complete: "./scripts/notify.sh completed ${SESSION} ${ITERATION}"
  on_error: "./scripts/notify.sh failed ${SESSION} ${ERROR}"
```

### Global Configuration (~/.config/loop-agents/hooks.sh)

```bash
#!/bin/bash
# Global hooks - run for all sessions

on_session_complete() {
  local session=$1
  local status=$2
  local iterations=$3

  # Send to Slack
  curl -X POST "$SLACK_WEBHOOK" \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"Loop $session completed after $iterations iterations\"}"
}

on_error() {
  local session=$1
  local error=$2

  # Send error alert
  osascript -e "display notification \"Loop $session failed: $error\" with title \"Loop Error\""
}
```

### Hook Priority

1. Loop-specific hooks (loop.yaml) run first
2. Global hooks (~/.config/loop-agents/hooks.sh) run second
3. Either can be disabled with `hooks.disable_global: true` in loop.yaml

## Environment Variables

Hooks receive context via environment variables:

| Variable | Description |
|----------|-------------|
| `LOOP_SESSION` | Session name |
| `LOOP_TYPE` | Loop type (work, improve-plan, etc.) |
| `LOOP_ITERATION` | Current iteration number |
| `LOOP_MAX_ITERATIONS` | Maximum iterations configured |
| `LOOP_STATUS` | Current status (running, completed, failed) |
| `LOOP_PROGRESS_FILE` | Path to progress file |
| `LOOP_STATE_FILE` | Path to state file |
| `LOOP_ERROR` | Error message (for on_error only) |
| `LOOP_DURATION` | Elapsed time in seconds |

## Implementation

### New File: scripts/lib/hooks.sh

```bash
#!/bin/bash
# Hook execution utilities

HOOKS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/loop-agents"
HOOKS_FILE="$HOOKS_CONFIG_DIR/hooks.sh"

# Load global hooks if available
load_global_hooks() {
  if [ -f "$HOOKS_FILE" ]; then
    source "$HOOKS_FILE"
  fi
}

# Execute a hook
# Usage: execute_hook "on_session_start" "session_name"
execute_hook() {
  local hook_name=$1
  shift
  local args=("$@")

  # Export context as environment variables
  export LOOP_SESSION="$SESSION"
  export LOOP_TYPE="$LOOP_TYPE"
  export LOOP_ITERATION="$CURRENT_ITERATION"
  export LOOP_MAX_ITERATIONS="$MAX_ITERATIONS"
  export LOOP_STATUS="$STATUS"
  export LOOP_PROGRESS_FILE="$PROGRESS_FILE"
  export LOOP_STATE_FILE="$STATE_FILE"
  export LOOP_DURATION="$DURATION"

  # Execute loop-specific hook if defined
  local loop_hook=$(get_loop_hook "$hook_name")
  if [ -n "$loop_hook" ]; then
    log_debug "Executing loop hook: $hook_name"
    eval "$loop_hook" || log_warn "Loop hook $hook_name failed"
  fi

  # Execute global hook if function exists and not disabled
  if [ "$DISABLE_GLOBAL_HOOKS" != "true" ]; then
    if type "$hook_name" &>/dev/null; then
      log_debug "Executing global hook: $hook_name"
      "$hook_name" "${args[@]}" || log_warn "Global hook $hook_name failed"
    fi
  fi
}

# Get hook command from loop config
get_loop_hook() {
  local hook_name=$1
  json_get "$LOOP_CONFIG" ".hooks.$hook_name" ""
}
```

### Modifications to engine.sh

```bash
# At top of file
source "$LIB_DIR/hooks.sh"
load_global_hooks

# Before main loop
execute_hook "on_session_start"

# In iteration loop, before Claude call
execute_hook "on_iteration_start"

# After successful Claude call
execute_hook "on_iteration_complete"

# On error
execute_hook "on_error" "$ERROR_MESSAGE"

# At end of session
execute_hook "on_session_complete"
```

## Webhook Notifications

Built-in webhook templates as a first-class hook use case.

### Setup Command

```bash
./scripts/run.sh notify setup slack
# Prompts for webhook URL, stores in config

./scripts/run.sh notify setup discord
./scripts/run.sh notify setup teams
```

### Configuration (~/.config/loop-agents/webhooks.yaml)

```yaml
webhooks:
  slack:
    url: "https://hooks.slack.com/services/xxx"
    events: [session_complete, error]

  discord:
    url: "https://discord.com/api/webhooks/xxx"
    events: [session_complete]
```

### Built-in Templates

```bash
# scripts/lib/webhooks.sh

send_slack_notification() {
  local event=$1
  local session=$2
  local status=$3
  local iterations=$4
  local duration=$5

  local color="good"
  [ "$status" = "failed" ] && color="danger"

  curl -X POST "$SLACK_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{
      \"attachments\": [{
        \"color\": \"$color\",
        \"title\": \"Loop $session $status\",
        \"fields\": [
          {\"title\": \"Iterations\", \"value\": \"$iterations\", \"short\": true},
          {\"title\": \"Duration\", \"value\": \"$duration\", \"short\": true}
        ]
      }]
    }"
}
```

## Implementation Phases

### Phase 1: Core Hook Infrastructure
1. Create `scripts/lib/hooks.sh`
2. Add hook points to `engine.sh`
3. Support loop-specific hooks in `loop.yaml`
4. Test with simple echo hooks

### Phase 2: Global Hooks
1. Support `~/.config/loop-agents/hooks.sh`
2. Add hook priority logic
3. Add `disable_global: true` option

### Phase 3: Webhook Notifications
1. Create `scripts/lib/webhooks.sh`
2. Add `./scripts/run.sh notify setup` command
3. Implement Slack template
4. Implement Discord template
5. Implement Teams template

### Phase 4: Documentation
1. Update CLAUDE.md with hooks section
2. Create example hooks
3. Document all environment variables

## Success Criteria

- [ ] Hooks execute at correct lifecycle points
- [ ] Loop-specific and global hooks both work
- [ ] Hook failures don't crash the loop (graceful degradation)
- [ ] Environment variables expose all relevant context
- [ ] Webhook templates work for Slack/Discord/Teams
- [ ] Setup command stores credentials securely

## Security Considerations

1. **Hook commands are not sandboxed** - users must trust their hook scripts
2. **Webhook URLs are secrets** - store in user config, not in repo
3. **Error messages may contain sensitive info** - be careful what's sent externally

## Future Enhancements

- Hook timeouts (prevent hung hooks from blocking loop)
- Async hooks (fire and forget)
- Hook result capture (influence loop behavior)
- Built-in metrics collection
- Web dashboard integration
