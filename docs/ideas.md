# Ideas

## Ideas from ideate-20260110 - Iteration 1

### 1. Debug Mode with Verbose Logging
**Problem:** When loops fail or behave unexpectedly, there's no easy way to trace what's happening. You have to manually inspect state files, progress files, and tmux output separately.

**Solution:** Add a `--debug` flag to `run.sh` that enables:
- Timestamped logging to a dedicated log file per session
- Prints resolved prompts before sending to Claude
- Shows completion strategy decision logic
- Logs all state file mutations
- Outputs Claude's full response (not just parsed fields)

**Why now:** The system is complex enough that debugging is becoming painful. Adding this early prevents hours of future frustration and makes the system more accessible to contributors.

---

### 2. Auto-Resume Crashed Sessions
**Problem:** If Claude crashes mid-iteration (API timeout, network blip, SIGKILL), the session is left in a broken state. The user has to manually figure out where it stopped and restart.

**Solution:** Add crash recovery to `engine.sh`:
- Store "iteration_started" timestamp in state before each iteration
- On startup, check for incomplete iterations (started but not finished)
- Offer to resume from last successful iteration
- Add `--resume` flag to explicitly continue a previous session

**Why now:** As loops get longer (50+ iterations), crashes become more costly. Recovery is essential for production use.

---

### 3. Dry Run Mode
**Problem:** Users can't preview what a loop or pipeline will do before running it. This makes it risky to try new configurations or debug prompt templates.

**Solution:** Add `--dry-run` flag that:
- Resolves all template variables and prints the prompt
- Shows which completion strategy would be used
- Lists expected state/progress file locations
- For pipelines, shows the full stage sequence with models
- Does NOT execute Claude or modify any files

**Why now:** The system has many configuration options now. A dry run lets users safely experiment without consuming Claude credits or polluting their project state.

---

### 4. Manual Approval Gates in Pipelines
**Problem:** Some workflows need human review between stages. For example, you might want to review an improved plan before creating beads from it.

**Solution:** Add a new stage type: `gate`
```yaml
stages:
  - name: improve-plan
    loop: improve-plan
    runs: 5
  - name: review
    type: gate
    message: "Review the plan in docs/plan.md. Continue?"
  - name: create-beads
    loop: refine-beads
    runs: 5
```
Gates pause the pipeline and wait for user confirmation (desktop notification + tmux prompt).

**Why now:** This unlocks more sophisticated human-in-the-loop workflows, which are critical for high-stakes tasks where full autonomy is risky.

---

### 5. Session Cost Tracking
**Problem:** Users have no visibility into how much each loop/pipeline costs. Long-running sessions can burn through significant Claude credits without awareness.

**Solution:** Track and report costs per session:
- Parse Claude CLI output for token usage (if available) or estimate from prompt/response lengths
- Store cumulative tokens in state file
- Show running total in iteration output
- Report final cost summary on completion
- Add `--budget` flag to halt if cost exceeds threshold

**Why now:** As adoption grows and loops get more ambitious, cost visibility becomes essential. Users need to understand the economics before running 50-iteration loops.

---

## Ideas from ideate-20260110 - Iteration 2

### 1. Adaptive Model Selection
**Problem:** All iterations currently use the same model (typically Opus), but many tasks don't need that power. Simple beads, progress updates, and routine iterations waste expensive tokens on Opus when Haiku or Sonnet would suffice.

**Solution:** Add model selection logic to loops:
- Define model tiers in loop config: `models: [haiku, sonnet, opus]`
- Let the completion strategy suggest model for next iteration
- Simple heuristic: start with cheaper model, escalate on failure/complexity
- Allow per-stage model override in pipelines
- Add `--model` flag to force specific model

**Why now:** With Haiku being 50x cheaper than Opus, adaptive selection could cut costs 60-80% on typical workflows without sacrificing quality where it matters.

---

### 2. Automatic Retry with Exponential Backoff
**Problem:** Transient failures (API rate limits, network timeouts, 503s) crash the entire loop. Users must manually restart, losing momentum and potentially context.

**Solution:** Add retry logic to the Claude execution wrapper:
- Retry transient errors (5xx, rate limits, timeouts) up to 3 times
- Exponential backoff: 5s, 15s, 45s delays
- Log retries to state for visibility
- Fail fast on non-transient errors (4xx, auth issues)
- Add `--max-retries` flag to configure

**Why now:** As sessions get longer, probability of hitting a transient failure approaches 100%. This is table stakes for production reliability.

---

### 3. Git Worktree Isolation per Session
**Problem:** Multiple concurrent loops can conflict if they modify the same files. A `work` loop and a `refine` loop running simultaneously can create race conditions and corrupted state.

**Solution:** Optionally run each session in its own git worktree:
- `--isolate` flag creates a new worktree at `.worktrees/{session}/`
- Loop runs entirely within that worktree
- On completion, offer to merge changes back to main branch
- Clean up worktree after merge
- Integrates with existing `git-worktree` skill

