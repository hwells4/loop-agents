# Unified Hook System Specification

> A simple, composable hook system for pipeline lifecycle events.

**Status:** Design document (not yet implemented)
**Supersedes:** `lifecycle-hooks-implementation.md`

---

## Core Concept

**One interface. Three action types. Two modes.**

```yaml
hooks:
  {hook_point}:
    - type: shell | webhook | spawn
      await: true | false  # default: false
      when: "condition"    # optional
      # ... type-specific config
```

Every hook point works the same way. Every action type can be blocking or fire-and-forget. Conditions are first-class.

---

## Hook Points

| Hook Point | When It Fires |
|------------|---------------|
| `on_session_start` | Before first iteration |
| `on_iteration_start` | Before each Claude call |
| `on_iteration_complete` | After each successful iteration |
| `on_stage_complete` | When a pipeline stage finishes |
| `on_session_complete` | When pipeline finishes (success or max) |
| `on_error` | When an iteration fails |

---

## Action Types

### 1. Shell

Run arbitrary shell commands.

```yaml
hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/backup-progress.sh ${PROGRESS}"

    - type: shell
      command: "./scripts/run-tests.sh"
      await: true  # Block until tests complete
      on_failure: abort  # abort | continue | retry
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `command` | yes | Shell command to execute |
| `await` | no | Wait for completion (default: false) |
| `timeout` | no | Max seconds to wait (default: 300) |
| `on_failure` | no | What to do if command fails (default: continue) |
| `retries` | no | Number of retry attempts if `on_failure: retry` (default: 3) |
| `retry_delay` | no | Seconds between retries (default: 5) |

**on_failure options:**
- `continue` - Log failure, proceed to next action (default)
- `abort` - Stop pipeline execution
- `retry` - Retry up to `retries` times with `retry_delay` between attempts

### 2. Webhook

Send HTTP requests, optionally wait for callback.

```yaml
hooks:
  on_session_complete:
    # Fire-and-forget notification
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      method: POST
      body:
        text: "Pipeline ${SESSION} completed after ${ITERATION} iterations"

  on_stage_complete:
    # Blocking approval
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      method: POST
      body:
        text: "Plan ready for review"
        actions:
          - label: "Approve"
            callback: "${CALLBACK_URL}?action=approve"
          - label: "Reject"
            callback: "${CALLBACK_URL}?action=reject"
      await: true
      callback_port: 8765
      timeout: 86400  # 24 hours
      on_timeout: abort
      when: "${STAGE} == 'plan'"
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `url` | yes | Webhook URL |
| `method` | no | HTTP method (default: POST) |
| `headers` | no | HTTP headers |
| `body` | no | Request body (JSON) |
| `await` | no | Wait for callback (default: false) |
| `callback_port` | no | Port for callback server (default: 8765) |
| `timeout` | no | Max seconds to wait (default: 3600) |
| `on_timeout` | no | abort \| continue (default: abort) |
| `on_failure` | no | abort \| continue \| retry (default: continue) |
| `retries` | no | Number of retry attempts for send failures (default: 3) |

**Callback Response:**

When `await: true`, the callback server listens for a response. The response body is available as `${HOOK_RESPONSE}` in subsequent actions.

```json
// POST to callback URL
{
  "action": "approve",
  "message": "Looks good, proceed"
}
```

### 3. Spawn

Spawn a child pipeline, optionally wait for completion.

