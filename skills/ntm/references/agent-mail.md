<overview>
MCP Agent Mail is a coordination layer for multiple coding agents - "like gmail for your coding agents." It provides identity management, asynchronous messaging, file reservations (advisory leases), and searchable history. All backed by Git (auditable artifacts) and SQLite (indexing/search).

Repository: https://github.com/Dicklesworthstone/mcp_agent_mail
</overview>

<installation>

**One-line installer:**
```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh" | bash -s -- --yes
```

This automatically:
- Installs Python 3.14 venv via `uv`
- Creates `.env` with bearer token
- Starts HTTP server on port 8765
- Adds `am` shell alias for future launches

**Start server manually:**
```bash
am                                    # Uses installed alias
scripts/run_server_with_token.sh      # Alternative
```

**Change port:**
```bash
uv run python -m mcp_agent_mail.cli config set-port 9000
```

</installation>

<mcp_tools>

## Core MCP Tools

### Identity & Registration

**register_agent** - Create agent identity
```
register_agent(project_key, program, model, name?, task_description?)
```
- `project_key`: Absolute path to project (e.g., `/Users/me/myproject`)
- `program`: Agent type (`claude-code`, `codex`, `gemini`)
- `model`: Model name (`opus`, `gpt-5.2-codex`, etc.)
- `name`: Optional hint; auto-generates memorable adjective+noun (e.g., "GreenCastle")
- Returns: Agent name and profile

**ensure_project** - Create project namespace
```
ensure_project(human_key)
```
- Creates project namespace for all agents, messages, and file reservations
- `human_key`: Absolute path to project directory

### Messaging

**send_message** - Send to other agents
```
send_message(project_key, sender_name, to[], subject, body_md,
             cc?, bcc?, attachment_paths?, importance?,
             ack_required?, thread_id?)
```
- `to[]`: Array of recipient agent names
- `body_md`: GitHub-Flavored Markdown content
- `importance`: `normal`, `high`, `urgent`
- `ack_required`: If true, marks as needing acknowledgment
- `thread_id`: Groups messages in conversation (use task ID like `bd-123`)

**fetch_inbox** - Read messages
```
fetch_inbox(project_key, agent_name, since_ts?, urgent_only?,
            include_bodies?, limit?)
```
- Returns recent messages for agent
- `urgent_only`: Filter to high-priority only
- `include_bodies`: Include full message content

**reply_message** - Reply in thread
```
reply_message(project_key, message_id, sender_name, body_md, ...)
```
- Inherits `thread_id` from original
- Subject prefixed with `Re:`

**acknowledge_message** - Ack high-priority messages
```
acknowledge_message(project_key, agent_name, message_id)
```
- Marks message as acknowledged with timestamp

### File Reservations

**file_reservation_paths** - Claim files before editing
```
file_reservation_paths(project_key, agent_name, paths[], ttl_seconds,
                       exclusive, reason)
```
- `paths[]`: Array of file glob patterns (e.g., `["src/auth/**", "config.json"]`)
- `ttl_seconds`: Lease duration (expires after this time)
- `exclusive`: If true, only this agent can hold exclusive on overlapping paths
- `reason`: Context string (often task ID like `bd-123`)
- Returns: `{ granted: [...], conflicts: [...] }`

**Behavior:**
- Reservations are **advisory** (not hard locks)
- Conflicts are reported but reservations still granted
- Patterns use Git wildmatch semantics
- Expired reservations auto-release

**release_file_reservations** - Release claimed files
```
release_file_reservations(project_key, agent_name, paths? | file_reservation_ids?)
```
- Releases active leases
- If no paths/IDs specified, releases all agent's leases

### Contact Policies

**request_contact** - Request permission to message
```
request_contact(project_key, from_agent, to_agent, reason?, ttl_seconds?)
```
- Creates pending contact link
- Sends intro message to recipient

**respond_contact** - Approve/deny contact
```
respond_contact(project_key, to_agent, from_agent, accept, ttl_seconds?)
```
- Approves or denies contact request

**list_contacts** - List approved contacts
```
list_contacts(project_key, agent_name)
```

**Policy modes:**
- `open`: Accept any messages
- `auto` (default): Allow with context (same thread, overlapping reservations)
- `contacts_only`: Require approved contact first
- `block_all`: Reject all

### Search & Summarization

**search_messages** - Full-text search
```
search_messages(project_key, query, limit?)
```
- FTS5 syntax: `plan AND users NOT legacy`
- Phrases: `"build plan"`
- Prefix: `mig*`
- Fields: `subject:login body:"api key"`

**summarize_thread** - LLM thread summary
```
summarize_thread(project_key, thread_id, include_examples?)
```
- Extracts key points, actions, participants

### Build Slots (Long-Running Tasks)

**acquire_build_slot** - Claim exclusive resource
```
acquire_build_slot(project_key, agent_name, slot, ttl_seconds=3600, exclusive=true)
```
- For dev servers, watchers, long-running processes

**renew_build_slot** - Extend lease
```
renew_build_slot(project_key, agent_name, slot, extend_seconds=1800)
```

**release_build_slot** - Release resource
```
release_build_slot(project_key, agent_name, slot)
```

</mcp_tools>

<agent_registration_flow>

## How Agents Register

**Step 1: Ensure project exists**
```
ensure_project("/absolute/path/to/project")
```

