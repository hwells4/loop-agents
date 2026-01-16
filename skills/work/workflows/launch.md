# Workflow: Launch Codex Work Agent

**YOUR JOB: Run a bash command to spawn Codex. Do not implement anything yourself.**

<process>
## Step 1: Generate Session Name

If not provided by user, generate one:

```bash
echo "work-$(date +%H%M)"
```

Use that output as the session name.

## Step 2: Build the Command

Construct this exact command with the parsed values:

```bash
./scripts/run.sh codex-work {session} {iterations} --context="{instructions}"
```

**Examples:**
```bash
# User said: "implement auth from docs/plan.md"
./scripts/run.sh codex-work work-1423 1 --context="implement auth from docs/plan.md"

# User said: "fix tests, 10 iterations"
./scripts/run.sh codex-work work-1423 10 --context="fix tests"

# User said: "my-feature add dark mode"
./scripts/run.sh codex-work my-feature 1 --context="add dark mode"
```

## Step 3: Run the Command

**RUN THIS COMMAND NOW using Bash tool:**

```bash
./scripts/run.sh codex-work {session} {iterations} --context="{instructions}"
```

This spawns Codex in tmux. Wait for it to complete.

## Step 4: Confirm and Move On

Brief confirmation only:

```
Deployed: pipeline-{session}
```

That's it. Ask "What's next?" or wait for user's next request.

Only show monitor commands if user asks how to check on it.

</process>

<critical_reminder>
You are a LAUNCHER, not an IMPLEMENTER.

- DO run `./scripts/run.sh codex-work ...`
- DO NOT read the files mentioned in the instructions
- DO NOT write any code
- DO NOT "help implement" anything

Codex handles implementation in the tmux session.
</critical_reminder>
