<overview>
Complete multi-phase workflow patterns for coordinated multi-agent development using NTM and Agent Mail. Covers planning, implementation, review, and integration phases with specific prompts and coordination protocols.
</overview>

<planning_phase>

## Phase 1: Planning

**Goal:** Create detailed implementation plan before any code is written.

**Agent assignment:**
- Claude agents: Analysis and planning
- Codex agents: Standby, reviewing plan drafts

**NTM + Agent Mail flow:**

```bash
# 1. Spawn planning agents
ntm spawn feature-auth --cc=2

# 2. Send planning prompt
ntm send feature-auth --cc "
## Planning Phase - bd-123

PROJECT: $(pwd)
TASK: Implement user authentication

### Setup
1. register_agent(project_key='$(pwd)', program='claude-code', model='opus')
2. fetch_inbox(...) and check for prior context

### Your Task
1. Reserve planning files:
   file_reservation_paths(..., paths=['docs/plans/auth-plan.md'], reason='bd-123')

2. Create comprehensive plan covering:
   - Architecture decisions
   - File structure
   - API endpoints
   - Data models
   - Security considerations
   - Test strategy

3. Write plan to docs/plans/auth-plan.md

4. When complete, announce:
   send_message(...,
     to=['ALL'],
     subject='[bd-123] Planning complete - ready for review',
     thread_id='bd-123',
     ack_required=true
   )

5. Release reservation and wait for feedback
"
```

**Expected outputs:**
- `docs/plans/auth-plan.md` - Detailed plan
- Agent-mail thread `bd-123` with planning discussions

</planning_phase>

<implementation_phase>

## Phase 2: Implementation

**Goal:** Implement plan with coordinated file ownership.

**Agent assignment:**
- Claude agents: Code review, guidance
- Codex agents: Primary implementation

**NTM + Agent Mail flow:**

```bash
# 1. Add implementation agents
ntm add feature-auth --cod=3

# 2. Assign file areas to avoid conflicts
ntm send feature-auth --cod "
## Implementation Phase - bd-123

PROJECT: $(pwd)
PLAN: docs/plans/auth-plan.md

### Setup
1. register_agent(project_key='$(pwd)', program='codex', model='gpt-5.2-codex')
2. fetch_inbox(...) - read planning thread
3. Read the plan: docs/plans/auth-plan.md

### File Ownership (CRITICAL)
Agent cod_1: src/auth/login.py, src/auth/logout.py
Agent cod_2: src/auth/register.py, src/auth/password.py
Agent cod_3: src/models/user.py, src/db/migrations/

### Your Task
1. Reserve YOUR files only:
   file_reservation_paths(..., paths=['your-assigned-files'], reason='bd-123', exclusive=true)

2. If conflicts, message the holder:
   send_message(..., to=['holder-name'], subject='[bd-123] File conflict', thread_id='bd-123')

3. Implement according to plan

4. When your part done:
   send_message(..., subject='[bd-123] {your-area} implemented', thread_id='bd-123')

5. Release reservations

### Coordination
- Check inbox every 10 minutes
- Reply in thread bd-123 for questions
- Wait for Claude review before merging
"

# 3. Claude agents provide guidance
ntm send feature-auth --cc "
## Implementation Support - bd-123

Monitor Codex agents implementing the plan.

1. Check inbox for questions
2. Review code snippets shared in thread
3. Provide guidance on architecture questions
4. Flag issues early:
   send_message(..., importance='high', ack_required=true)
"
```

**Expected outputs:**
- Implemented files per assignment
- Agent-mail thread with coordination messages
- No file conflicts (reservations prevent)

</implementation_phase>

<review_phase>

## Phase 3: Review

**Goal:** Validate implementation against plan, find bugs.

**Agent assignment:**
- Fresh Claude agents: Code review
- Original Codex agents: Bug fixes

**NTM + Agent Mail flow:**

```bash
# 1. Add review agents
ntm add feature-auth --cc=2

# 2. Assign review task
ntm send feature-auth --cc "
## Review Phase - bd-123

PROJECT: $(pwd)
PLAN: docs/plans/auth-plan.md

### Setup
1. register_agent(..., task_description='Code review for auth feature')
2. fetch_inbox(...) - read implementation thread

### Your Task
1. Review implemented code against plan
2. Check for:
   - Security issues
   - Missing error handling
   - Test coverage gaps
   - Deviation from plan

3. For each issue found:
   send_message(...,
     to=['implementer-agent-name'],
     subject='[bd-123] Review: {issue-summary}',
     thread_id='bd-123',
     importance='high' if security else 'normal'
   )

4. When review complete:
   send_message(...,
     subject='[bd-123] Review complete - {pass/needs-fixes}',
     thread_id='bd-123'
   )
"

# 3. Codex agents fix issues
ntm send feature-auth --cod "
## Fix Review Issues - bd-123

Check inbox for review feedback.

For each issue:
1. Reserve the file
2. Fix the issue
3. Reply in thread: 'Fixed: {issue-summary}'
4. Release reservation
"
```

**Expected outputs:**
- Review comments in agent-mail thread
- Fixed issues with confirmation messages

</review_phase>