**Why now:** Users are starting to run multiple loops concurrently. Without isolation, this is a footgun waiting to happen. Worktrees are the right primitive.

---

### 4. Session Lockfiles
**Problem:** Starting a loop with the same session name while one is already running leads to corrupted state files, race conditions, and unpredictable behavior. There's no guard against this.

**Solution:** Add lockfile management:
- Create `.claude/locks/{session}.lock` on session start
- Check for existing lock before starting
- Store PID and timestamp in lock file
- Detect stale locks (PID no longer running) and clean up
- `--force` flag to override (with warning)

**Why now:** This is a 20-line addition that prevents a class of catastrophic bugs. Easy win that should have been there from day one.

---

### 5. Loop Scaffolding Command
**Problem:** Creating a new stage type requires knowing the exact file structure, required fields in stage.yaml, and template variable syntax. New users copy-paste and make mistakes.

**Solution:** Add `./scripts/run.sh init loop {name}` command:
- Creates `scripts/stages/{name}/` directory
- Generates `stage.yaml` with all fields documented
- Creates `prompt.md` with commented template showing available variables
- Optionally copies from existing loop as starting point
- Validates the result with the loop linter

**Why now:** As the loop library grows, we want users to create custom loops. Scaffolding reduces friction and ensures consistency.

---

## Ideas from ideate-20260110 - Iteration 3

### 1. Iteration Timeout
**Problem:** A single Claude iteration can hang indefinitely—network stall, infinite thinking loop, or API issue. There's no way to bound iteration time, so a stuck iteration blocks the entire session until manual intervention.

**Solution:** Add timeout configuration at multiple levels:
- `timeout: 300` in stage.yaml (default 5 minutes)
- `--timeout 600` CLI override for specific runs
- Wrap Claude execution with `timeout` command
- On timeout: log to state, retry once with same prompt, then skip iteration
- Special handling: save partial output if available before killing

**Why now:** This is a 15-line addition with huge reliability impact. As loops scale to 50+ iterations, timeout is essential. No downsides, only upside.

---

### 2. Loop Linter/Validator
**Problem:** Invalid loop configurations (missing required fields, bad completion strategy names, undefined template variables) only fail at runtime—often deep into a long session. Users waste Claude credits discovering typos.

**Solution:** Add `./scripts/run.sh lint` command:
- Validates all loops in `scripts/stages/`
- Checks required fields: name, description, completion
- Validates completion strategy exists in `lib/completions/`
- Scans prompt.md for undefined template variables
- Validates pipeline stage references
- Add pre-commit hook option
- Exit with error code for CI integration

**Why now:** The loop library is growing. Early validation prevents frustrating runtime failures and makes the system more approachable for new contributors.

---

### 3. Session Lifecycle Hooks
**Problem:** Users can't customize behavior at key session moments. Want to send a Slack message on completion? Run cleanup on failure? Back up progress file between iterations? Currently requires forking the engine.

**Solution:** Add hook points in engine.sh:
- `on_session_start` - Before first iteration
- `on_iteration_start` - Before each Claude call
- `on_iteration_complete` - After each successful iteration
- `on_session_complete` - When loop finishes (success or max reached)
- `on_error` - When iteration fails
Hooks defined in stage.yaml or `~/.config/agent-pipelines/hooks.sh`:
```yaml
hooks:
  on_session_complete: "./scripts/notify-slack.sh ${SESSION}"
```

**Why now:** This is the standard extensibility pattern. Rather than adding every possible feature, let users compose their own behaviors. Unlocks integrations without bloating core.

---

### 4. Webhook Notifications
**Problem:** Long-running loops (30+ iterations) take hours. Users have to manually check tmux or poll state files to know when they're done. No integration with team communication tools.

**Solution:** Add webhook support via lifecycle hooks (see idea #3):
- Built-in templates for Slack, Discord, Microsoft Teams
- `./scripts/run.sh notify setup slack` to configure webhook URL
- Sends: session name, completion status, iteration count, duration, cost (if tracked)
- Optional: send on each iteration for verbose monitoring
- Store webhook URLs in `~/.config/agent-pipelines/webhooks.yaml`

**Why now:** Remote/async work is standard. Developers run loops and context-switch. Push notifications close the feedback loop without polling.

---

### 5. Test Harness for Loops
**Problem:** How do you test a new loop without burning Claude credits? How do you verify a completion strategy works correctly? Currently there's no way to develop loops with fast feedback.

**Solution:** Add test mode with mocked Claude responses:
- `./scripts/run.sh test loop work` runs with mock responses
- Define fixtures in `scripts/stages/{name}/fixtures/`:
  - `iteration-1.txt` - mock Claude response for iteration 1
  - `iteration-2.txt` - etc.
- Falls back to generic "PLATEAU: false" if no fixture
- Records actual prompts sent (for assertion/review)
- Tests complete in seconds, not minutes
- Add `--record` flag to capture real responses as fixtures

**Why now:** This unlocks TDD for loop development. Right now creating a new loop is trial-and-error with real Claude calls. Test harness makes iteration 10x faster and catches regressions.

---