```yaml
hooks:
  on_iteration_complete:
    # Periodic code review
    - type: spawn
      pipeline: code-review
      await: true
      inputs:
        files_changed: "${CHANGED_FILES}"
        parent_session: "${SESSION}"
      when: "${ITERATION} % 10 == 0"

    # Fire-and-forget metrics collection
    - type: spawn
      pipeline: collect-metrics
      inputs:
        session: "${SESSION}"
        iteration: "${ITERATION}"
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `pipeline` | yes | Pipeline name to spawn |
| `inputs` | no | Data passed to child pipeline |
| `await` | no | Wait for child to complete (default: true) |
| `timeout` | no | Max seconds to wait (default: 3600) |
| `on_failure` | no | abort \| continue \| retry (default: continue) |
| `retries` | no | Number of retry attempts if child fails (default: 0) |

**Child Pipeline Isolation:**

- Child runs in `{session_dir}/children/{hook_point}-{iteration}/`
- Child gets its own progress file
- Parent passes explicit inputs via `inputs:`
- Child outputs available as `${SPAWN_OUTPUT}` when awaited

---

## Conditions

Any action can have a `when:` condition. Supports:

- Variable comparison: `"${ITERATION} == 10"`
- Modulo for periodic: `"${ITERATION} % 10 == 0"`
- Stage matching: `"${STAGE} == 'plan'"`
- Status checks: `"${LAST_DECISION} == 'stop'"`
- Boolean logic: `"${ITERATION} > 5 && ${STAGE} == 'work'"`

```yaml
hooks:
  on_iteration_complete:
    # Only on iteration 1
    - type: shell
      command: "./scripts/first-iteration.sh"
      when: "${ITERATION} == 1"

    # Every 10 iterations
    - type: spawn
      pipeline: code-review
      when: "${ITERATION} % 10 == 0"

    # Only during work stage after iteration 5
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Progress update" }
      when: "${STAGE} == 'work' && ${ITERATION} > 5"
```

---

## Environment Variables

All actions receive context via environment:

| Variable | Description |
|----------|-------------|
| `SESSION` | Session name |
| `STAGE` | Current stage name |
| `NEXT_STAGE` | Next stage name (empty if last stage) |
| `ITERATION` | Current iteration (1-based) |
| `MAX_ITERATIONS` | Maximum iterations configured |
| `PROGRESS` | Path to progress file |
| `STATUS` | Path to status.json |
| `CTX` | Path to context.json |
| `LAST_DECISION` | Previous iteration's decision |
| `LAST_HOOK_STATUS` | Previous action's result: `success` or `failed` |
| `CHANGED_FILES` | Files modified this iteration |
| `STAGE_OUTPUTS` | Collected outputs from current stage |
| `ERROR` | Error message (only set in `on_error` hook) |
| `TIMESTAMP` | Current ISO 8601 timestamp |
| `CALLBACK_URL` | Auto-generated callback URL for webhooks |
| `HOOK_RESPONSE` | Response from previous await webhook |
| `SPAWN_OUTPUT` | Output from previous await spawn |

---

## Execution Order

1. Actions execute in order (top to bottom)
2. If `await: true`, execution pauses until action completes
3. If action fails and `on_failure: abort`, pipeline stops
4. If condition `when:` is false, action is skipped
5. Multiple hook points can fire in sequence (e.g., `on_iteration_complete` then `on_stage_complete`)

---

## Configuration Locations

### Per-Stage (stage.yaml)

```yaml
name: work
description: Implementation stage

termination:
  type: queue

hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/backup.sh"
```

### Per-Pipeline (pipeline.yaml)

```yaml
name: full-workflow
description: Complete workflow with approvals

stages:
  - name: plan
    loop: improve-plan
  - name: work
    loop: work

hooks:
  on_stage_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body: { text: "Stage ${STAGE} complete" }
      await: true
      when: "${STAGE} == 'plan'"
```

### Global (~/.config/agent-pipelines/hooks.yaml)

```yaml
# Applied to all pipelines unless disabled
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Pipeline ${SESSION} finished"

  on_error:
    - type: webhook
      url: "${PAGERDUTY_WEBHOOK}"
      body:
        text: "Pipeline ${SESSION} failed: ${ERROR}"
```

### Disable Global Hooks

```yaml
# In stage.yaml or pipeline.yaml
disable_global_hooks: true
```

---

## Common Patterns

### Pattern 1: Notification on Complete

```yaml
hooks:
  on_session_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: ":white_check_mark: ${SESSION} completed in ${ITERATION} iterations"
