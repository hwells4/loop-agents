---
description: Spawn Codex in tmux (fire-and-forget). Use /agent-pipelines:work to invoke.
---

# /agent-pipelines:work

Spawn a Codex agent to implement something. You give instructions, Codex works in the background.

**Invoke as:** `/agent-pipelines:work <task>` (not `/work` which may conflict with other plugins)

**YOU ARE A LAUNCHER. DO NOT IMPLEMENT ANYTHING. JUST RUN THE COMMAND.**

## When Invoked

### If user provided instructions:

Parse from their input:
- **instructions**: Everything they said (what to implement)
- **iterations**: Look for "N iterations" or "N runs" (default: 1)
- **session**: If they gave an explicit name, use it. Otherwise generate `work-$(date +%H%M)`

Then skip to "Run the Command" below.

### If user provided nothing:

Ask: **"What should Codex implement?"**

They can provide:
- A task description ("add dark mode support")
- A file path ("implement docs/plans/auth.md")
- Bead IDs ("beads-001 beads-002")

Then ask: **"How many iterations?"** (default: 1)

## Run the Command

**Generate session name if needed:**
```bash
date +%H%M
```
Use output as: `work-{output}` (e.g., `work-1432`)

**Run this command immediately:**
```bash
./scripts/run.sh codex-work {session} {iterations} --context="{instructions}"
```

**If they mentioned a file to implement from, add --input:**
```bash
./scripts/run.sh codex-work {session} {iterations} --input={file} --context="Implement the plan in the input file"
```

## After Running

Brief confirmation, then move on:
```
Deployed: pipeline-{session}
```

That's it. Don't linger. Ask "What's next?" or wait for user's next request.

Only show monitor commands if user asks how to check on it.

## Examples

**User:** `/work implement the auth module from docs/plans/auth.md`
**Action:** Run `./scripts/run.sh codex-work work-1432 1 --input=docs/plans/auth.md --context="Implement the auth module"`
**Response:** "Deployed: pipeline-work-1432"

**User:** `/work fix failing tests, 10 iterations`
**Action:** Run `./scripts/run.sh codex-work work-1432 10 --context="fix failing tests"`
**Response:** "Deployed: pipeline-work-1432 (10 iterations)"

**User:** `/work my-feature add user preferences`
**Action:** Run `./scripts/run.sh codex-work my-feature 1 --context="add user preferences"`
**Response:** "Deployed: pipeline-my-feature"

**User:** `/work`
**Action:** Ask what to implement, then run the command

## Critical Reminder

**DO NOT:**
- Read files mentioned in the instructions
- Write code
- "Help implement" anything
- Do any work yourself

**DO:**
- Parse the input
- Run `./scripts/run.sh codex-work ...`
- Confirm it started

Codex handles everything in tmux.

---

**Invoke as:** `/agent-pipelines:work $ARGUMENTS`
