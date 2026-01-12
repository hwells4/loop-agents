# Plan: Session Lifecycle Hooks

> NOTE: This feature is deprioritized - focus on quality of life improvements first.
> This comprehensive plan exists to circle back to later.

## Table of Contents

**Part 1: Basic Hooks (Fire-and-Forget)**
- [Overview](#overview)
- [Hook Points](#hook-points)
- [Configuration](#configuration)
- [Webhook Notifications](#webhook-notifications)
- [Implementation Phases 1-4](#implementation-phases)

**Part 2: Advanced Capabilities**
- [Design Philosophy](#design-philosophy)
- [Nested Pipelines (spawn)](#nested-pipelines-spawn)
- [Blocking Hooks (await)](#blocking-hooks-await)
- [Human-in-the-Loop Patterns](#human-in-the-loop-patterns)
- [Callback Server Architecture](#callback-server-architecture)
- [Implementation Phases 5-8](#implementation-phases-extended)
- [Production Example](#example-full-production-pipeline)

---

## Overview

Add extensibility points to engine.sh that allow users to customize behavior at key session moments without forking the engine.

**Part 1** covers basic fire-and-forget hooks for notifications, logging, and backups.

**Part 2** (added later) extends this to support production-grade, long-running pipelines with:
- **Nested pipelines**: Spawn child pipelines mid-execution (e.g., code review every 10 tasks)
- **Blocking hooks**: Pause and wait for external responses (webhooks, human approval)
- **Human-in-the-loop**: Notification + approval workflows that can run for days

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

### Per-Loop Configuration (stage.yaml)

```yaml
name: my-loop
description: Loop with hooks

hooks:
  on_session_start: "./scripts/notify.sh started ${SESSION}"
  on_iteration_complete: "./scripts/backup-progress.sh ${PROGRESS_FILE}"
  on_session_complete: "./scripts/notify.sh completed ${SESSION} ${ITERATION}"
  on_error: "./scripts/notify.sh failed ${SESSION} ${ERROR}"
```

### Global Configuration (~/.config/agent-pipelines/hooks.sh)

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

1. Loop-specific hooks (stage.yaml) run first
2. Global hooks (~/.config/agent-pipelines/hooks.sh) run second
3. Either can be disabled with `hooks.disable_global: true` in stage.yaml

## Environment Variables

Hooks receive context via environment variables:

| Variable | Description |
|----------|-------------|
| `PIPELINE_SESSION` | Session name |
| `PIPELINE_TYPE` | Loop type (work, improve-plan, etc.) |
| `PIPELINE_ITERATION` | Current iteration number |
| `PIPELINE_MAX_ITERATIONS` | Maximum iterations configured |
| `PIPELINE_STATUS` | Current status (running, completed, failed) |
| `PIPELINE_PROGRESS_FILE` | Path to progress file |
| `PIPELINE_STATE_FILE` | Path to state file |
| `PIPELINE_ERROR` | Error message (for on_error only) |
| `PIPELINE_DURATION` | Elapsed time in seconds |

## Implementation

### New File: scripts/lib/hooks.sh

```bash
#!/bin/bash
# Hook execution utilities

HOOKS_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agent-pipelines"
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
  export PIPELINE_SESSION="$SESSION"
  export PIPELINE_TYPE="$PIPELINE_TYPE"
  export PIPELINE_ITERATION="$CURRENT_ITERATION"
  export PIPELINE_MAX_ITERATIONS="$MAX_ITERATIONS"
  export PIPELINE_STATUS="$STATUS"
  export PIPELINE_PROGRESS_FILE="$PROGRESS_FILE"
  export PIPELINE_STATE_FILE="$STATE_FILE"
  export PIPELINE_DURATION="$DURATION"

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
  json_get "$STAGE_CONFIG" ".hooks.$hook_name" ""
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

### Configuration (~/.config/agent-pipelines/webhooks.yaml)

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
3. Support loop-specific hooks in `stage.yaml`
4. Test with simple echo hooks

### Phase 2: Global Hooks
1. Support `~/.config/agent-pipelines/hooks.sh`
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

---

# Advanced Hook Capabilities

> The sections below expand the hook system to support production-grade, long-running pipelines
> that can run for days with proper orchestration, human oversight, and quality gates.

## Design Philosophy

Following [Claude Code's hook pattern](https://code.claude.com/docs/en/hooks):
- **Event-driven**: Hooks fire at specific lifecycle moments
- **Non-blocking by default**: Standard hooks don't pause execution
- **Blocking when needed**: Special `await` hooks pause and wait for responses
- **Composable**: Hooks can spawn pipelines, call webhooks, or run arbitrary code

Two types of hooks:
1. **Fire-and-forget** (default): Notification, logging, backups - execution continues immediately
2. **Blocking/await**: Wait for a response before continuing - for approvals, spawned pipelines, external systems

## Extended Hook Points

| Hook | When | Type | Use Cases |
|------|------|------|-----------|
| `on_session_start` | Before first iteration | fire-and-forget | Initialize resources, notifications |
| `on_iteration_start` | Before each Claude call | fire-and-forget | Logging, prerequisite checks |
| `on_iteration_complete` | After each successful iteration | fire-and-forget | Backups, metrics |
| `on_stage_complete` | When a pipeline stage finishes | fire-and-forget | Stage transition logging |
| `on_session_complete` | When pipeline finishes | fire-and-forget | Completion notifications |
| `on_error` | When iteration fails | fire-and-forget | Error alerts |
| `on_checkpoint` | Every N iterations (configurable) | **blocking** | Quality gates, spawned pipelines |
| `on_approval_required` | When human approval needed | **blocking** | Human-in-the-loop decisions |

## Nested Pipelines (spawn)

A pipeline can spawn another pipeline, wait for it to complete, and receive its outputs.

### Configuration

```yaml
name: work-with-review
description: Work pipeline with periodic code review

completion: beads-empty

# Spawn a review pipeline every 10 iterations
checkpoints:
  every: 10
  spawn:
    pipeline: code-review
    inputs:
      files_changed: "${CHANGED_FILES}"
      session: "${SESSION}"
    on_complete: merge  # merge | replace | ignore

hooks:
  on_checkpoint: spawn  # special keyword triggers spawn config
```

### Code Review Pipeline Example

```yaml
# scripts/pipelines/code-review.yaml
name: code-review
description: Review code and fix issues until clean

stages:
  - name: review
    loop: compound-review
    completion: plateau
    max_iterations: 5

  - name: fix
    loop: fix-issues
    completion: beads-empty
    inputs: "${INPUTS.review}"
```

### How Spawn Works

1. Parent pipeline reaches checkpoint (iteration 10, 20, 30...)
2. Engine pauses parent, saves state to `state.json`
3. Engine spawns child pipeline in same session directory under `children/{checkpoint-N}/`
4. Child runs to completion (plateau, beads-empty, etc.)
5. Child outputs written to `children/{checkpoint-N}/output.json`
6. Parent resumes, child outputs available as `${CHILD_OUTPUT}`

### State Isolation

Child pipelines are **isolated with explicit handoff**:
- Child gets its own progress file: `children/{checkpoint-N}/progress.md`
- Parent passes explicit inputs via `spawn.inputs`
- Child returns explicit outputs via its completion
- No implicit state sharing (clean boundaries, predictable behavior)

```
.claude/pipeline-runs/my-session/
├── state.json              # Parent state (paused at checkpoint)
├── progress-my-session.md  # Parent progress
├── children/
│   ├── checkpoint-10/
│   │   ├── state.json      # Child state
│   │   ├── progress.md     # Child progress
│   │   └── output.json     # Child output (returned to parent)
│   └── checkpoint-20/
│       └── ...
```

### Spawn Implementation

```bash
# scripts/lib/spawn.sh

spawn_pipeline() {
  local parent_session=$1
  local checkpoint=$2
  local pipeline_config=$3
  local inputs=$4

  local child_dir="$SESSION_DIR/children/checkpoint-$checkpoint"
  mkdir -p "$child_dir"

  # Save parent state
  update_state ".status" "paused"
  update_state ".paused_at" "$checkpoint"
  update_state ".child_session" "$child_dir"

  # Write inputs for child
  echo "$inputs" > "$child_dir/inputs.json"

  # Run child pipeline (blocking)
  ./scripts/engine.sh \
    --session-dir "$child_dir" \
    --pipeline "$pipeline_config" \
    --inputs "$child_dir/inputs.json"

  local child_exit=$?

  # Read child output
  if [ -f "$child_dir/output.json" ]; then
    export CHILD_OUTPUT=$(cat "$child_dir/output.json")
  fi

  # Resume parent
  update_state ".status" "running"
  update_state ".child_completed" "$checkpoint"

  return $child_exit
}
```

## Blocking Hooks (await)

Hooks that pause execution and wait for a response.

### Types of Await Hooks

1. **await_webhook**: Send HTTP request, wait for callback
2. **await_input**: Wait for file/stdin input
3. **await_pipeline**: Spawn pipeline, wait for completion (see above)

### Await Webhook

```yaml
hooks:
  on_approval_required:
    type: await_webhook
    send:
      url: "${APPROVAL_WEBHOOK_URL}"
      method: POST
      body:
        session: "${SESSION}"
        iteration: "${ITERATION}"
        summary: "${PROGRESS_SUMMARY}"
        approve_url: "${CALLBACK_URL}/approve"
        reject_url: "${CALLBACK_URL}/reject"
    receive:
      port: 8765  # Local server listens for callback
      timeout: 86400  # 24 hours
      timeout_action: continue  # continue | abort
    response_var: APPROVAL_RESPONSE
```

### How Await Webhook Works

1. Hook fires, sends outbound webhook with context
2. Engine starts minimal HTTP server on `receive.port`
3. Engine pauses, waiting for callback
4. External system (Slack bot, web UI, etc.) calls back to approve/reject
5. Response captured in `APPROVAL_RESPONSE` environment variable
6. Pipeline continues or aborts based on response

### Callback Server

```bash
# scripts/lib/await.sh

await_webhook_response() {
  local port=$1
  local timeout=$2
  local response_file="$SESSION_DIR/await-response.json"

  # Start simple HTTP server
  timeout "$timeout" nc -l "$port" > "$response_file" &
  local server_pid=$!

  log_info "Waiting for callback on port $port (timeout: ${timeout}s)"

  # Wait for response or timeout
  wait $server_pid
  local exit_code=$?

  if [ $exit_code -eq 124 ]; then
    log_warn "Await timed out after ${timeout}s"
    return 1
  fi

  # Parse response
  if [ -f "$response_file" ]; then
    export APPROVAL_RESPONSE=$(cat "$response_file" | parse_http_body)
    return 0
  fi

  return 1
}
```

## Human-in-the-Loop Patterns

### Pattern 1: Plan Approval

Run a planning pipeline, notify human, wait for approval before execution.

```yaml
# scripts/pipelines/plan-then-work.yaml
name: plan-then-work
description: Plan with human approval before work

stages:
  - name: plan
    loop: improve-plan
    completion: plateau

  - name: approval
    type: await  # Special stage type
    webhook:
      send:
        url: "${SLACK_WEBHOOK}"
        body:
          text: "Plan ready for review"
          plan_url: "file://${PROGRESS_FILE}"
          actions:
            - type: button
              text: "Approve"
              url: "${CALLBACK_URL}?action=approve"
            - type: button
              text: "Reject"
              url: "${CALLBACK_URL}?action=reject"
      receive:
        timeout: 86400
        timeout_action: abort

  - name: work
    loop: work
    completion: beads-empty
    # Only runs if approval stage succeeds
```

### Pattern 2: Periodic Check-ins

Long-running work with human oversight every N tasks.

```yaml
name: supervised-work
description: Work with human check-ins

completion: beads-empty

checkpoints:
  every: 10
  notify:
    url: "${SLACK_WEBHOOK}"
    message: "Completed ${ITERATION} iterations. ${REMAINING} beads remaining."
  await:
    enabled: true  # Wait for acknowledgment
    timeout: 3600  # 1 hour
    timeout_action: continue  # Keep going if no response
```

### Pattern 3: Quality Gate

Run quality checks, require human decision on failures.

```yaml
checkpoints:
  every: 10
  spawn:
    pipeline: quality-check
  on_failure:
    type: await_webhook
    send:
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Quality check failed"
        errors: "${CHILD_OUTPUT.errors}"
        actions:
          - text: "Fix and Continue"
            url: "${CALLBACK_URL}?action=fix"
          - text: "Ignore and Continue"
            url: "${CALLBACK_URL}?action=ignore"
          - text: "Abort Pipeline"
            url: "${CALLBACK_URL}?action=abort"
```

## Callback Server Architecture

For production use, the simple `nc` listener won't suffice. Options:

### Option 1: Built-in Minimal Server

```bash
# scripts/lib/callback-server.sh

start_callback_server() {
  local port=$1
  local session=$2

  # Use Python's built-in HTTP server
  python3 -c "
import http.server
import json
import os

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)

        # Write response to file for shell to read
        with open('$SESSION_DIR/callback-response.json', 'w') as f:
            f.write(body.decode())

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')

        # Shutdown after receiving callback
        os._exit(0)

http.server.HTTPServer(('', $port), Handler).serve_forever()
" &

  echo $! > "$SESSION_DIR/callback-server.pid"
}
```

### Option 2: External Webhook Relay

For firewalled environments, use a relay service:

```yaml
# ~/.config/agent-pipelines/webhooks.yaml
relay:
  provider: cloudflare-tunnel  # or ngrok, localtunnel
  auth_token: "${CLOUDFLARE_TOKEN}"
```

### Option 3: Polling-based (Simplest)

Instead of waiting for callbacks, poll an endpoint:

```yaml
hooks:
  on_approval_required:
    type: await_poll
    poll:
      url: "${APPROVAL_API}/status/${SESSION}"
      interval: 30  # seconds
      timeout: 86400
      success_when: ".status == 'approved'"
      abort_when: ".status == 'rejected'"
```

## Implementation Phases (Extended)

### Phase 5: Blocking Hooks Infrastructure
1. Create `scripts/lib/await.sh` with await primitives
2. Add `await_webhook` hook type
3. Implement simple callback server
4. Add `await_poll` as simpler alternative
5. Test with manual curl callbacks

### Phase 6: Nested Pipelines
1. Create `scripts/lib/spawn.sh`
2. Add checkpoint configuration to stage.yaml schema
3. Implement child session directory structure
4. Add `spawn` as checkpoint action
5. Test with code-review example

### Phase 7: Human-in-the-Loop Patterns
1. Create approval stage type
2. Build Slack integration for interactive approvals
3. Add web UI for approval management (optional)
4. Document patterns with examples

### Phase 8: Production Hardening
1. Add proper HTTP server (not nc)
2. Implement webhook relay options
3. Add retry logic for failed callbacks
4. Security audit of callback handling

## Extended Success Criteria

- [ ] Nested pipelines spawn and return outputs correctly
- [ ] Parent pipeline resumes from correct state after child completes
- [ ] Blocking webhooks pause execution and resume on callback
- [ ] Timeout behavior works correctly (continue/abort)
- [ ] Human approval flow works end-to-end with Slack
- [ ] Polling-based await works as fallback
- [ ] Callback server handles concurrent requests safely
- [ ] Child pipeline failures propagate to parent appropriately

## Security Considerations (Extended)

1. **Callback server exposure**: Only bind to localhost by default; use relay for external access
2. **Callback authentication**: Include session-specific token in callback URL to prevent spoofing
3. **Input validation**: Sanitize all data received from callbacks before use
4. **Timeout limits**: Cap maximum await time to prevent indefinite hangs
5. **Child pipeline isolation**: Children can't access parent's secrets unless explicitly passed

## Example: Full Production Pipeline

```yaml
# scripts/pipelines/production-work.yaml
name: production-work
description: Full production pipeline with reviews and approvals

stages:
  - name: plan
    loop: improve-plan
    completion: plateau
    max_iterations: 5

  - name: plan-approval
    type: await
    webhook:
      send:
        url: "${SLACK_WEBHOOK}"
        body:
          text: ":memo: Plan ready for ${SESSION}"
          blocks:
            - type: section
              text: "Review the plan and approve to continue"
            - type: actions
              elements:
                - type: button
                  text: "Approve"
                  style: primary
                  url: "${CALLBACK_URL}?approve=true"
                - type: button
                  text: "Reject"
                  style: danger
                  url: "${CALLBACK_URL}?approve=false"
      receive:
        timeout: 86400
        timeout_action: abort

  - name: work
    loop: work
    completion: beads-empty
    max_iterations: 50
    checkpoints:
      every: 10
      spawn:
        pipeline: code-review
      notify:
        url: "${SLACK_WEBHOOK}"
        message: ":hammer: ${SESSION}: ${ITERATION}/50 iterations, ${REMAINING} beads"

  - name: final-review
    type: await
    webhook:
      send:
        url: "${SLACK_WEBHOOK}"
        body:
          text: ":white_check_mark: ${SESSION} complete - final review"

# Total: Plan (5 iter) → Approval → Work (50 iter, reviews every 10) → Final Review
# Can run for days with human oversight at key points
```
