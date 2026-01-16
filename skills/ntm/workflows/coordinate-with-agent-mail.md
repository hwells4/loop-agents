# Workflow: Coordinate Agents with Agent Mail

<required_reading>
**Read these reference files NOW:**
1. references/agent-mail.md (complete MCP tools reference)
2. references/patterns.md (multi-agent patterns)
</required_reading>

<process>

## Step 1: Start Agent Mail Server

**Option A: Background process (recommended for swarms)**
```bash
# One-line install (if not installed)
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh" | bash -s -- --yes

# Start in background
am &
AGENT_MAIL_PID=$!

# Or with nohup for persistence
nohup am > /tmp/agent-mail.log 2>&1 &
```

**Option B: Dedicated tmux pane**
```bash
# Create agent-mail in its own tmux session
tmux new-session -d -s agent-mail "am"

# Later, to check logs
tmux attach -t agent-mail
```

**Option C: Alongside NTM session**
```bash
# Start agent-mail, then spawn NTM
am &
sleep 2  # Wait for server to start
ntm spawn myproject --cc=3 --cod=2
```

Verify running:
```bash
curl http://localhost:8765/mcp/
```

**Note:** No authentication token needed for local development. Server runs on port 8765 by default.

## Step 2: Spawn NTM Session with Agent Mail Context

When spawning agents, include agent-mail instructions in the initial prompt:

```bash
ntm spawn myproject --cc=3 --cod=2
```

Then send coordination prompt:

```bash
ntm send myproject --all "
You have access to the agent-mail MCP for coordination with other agents.

PROJECT: $(pwd)

ON STARTUP:
1. Register yourself: register_agent(project_key='$(pwd)', program='claude-code', model='opus')
2. Check inbox: fetch_inbox(project_key, your_agent_name)
3. Note your agent name (e.g., 'GreenCastle')

BEFORE EDITING FILES:
1. Reserve files: file_reservation_paths(project_key, your_name, ['path/to/files/**'], ttl_seconds=1800, exclusive=true, reason='task-id')
2. If conflicts returned, message the holder or work on different files

COMMUNICATION:
- Announce work: send_message(..., thread_id='task-id', importance='high')
- Check inbox periodically
- Reply in threads to coordinate

WHEN DONE:
- Release reservations: release_file_reservations(project_key, your_name)
- Send completion message to thread
"
```

## Step 3: Assign Specific Tasks

**To Claude agents (planning/analysis):**
```bash
ntm send myproject --cc "
Task: bd-123 - Implement user authentication

1. Register with agent-mail if not done
2. Reserve: file_reservation_paths(..., paths=['docs/auth-plan.md'], reason='bd-123')
3. Create detailed implementation plan in docs/auth-plan.md
4. Message Codex agents when plan is ready:
   send_message(..., to=['ALL'], subject='[bd-123] Plan ready', thread_id='bd-123')
5. Release reservation
"
```

**To Codex agents (implementation):**
```bash
ntm send myproject --cod "
Task: bd-123 - Implement user authentication

1. Register with agent-mail if not done
2. Check inbox for plan from Claude agents
3. When plan ready, reserve implementation files:
   file_reservation_paths(..., paths=['src/auth/**'], reason='bd-123')
4. Implement according to plan
5. Message when done:
   send_message(..., subject='[bd-123] Implementation complete', thread_id='bd-123')
6. Release reservations
"
```

## Step 4: Monitor Coordination

**Check file reservations:**
```bash
ntm locks myproject --all-agents --json
```

**View agent-mail web UI:**
```
http://localhost:8765/mail
```

**Check specific project:**
```
http://localhost:8765/mail/{project-path}
```

## Step 5: Human Overseer Intervention

If agents go off track, send high-priority message:

**Via web UI:**
```
http://localhost:8765/mail/{project}/overseer/compose
```

**Via CLI:**
```bash
# In agent-mail directory
uv run python -m mcp_agent_mail.cli send \
  --project /path/to/project \
  --from "HumanOverseer" \
  --to "GreenCastle,BlueLake" \
  --subject "[URGENT] Stop current work" \
  --body "Please stop and wait for new instructions." \
  --importance urgent \
  --ack-required
```

## Step 6: Collect Results

**Save all outputs:**
```bash
ntm save myproject -o ~/outputs/
```

**Search agent-mail for task thread:**
```
http://localhost:8765/mail/{project}/search?q=thread_id:bd-123
```