<integration_phase>

## Phase 4: Integration

**Goal:** Merge all work, run tests, finalize.

**Agent assignment:**
- One lead agent (Claude): Integration coordination
- All agents: Final verification

**NTM + Agent Mail flow:**

```bash
# 1. Assign integration lead
ntm send feature-auth --cc "
## Integration Phase - bd-123

You are the integration lead.

### Tasks
1. Ensure all agents have released file reservations:
   - Check: ntm locks feature-auth
   - Message any holders to release

2. Run full test suite

3. If tests fail:
   send_message(...,
     to=['relevant-agent'],
     subject='[bd-123] Test failure: {test-name}',
     thread_id='bd-123',
     ack_required=true
   )

4. When all tests pass:
   send_message(...,
     to=['ALL'],
     subject='[bd-123] COMPLETE - Ready for merge',
     thread_id='bd-123',
     importance='high'
   )

5. Summarize the work:
   summarize_thread(project_key, thread_id='bd-123')
"
```

**Expected outputs:**
- All tests passing
- Thread summary documenting the work
- Clean git history ready for merge

</integration_phase>

<complete_workflow_script>

## Complete Multi-Phase Workflow Script

```bash
#!/bin/bash
# multi-phase-workflow.sh

SESSION="feature-$1"
TASK_ID="$2"
PROJECT=$(pwd)

# Phase 1: Planning
echo "=== PLANNING PHASE ==="
ntm spawn $SESSION --cc=2
ntm send $SESSION --all "$(cat <<EOF
Register with agent-mail: register_agent(project_key='$PROJECT', program='claude-code', model='opus')
Task: $TASK_ID
Phase: Planning
Create detailed plan in docs/plans/${TASK_ID}-plan.md
Announce when ready via agent-mail thread $TASK_ID
EOF
)"

read -p "Press enter when planning complete..."

# Phase 2: Implementation
echo "=== IMPLEMENTATION PHASE ==="
ntm add $SESSION --cod=3
ntm send $SESSION --cod "$(cat <<EOF
Register with agent-mail: register_agent(project_key='$PROJECT', program='codex', model='gpt-5.2-codex')
Task: $TASK_ID
Phase: Implementation
Read plan: docs/plans/${TASK_ID}-plan.md
Reserve files before editing (exclusive=true, reason='$TASK_ID')
Coordinate via agent-mail thread $TASK_ID
EOF
)"

read -p "Press enter when implementation complete..."

# Phase 3: Review
echo "=== REVIEW PHASE ==="
ntm add $SESSION --cc=1
ntm send $SESSION --cc "$(cat <<EOF
Task: $TASK_ID
Phase: Review
Review implementation against plan
Post issues to agent-mail thread $TASK_ID
EOF
)"

read -p "Press enter when review complete..."

# Phase 4: Integration
echo "=== INTEGRATION PHASE ==="
ntm send $SESSION --cc "$(cat <<EOF
Task: $TASK_ID
Phase: Integration
Ensure all reservations released
Run tests
Summarize thread: summarize_thread(project_key='$PROJECT', thread_id='$TASK_ID')
EOF
)"

echo "=== WORKFLOW COMPLETE ==="
ntm save $SESSION -o ~/outputs/$SESSION/
```

Usage:
```bash
./multi-phase-workflow.sh auth bd-123
```

</complete_workflow_script>

<agent_mail_thread_structure>

## Recommended Thread Structure

For task `bd-123`:

```
Thread: bd-123

[1] GreenCastle (Claude): [bd-123] Planning started
    - Reserving docs/plans/auth-plan.md

[2] GreenCastle (Claude): [bd-123] Planning complete - ready for review
    - Plan written to docs/plans/auth-plan.md
    - Attachments: plan-diagram.png

[3] BlueLake (Codex): [bd-123] Starting implementation
    - Reserving src/auth/login.py, src/auth/logout.py

[4] RedMountain (Codex): [bd-123] Starting implementation
    - Reserving src/auth/register.py

[5] BlueLake (Codex): [bd-123] Login/logout implemented
    - Releasing reservations

[6] SilverRiver (Claude): [bd-123] Review: Security issue in login.py
    - importance: high, ack_required: true

[7] BlueLake (Codex): Re: [bd-123] Review: Security issue in login.py
    - Fixed: Added rate limiting

[8] GreenCastle (Claude): [bd-123] COMPLETE - All tests passing
    - Thread summary attached
```

</agent_mail_thread_structure>

<coordination_best_practices>

## Best Practices

**File reservations:**
- Always use `exclusive=true` for files you're editing
- Use `reason=task-id` to link reservations to task
- Release immediately when done
- Don't reserve files you're only reading

**Messaging:**
- Use consistent `thread_id` for entire task
- Subject format: `[task-id] {action/status}`
- Set `ack_required=true` for blocking issues
- Check inbox at start of each work session

**Phase transitions:**
- Wait for explicit "phase complete" messages
- Don't start implementation until plan is approved
- Don't merge until review is complete

**Conflict resolution:**
- If reservation conflicts, message the holder first
- If no response in 15 min, work on different files
- Human overseer can force-release stale locks

</coordination_best_practices>