**Step 2: Register agent identity**
```
register_agent(
  project_key="/absolute/path/to/project",
  program="claude-code",
  model="opus",
  task_description="Implementing authentication feature"
)
```

**Returns:**
```json
{
  "agent_name": "GreenCastle",
  "project_key": "/absolute/path/to/project",
  "program": "claude-code",
  "model": "opus",
  "inception_ts": "2025-01-16T10:00:00Z"
}
```

**Names:**
- Auto-generated memorable adjective+noun pairs
- Unique per project
- Can provide `name_hint` for preference

</agent_registration_flow>

<file_reservation_flow>

## How File Reservations Work

**Step 1: Reserve before editing**
```
file_reservation_paths(
  project_key="/path/to/project",
  agent_name="GreenCastle",
  paths=["src/auth/**", "src/models/user.py"],
  ttl_seconds=1800,
  exclusive=true,
  reason="bd-123"
)
```

**Returns:**
```json
{
  "granted": [
    {"id": 1, "pattern": "src/auth/**", "exclusive": true, "expires": "..."},
    {"id": 2, "pattern": "src/models/user.py", "exclusive": true, "expires": "..."}
  ],
  "conflicts": []
}
```

**Step 2: If conflicts exist**
```json
{
  "granted": [...],
  "conflicts": [
    {"pattern": "src/auth/login.py", "holder": "BlueLake", "expires": "..."}
  ]
}
```

Options:
- Work on non-conflicting files
- Message the holder to coordinate
- Wait for their reservation to expire

**Step 3: Release when done**
```
release_file_reservations(
  project_key="/path/to/project",
  agent_name="GreenCastle"
)
```

</file_reservation_flow>

<messaging_flow>

## How Messaging Works

**Step 1: Check inbox on start**
```
fetch_inbox(
  project_key="/path/to/project",
  agent_name="GreenCastle",
  include_bodies=true,
  limit=20
)
```

**Step 2: Send messages to coordinate**
```
send_message(
  project_key="/path/to/project",
  sender_name="GreenCastle",
  to=["BlueLake", "RedMountain"],
  subject="[bd-123] Starting auth implementation",
  body_md="I'm taking the authentication module. Will reserve src/auth/.\n\nPlease avoid those files.",
  thread_id="bd-123",
  importance="high"
)
```

**Step 3: Reply in threads**
```
reply_message(
  project_key="/path/to/project",
  message_id=42,
  sender_name="BlueLake",
  body_md="Got it! I'll focus on tests/ instead."
)
```

**Step 4: Acknowledge urgent messages**
```
acknowledge_message(
  project_key="/path/to/project",
  agent_name="GreenCastle",
  message_id=99
)
```

</messaging_flow>

<pre_commit_guard>

## Pre-Commit Guard

Blocks commits that conflict with other agents' exclusive reservations.

**Install:**
```bash
mcp-agent-mail guard install /path/to/project /path/to/repo --prepush
```

**Requires:**
- `AGENT_NAME` environment variable set

**Bypass (emergency):**
```bash
AGENT_MAIL_BYPASS=1 git commit -m "..."
# or
git commit --no-verify -m "..."
```

**NTM integration:**
```bash
ntm hooks guard install
```

</pre_commit_guard>

<configuration>

## Configuration

Set in `.env` file (all optional):

| Variable | Default | Purpose |
|----------|---------|---------|
| `HTTP_PORT` | `8765` | Server port |
| `HTTP_BEARER_TOKEN` | (none) | Auth token - **optional for localhost** |
| `CONTACT_ENFORCEMENT_ENABLED` | `true` | Enforce contact policies |
| `FILE_RESERVATIONS_ENFORCEMENT_ENABLED` | `true` | Block conflicting writes |
| `FILE_RESERVATION_INACTIVITY_SECONDS` | `1800` | Stale lock threshold |
| `LLM_ENABLED` | `true` | Enable thread summarization |
| `LLM_DEFAULT_MODEL` | `gpt-5-mini` | Summary model |

**Note:** For local development, no authentication is required. The bearer token is only needed for remote/production deployments.

</configuration>

<web_ui>

## Web UI

Access at `http://localhost:8765/mail`:

**Routes:**
- `/mail` - Unified inbox, projects, discovery
- `/mail/{project}` - Project overview, agents, search
- `/mail/{project}/inbox/{agent}` - Single-agent inbox
- `/mail/{project}/message/{id}` - Message detail with thread
- `/mail/{project}/file_reservations` - Active leases
- `/mail/{project}/overseer/compose` - Human operator message sender

**Features:**
- Gmail-style three-pane interface
- Dark mode
- Full-text search
- Thread visualization

</web_ui>

<ntm_integration>

## NTM + Agent Mail Integration

**View file reservations:**
```bash
ntm locks {session} [--all-agents] [--json]
```

**Pre-commit guard:**
```bash
ntm hooks guard install
```

**In agent prompts, include:**
```
You have access to agent-mail MCP for coordination:

1. On startup, register: register_agent(project_key, "claude-code", "opus")
2. Before editing files, reserve: file_reservation_paths(..., exclusive=true)
3. Check inbox periodically: fetch_inbox(...)
4. Announce work in threads: send_message(..., thread_id="bd-123")
5. Release files when done: release_file_reservations(...)

If files are reserved by another agent, message them or work on something else.
```

</ntm_integration>
