---
name: work
description: Spawn Codex in tmux (fire-and-forget). Use /agent-pipelines:work to invoke.
---

<objective>
Spawn a Codex agent in a background tmux session. This is a LAUNCHER - it does NOT do any work itself. Codex runs autonomously in the background.

**Invoke as:** `/agent-pipelines:work <task>`
</objective>

<critical_behavior>
**THIS SKILL LAUNCHES A COMMAND. IT DOES NOT IMPLEMENT ANYTHING.**

Your ONLY job is to:
1. Parse what the user wants done
2. Run `./scripts/run.sh codex-work ...` to spawn Codex
3. Confirm it started

DO NOT read files, write code, or "do the work." Codex does that in tmux.
</critical_behavior>

<usage>
```
/work implement the auth module from docs/plans/auth.md
/work fix the failing tests in src/api/
/work add dark mode support, 10 iterations
/work beads-123 beads-124 beads-125
```
</usage>

<intake>
Parse from user input:
- **instructions**: What to implement (required)
- **iterations**: Number like "10 iterations" or "5 runs" (default: 1)
- **session**: Explicit name if given, otherwise generate from timestamp

## Examples

| Input | Session | Iterations | Context |
|-------|---------|------------|---------|
| `implement auth from docs/plan.md` | work-HHMM | 1 | `Implement auth from docs/plan.md` |
| `fix tests, 10 iterations` | work-HHMM | 10 | `fix tests` |
| `my-feature add dark mode` | my-feature | 1 | `add dark mode` |
</intake>

<routing>
**All paths lead to `workflows/launch.md`**

If user input is empty, ask what they want Codex to work on. Then go to launch.md.
</routing>

<success_criteria>
- [ ] Parsed user intent into session/iterations/context
- [ ] Ran `./scripts/run.sh codex-work` command
- [ ] Brief confirmation: "Deployed: pipeline-{session}"
- [ ] Move on - ask "What's next?" or wait for user
</success_criteria>