```

### Pattern 2: Human Approval Gate

```yaml
hooks:
  on_stage_complete:
    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Plan ready for ${SESSION}"
        blocks:
          - type: actions
            elements:
              - type: button
                text: "Approve"
                url: "${CALLBACK_URL}?action=approve"
              - type: button
                text: "Reject"
                url: "${CALLBACK_URL}?action=reject"
      await: true
      timeout: 86400
      on_timeout: abort
      when: "${STAGE} == 'plan'"
```

### Pattern 3: Periodic Code Review

```yaml
hooks:
  on_iteration_complete:
    - type: spawn
      pipeline: code-review
      await: true
      inputs:
        files: "${CHANGED_FILES}"
      when: "${ITERATION} % 10 == 0"
```

### Pattern 4: Quality Gate with Fallback

```yaml
hooks:
  on_iteration_complete:
    - type: shell
      command: "./scripts/run-tests.sh"
      await: true
      on_failure: continue  # Don't abort on test failure

    - type: webhook
      url: "${SLACK_WEBHOOK}"
      body:
        text: "Tests failed - manual review needed"
        actions:
          - label: "Ignore and Continue"
            callback: "${CALLBACK_URL}?action=continue"
          - label: "Abort Pipeline"
            callback: "${CALLBACK_URL}?action=abort"
      await: true
      when: "${LAST_HOOK_STATUS} == 'failed'"
```

### Pattern 5: Backup + Metrics + Notification

```yaml
hooks:
  on_iteration_complete:
    # All fire-and-forget, run in parallel conceptually
    - type: shell
      command: "./scripts/backup-progress.sh"

    - type: shell
      command: "./scripts/collect-metrics.sh"

    - type: webhook
      url: "${METRICS_ENDPOINT}"
      body:
        session: "${SESSION}"
        iteration: "${ITERATION}"
        timestamp: "${TIMESTAMP}"
```

### Pattern 6: Spawn Review Before Final Stage

```yaml
hooks:
  on_stage_complete:
    - type: spawn
      pipeline: comprehensive-review
      await: true
      inputs:
        all_outputs: "${STAGE_OUTPUTS}"
      when: "${NEXT_STAGE} == 'deploy'"
```

---

## Security Considerations

### Callback Server

- **Localhost only by default**: Callback server binds to `127.0.0.1`, not `0.0.0.0`
- **Session tokens**: Each callback URL includes a random session token to prevent spoofing
  ```
  http://localhost:8765/callback?token=a1b2c3d4e5f6
  ```
- **Single-use callbacks**: Token invalidated after first use

### Webhook URLs

- **Secrets**: Webhook URLs often contain auth tokens—never commit to repo
- **Environment variables**: Store in `~/.config/agent-pipelines/secrets.env` or use `${SLACK_WEBHOOK}` from environment
- **Validation**: URLs must be HTTPS in production (HTTP allowed for localhost only)

### Shell Commands

- **No sandboxing**: Shell hooks run with full user permissions
- **Input sanitization**: Variables like `${ERROR}` are escaped before substitution
- **Trusted scripts only**: Only run scripts you control

### Spawn Isolation

- **Child can't access parent secrets**: Unless explicitly passed via `inputs:`
- **Separate working directory**: Children run in isolated subdirectory
- **No implicit state sharing**: Clean boundaries between parent and child

---

## Implementation

### File: scripts/lib/hooks.sh

```bash
#!/bin/bash
# Unified hook execution

execute_hooks() {
  local hook_point=$1
  local hooks_config=$2

  # Get actions for this hook point
  local actions=$(json_get "$hooks_config" ".hooks.$hook_point" "[]")

  # Execute each action
  echo "$actions" | jq -c '.[]' | while read -r action; do
    local action_type=$(echo "$action" | jq -r '.type')
    local condition=$(echo "$action" | jq -r '.when // "true"')

    # Evaluate condition
    if ! eval_condition "$condition"; then
      continue
    fi

    case "$action_type" in
      shell)   execute_shell_action "$action" ;;
      webhook) execute_webhook_action "$action" ;;
      spawn)   execute_spawn_action "$action" ;;
    esac

    local status=$?
    export LAST_HOOK_STATUS=$([[ $status -eq 0 ]] && echo "success" || echo "failed")

    # Handle failure
    if [[ $status -ne 0 ]]; then
      local on_failure=$(echo "$action" | jq -r '.on_failure // "continue"')
      [[ "$on_failure" == "abort" ]] && return 1
    fi
  done
}