**Summarize thread:**
```
summarize_thread(project_key, thread_id="bd-123")
```

</process>

<agent_prompt_template>

## Template: Agent Mail Coordination Prompt

Include this in initial prompts to agents:

```markdown
## Agent Mail Coordination

You have access to the agent-mail MCP server (http://localhost:8765) for coordinating with other agents. No authentication required for local use.

PROJECT_KEY: {absolute_project_path}
TASK_ID: {task_id}

### Startup Sequence
1. register_agent(project_key=PROJECT_KEY, program="claude-code", model="opus")
   → You'll get a memorable name like "GreenCastle" or "BlueFox"
2. fetch_inbox(project_key=PROJECT_KEY, agent_name=YOUR_NAME, include_bodies=true)
3. Acknowledge any urgent messages

### File Editing Protocol
BEFORE editing any file:
1. file_reservation_paths(
     project_key=PROJECT_KEY,
     agent_name=YOUR_NAME,
     paths=["path/to/files/**"],
     ttl_seconds=1800,
     exclusive=true,
     reason=TASK_ID
   )
2. Check response for conflicts
3. If conflicts: message holder or work on different files

AFTER editing:
1. release_file_reservations(project_key=PROJECT_KEY, agent_name=YOUR_NAME)

### Communication Protocol
- Use thread_id=TASK_ID for all messages related to this task
- Check inbox every 10-15 minutes
- Reply in threads, don't start new ones
- Mark importance="high" for blocking issues
- Acknowledge ack_required messages promptly

### Handoff Protocol
When your part is done:
1. Release all file reservations
2. Send completion message:
   send_message(
     project_key=PROJECT_KEY,
     sender_name=YOUR_NAME,
     to=["ALL"],
     subject="[TASK_ID] {phase} complete",
     body_md="Summary of work done...",
     thread_id=TASK_ID
   )
```

</agent_prompt_template>

<swarm_startup_script>

## Complete Swarm Startup Script

```bash
#!/bin/bash
# swarm-with-agent-mail.sh
# Usage: ./swarm-with-agent-mail.sh <session-name> <task-id>

SESSION="${1:-myproject}"
TASK_ID="${2:-task-001}"
PROJECT=$(pwd)

# 1. Start agent-mail server in background
echo "Starting agent-mail server..."
am &
AGENT_MAIL_PID=$!
sleep 2

# Verify agent-mail is running
if ! curl -s http://localhost:8765/mcp/ > /dev/null; then
    echo "ERROR: Agent-mail failed to start"
    exit 1
fi
echo "Agent-mail running on http://localhost:8765 (PID: $AGENT_MAIL_PID)"

# 2. Spawn NTM session with agents
echo "Spawning NTM session: $SESSION"
ntm spawn "$SESSION" --cc=3 --cod=2

# 3. Send coordination setup to all agents
echo "Configuring agents for coordination..."
ntm send "$SESSION" --all "
## Agent Mail Coordination Setup

You have access to agent-mail MCP at http://localhost:8765 (no auth needed).

PROJECT: $PROJECT
TASK: $TASK_ID

### On Startup
1. register_agent(project_key='$PROJECT', program='claude-code', model='opus')
2. fetch_inbox(project_key='$PROJECT', agent_name=YOUR_NAME)

### Before Editing Files
file_reservation_paths(
  project_key='$PROJECT',
  agent_name=YOUR_NAME,
  paths=['files/to/edit/**'],
  ttl_seconds=1800,
  exclusive=true,
  reason='$TASK_ID'
)

### Communication
- Use thread_id='$TASK_ID' for all messages
- Check inbox periodically
- Release reservations when done
"

echo ""
echo "=== Swarm Ready ==="
echo "Session: $SESSION"
echo "Agent-mail: http://localhost:8765/mail"
echo "Dashboard: ntm dashboard $SESSION"
echo ""
echo "To stop: kill $AGENT_MAIL_PID && ntm kill $SESSION -f"
```

</swarm_startup_script>

<success_criteria>

Agent-mail coordination successful when:
- [ ] Agent-mail server running on localhost:8765
- [ ] All agents registered and have unique names
- [ ] File reservations prevent edit conflicts
- [ ] Messages flow in task threads
- [ ] Handoffs happen via messages (not guessing)
- [ ] Human can intervene via overseer
- [ ] Thread summary captures coordination history

</success_criteria>