execute_shell_action() {
  local action=$1
  local command=$(echo "$action" | jq -r '.command')
  local should_await=$(echo "$action" | jq -r '.await // false')
  local timeout=$(echo "$action" | jq -r '.timeout // 300')

  # Resolve variables in command
  command=$(resolve_variables "$command")

  if [[ "$should_await" == "true" ]]; then
    timeout "$timeout" bash -c "$command"
  else
    bash -c "$command" &
  fi
}

execute_webhook_action() {
  local action=$1
  local url=$(echo "$action" | jq -r '.url')
  local method=$(echo "$action" | jq -r '.method // "POST"')
  local body=$(echo "$action" | jq -c '.body // {}')
  local should_await=$(echo "$action" | jq -r '.await // false')

  # Resolve variables
  url=$(resolve_variables "$url")
  body=$(resolve_variables "$body")

  # Send webhook
  curl -s -X "$method" "$url" \
    -H "Content-Type: application/json" \
    -d "$body"

  # If await, start callback server
  if [[ "$should_await" == "true" ]]; then
    local port=$(echo "$action" | jq -r '.callback_port // 8765')
    local timeout=$(echo "$action" | jq -r '.timeout // 3600')

    await_callback "$port" "$timeout"
  fi
}

execute_spawn_action() {
  local action=$1
  local pipeline=$(echo "$action" | jq -r '.pipeline')
  local inputs=$(echo "$action" | jq -c '.inputs // {}')
  local should_await=$(echo "$action" | jq -r '.await // true')

  local child_dir="$SESSION_DIR/children/${HOOK_POINT}-${ITERATION}"
  mkdir -p "$child_dir"

  # Write inputs for child
  echo "$inputs" | resolve_variables > "$child_dir/inputs.json"

  if [[ "$should_await" == "true" ]]; then
    # Run child and wait
    ./scripts/engine.sh \
      --session-dir "$child_dir" \
      --pipeline "$pipeline" \
      --inputs "$child_dir/inputs.json"

    # Capture output
    if [[ -f "$child_dir/output.json" ]]; then
      export SPAWN_OUTPUT=$(cat "$child_dir/output.json")
    fi
  else
    # Fire and forget
    ./scripts/engine.sh \
      --session-dir "$child_dir" \
      --pipeline "$pipeline" \
      --inputs "$child_dir/inputs.json" &
  fi
}
```

---

## Success Criteria

- [ ] All three action types work (shell, webhook, spawn)
- [ ] Await mode blocks execution correctly
- [ ] Fire-and-forget mode doesn't block
- [ ] Conditions evaluate correctly
- [ ] Variables resolve in all contexts
- [ ] Callback server handles responses
- [ ] Child pipelines spawn and return outputs
- [ ] Global hooks apply unless disabled
- [ ] Hook failures respect on_failure setting
- [ ] Timeouts trigger correctly

---

## Migration from Current Plan

The existing `lifecycle-hooks-implementation.md` concepts map to:

| Old Concept | New Unified Approach |
|-------------|---------------------|
| `checkpoints.every: 10` | `when: "${ITERATION} % 10 == 0"` |
| `checkpoints.spawn.pipeline` | `type: spawn` action |
| `await_webhook` hook type | `type: webhook` with `await: true` |
| `await_poll` hook type | `type: webhook` with polling (future) |
| `on_approval_required` | `type: webhook` with `await: true` |
| Approval stage type | `on_stage_complete` webhook with `await: true` |

One pattern instead of many. Same power, simpler model.
