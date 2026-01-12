# Agent Pipelines

A [Ralph loop](https://ghuntley.com/ralph/) orchestrator for Claude Code.

Describe what you want to build, and Claude handles the rest: planning, task breakdown, and running loops in the background. You can attach to watch progress, spin up multiple loops at once, or chain them into pipelines.

**What you get:**
- Loops run in tmux, not your terminal. Attach, detach, let them run overnight.
- Multiple loops at once for parallel features.
- Planning workflow: PRD → tasks → implementation loop.
- Pipelines to chain loops together.
- Crash recovery with automatic resume.
- Session locking prevents duplicate runs.

**Core philosophy:** Fresh agent per iteration prevents context degradation. Two-agent consensus prevents premature stopping. Planning tokens are cheaper than implementation tokens.

## Build Your Own Stages

Agent Pipelines is also a framework for creating custom stage types. Each stage has:

- A **prompt** that tells Claude what to do each iteration
- A **termination strategy** that decides when to stop

Built-in termination strategies:

| Strategy | When it stops | Good for |
|----------|---------------|----------|
| `queue` | All tasks done (`bd ready` returns empty) | Implementation loops |
| `judgment` | Two agents agree quality plateaued | Refinement, review, elegance |
| `fixed` | After N iterations or agent requests stop | Brainstorming, documentation |

**Example:** You want a bug-fix loop that keeps finding and fixing bugs until it stops finding new ones. Create a stage with `termination: { type: judgment }`. Run it with max 15 iterations. It might stop at 7 when two consecutive runs agree there's nothing left to fix.

Scaffold a new stage in seconds:
```bash
/agent-pipelines:build-stage bugfix
```

This creates `scripts/stages/bugfix/` with a config and prompt template. Edit the prompt, pick your termination strategy, done.

## Installation

```bash
# Add the marketplace
claude plugin marketplace add https://github.com/hwells4/agent-pipelines

# Install the plugin
claude plugin install agent-pipelines@dodo-digital
```

## Dependencies

The plugin checks for these on startup:

| Dependency | Purpose | Install |
|------------|---------|---------|
| [tmux](https://github.com/tmux/tmux) | Background execution | `brew install tmux` or `apt install tmux` |
| [beads](https://github.com/steveyegge/beads) | Task management CLI | `brew install steveyegge/tap/bd` |
| [jq](https://github.com/jqlang/jq) | JSON state management | `brew install jq` or `apt install jq` |

## Commands

### Primary Commands

```bash
/sessions          # Orchestration hub: plan, status, attach, kill
/work              # Run the work loop: implement tasks from beads
/refine            # Run refinement pipelines: improve plans and beads
/ideate            # Generate improvement ideas (one-shot)
```

### Loop Management

```bash
/sessions status       # Check all running loops
/sessions attach NAME  # Watch a loop live (Ctrl+b, d to detach)
/sessions kill NAME    # Stop a session
/sessions plan         # Plan a new feature (PRD → beads)
```

### Supporting Skills

```bash
/agent-pipelines:create-prd     # Generate product requirements document
/agent-pipelines:create-tasks   # Break PRD into executable beads
/agent-pipelines:build-stage    # Scaffold a new custom stage type
```

Or just talk to Claude naturally:

```
"I want to add user authentication to this app"
"Check on my running loops"
"Attach to the auth loop"
```

## How It Works

Run `/sessions` and tell Claude what you're working on:

1. **Planning phase**: Claude gathers context through adaptive questioning, generates a PRD, and breaks it into discrete tasks (beads)
2. **Loop launch**: Claude spawns a tmux session running the loop engine
3. **Iteration cycle**: Each iteration, a fresh Claude instance reads the progress file, picks a task, implements it, commits, and updates progress
4. **Completion**: When work is done (all tasks complete, or quality has plateaued), you get a desktop notification

```
You describe work → Claude plans → tmux loop spawns → Fresh Claude per task → Desktop notification
```

The loop runs **independently** of your Claude Code session. You can:
- Continue working on other things while loops run
- Attach to watch live progress (`/sessions attach`)
- Spin up multiple loops for parallel work
- Recover if Claude Code crashes—loops keep running in tmux

### Why Fresh Agents?

The core insight of the [Ralph loop pattern](https://ghuntley.com/ralph/) is that **fresh agents per iteration prevent context degradation**.

Traditional approaches keep a single agent running across multiple tasks. As the context window fills with previous work, responses become less coherent and the agent loses sight of original goals. Token accumulation degrades quality.

The Ralph loop inverts this:
- Each iteration spawns a **completely fresh Claude instance**
- The fresh agent reads a **progress file** with accumulated learnings
- The progress file is curated: only essential context, not raw conversation history
- Result: iteration 25 has the same quality as iteration 1

This is why planning tokens are cheaper than implementation tokens. A well-structured progress file compresses hours of work into pages of context. Fresh agents read this compressed context and maintain full capability.

## Stage Types

The system includes eight stage types, each designed for a different phase of work:

| Stage | Purpose | Termination | Default Iterations |
|-------|---------|-------------|-------------------|
| **work** | Implement tasks from beads | queue | User-specified |
| **improve-plan** | Iteratively refine planning docs | judgment (2 consensus) | 5 |
| **refine-beads** | Improve task definitions and dependencies | judgment (2 consensus) | 5 |
| **elegance** | Deep exploration for simplicity | judgment (3 min, 2 consensus) | Until plateau |
| **idea-wizard** | Brainstorm improvements | fixed | 1 |
| **readme-sync** | Keep README aligned with code | fixed | 1 |
| **robot-mode** | Design agent-optimized interfaces | fixed | 3 |
| **research-plan** | Research-driven plan refinement | judgment (3 min, 2 consensus) | Until plateau |

### Work Stage

The primary stage for implementation. Each iteration:

1. Reads progress file for accumulated context
2. Lists available beads: `bd ready --label=pipeline/{session}`
3. Picks the next logical task (considering dependencies)
4. Claims it: `bd update {id} --status=in_progress`
5. Implements, tests, commits
6. Closes: `bd close {id}`
7. Appends learnings to progress file

Terminates when the beads queue is empty.

### Refinement Stages

Use `/refine` to polish plans and tasks before implementation:

```bash
/refine quick    # 3+3 iterations (fast validation)
/refine full     # 5+5 iterations (standard, default)
/refine deep     # 8+8 iterations (thorough)
/refine plan     # Only improve the plan
/refine beads    # Only improve the beads
```

Each iteration reviews the work critically, makes improvements, and writes a decision (continue/stop) to status.json. Stops when two consecutive agents agree quality has plateaued.

### Elegance Stage

Deep exploration for simplicity and elegance. Finds what can be simplified, removed, or recast for clarity:

- Reads AGENTS.md and CLAUDE.md intensively
- Maps system architecture before judging pieces
- Launches subagents for deep dives into suspicious abstractions
- Searches for functions that could merge, abstractions serving no purpose, machinery solving non-existent problems

Uses ultrathinking for depth. Requires 3 minimum iterations before checking plateau, then 2 consecutive agents must agree to stop.

### Idea Wizard

Use `/ideate` to generate improvement ideas. The agent:

1. Analyzes your codebase and existing plans
2. Brainstorms 20-30 ideas across six dimensions (UX, performance, reliability, simplicity, features, DX)
3. Evaluates each: Impact (1-5), Effort (1-5), Risk (1-5)
4. Winnows to top 5 and saves to `docs/ideas-{session}.md`

Fixed iterations (default: 1). Multiple iterations push the agent to think differently.

### README Sync Stage

Keeps README aligned with actual codebase:

1. Reads CLAUDE.md as authoritative source
2. Explores codebase for implemented features
3. Compares code vs README for each feature
4. Identifies gaps: missing, outdated, under-explained, under-justified
5. Edits README directly with clear descriptions, usage examples, and rationale

Single iteration by default.

### Robot Mode Stage

Designs CLI interfaces optimized for coding agent ergonomics:

- Identifies friction points that waste agent tokens
- Finds human-oriented formatting (colors, spinners, ASCII art)
- Documents missing machine-readable output options
- Prioritizes improvements by impact-to-effort ratio

Runs 3 iterations by default, each analyzing different areas.

### Research Plan Stage

Research-driven plan refinement using external sources:

1. Chooses ONE research focus per iteration (external repos, local models, tools, architecture)
2. Conducts focused research using WebFetch and WebSearch
3. Documents findings in progress file
4. Applies findings to plan with concrete changes

Uses judgment termination (3 min, 2 consensus). Each iteration must return with specific, actionable findings.

## How Plateau Detection Works

The `judgment` termination strategy requires **N consecutive agents to agree** before stopping (default: 2). This prevents single-agent blind spots.

### The Algorithm

1. **Minimum iterations gate**: Must reach `min_iterations` (default: 2) before checking consensus
2. **Current decision check**: Read the latest agent's status.json for `decision: stop`
3. **Backward scan**: Count consecutive "stop" decisions from most recent backward
4. **Consensus check**: If consecutive stops >= `consensus` (default: 2), terminate

```
Iteration 1: decision=continue
Iteration 2: decision=continue
Iteration 3: decision=stop      → 1 consecutive, need 2, continue
Iteration 4: decision=stop      → 2 consecutive, consensus reached, STOP
```

### Why This Matters

```
Agent 1: "decision: stop - plan covers all requirements"
Agent 2: "decision: continue - missing error handling section"  ← counter resets
Agent 3: "decision: stop - added error handling, plan complete"
Agent 4: "decision: stop - confirmed, nothing to add"  ← loop stops
```

No single agent can prematurely stop a loop. Both must independently confirm the work is done. This prevents:
- Single-agent blind spots
- Premature stopping on subjective quality judgments
- False confidence from one agent's limited analysis

### Configuration

Stages configure consensus requirements in `stage.yaml`:

```yaml
termination:
  type: judgment
  min_iterations: 2    # Don't check before this many iterations
  consensus: 2         # Consecutive stops needed
```

The `elegance` and `research-plan` stages use `min_iterations: 3` to ensure thorough exploration before allowing early termination.

## Pipelines

Chain multiple stages in sequence. Each stage's outputs become inputs for the next:

```yaml
# pipelines/full-refine.yaml
name: full-refine
description: Complete planning refinement - plan first, then beads

stages:
  - name: improve-plan
    stage: improve-plan
    runs: 5

  - name: refine-beads
    stage: refine-beads
    runs: 5
    inputs:
      from: improve-plan
      select: latest
```

Available pipelines:
- `quick-refine` - 3+3 iterations (fast validation)
- `full-refine` - 5+5 iterations (standard)
- `deep-refine` - 8+8 iterations (thorough)

### Running Pipelines

```bash
# Run a multi-stage pipeline
./scripts/run.sh pipeline full-refine.yaml my-session

# Run a single-stage pipeline (3 equivalent ways)
./scripts/run.sh work auth 25                    # Shortcut
./scripts/run.sh loop work auth 25               # Explicit
./scripts/run.sh pipeline --single-stage work auth 25  # Engine syntax
```

### Pipeline Schema

Pipelines support inline prompts, perspectives for fan-out, and stage references:

```yaml
name: multi-review
stages:
  - name: review
    runs: 4
    perspectives:
      - security
      - performance
      - maintainability
      - testing
    prompt: |
      Review from ${PERSPECTIVE} perspective.
      Write to ${OUTPUT}

  - name: synthesize
    runs: 1
    prompt: |
      Combine all reviews:
      ${INPUTS.review}
      Write synthesis to ${OUTPUT}
```

See `scripts/pipelines/SCHEMA.md` for the complete schema reference.

## Architecture

**Everything is a pipeline.** The unified engine (`engine.sh`) runs all sessions the same way. A single-stage pipeline is what we colloquially call a "loop."

```
scripts/
├── engine.sh                 # Unified pipeline engine
├── run.sh                    # Entry point (converts all commands to pipeline calls)
├── lib/                      # Shared utilities
│   ├── yaml.sh               # YAML→JSON conversion
│   ├── state.sh              # JSON iteration history + crash recovery
│   ├── progress.sh           # Accumulated context files
│   ├── context.sh            # v3 context.json generation
│   ├── status.sh             # v3 status.json validation
│   ├── resolve.sh            # Template variable resolution
│   ├── notify.sh             # Desktop notifications + logging
│   ├── lock.sh               # Session locking (prevents duplicates)
│   └── completions/          # Termination strategies
│       ├── beads-empty.sh    # Stop when queue empty (type: queue)
│       ├── plateau.sh        # Stop on consensus (type: judgment)
│       └── fixed-n.sh        # Stop after N iterations (type: fixed)
├── stages/                   # Stage definitions
│   ├── work/                 # Implementation (queue termination)
│   ├── improve-plan/         # Plan refinement (judgment termination)
│   ├── refine-beads/         # Bead refinement (judgment termination)
│   ├── elegance/             # Code elegance review (judgment termination)
│   ├── idea-wizard/          # Ideation (fixed termination)
│   ├── readme-sync/          # Documentation sync (fixed termination)
│   ├── robot-mode/           # Agent-friendly CLI design (fixed termination)
│   └── research-plan/        # Research-driven refinement (judgment termination)
└── pipelines/                # Multi-stage pipeline configs
    ├── SCHEMA.md             # Pipeline schema reference
    ├── quick-refine.yaml     # 3+3 iterations
    ├── full-refine.yaml      # 5+5 iterations
    └── deep-refine.yaml      # 8+8 iterations

skills/                       # Claude Code skill extensions
commands/                     # Slash command documentation
```

### Stage Configuration

Each stage type is defined by a `stage.yaml`:

```yaml
name: work
description: Implement features from beads until done

termination:
  type: queue                 # queue, judgment, or fixed

delay: 3                      # Seconds between iterations
```

For judgment-based stages:

```yaml
name: improve-plan
description: Iteratively refine planning docs

termination:
  type: judgment
  min_iterations: 2           # Don't check consensus before this
  consensus: 2                # Consecutive stops needed

delay: 2
```

For fixed-iteration stages:

```yaml
name: idea-wizard
description: Brainstorm improvements

termination:
  type: fixed                 # Runs exactly N times, or until agent writes decision: stop

delay: 1
```

### v3 Status Format

Agents write `status.json` at the end of each iteration:

```json
{
  "decision": "continue",       // or "stop" or "error"
  "reason": "Found more work",
  "summary": "Implemented auth middleware",
  "work": {
    "items_completed": ["beads-abc123"],
    "files_touched": ["src/auth.ts"]
  },
  "errors": []
}
```

The engine reads this to determine:
- Whether to continue (for judgment/fixed types)
- What to record in state history
- Whether an error occurred

### Template Variables

Prompts use variables that are resolved at runtime:

| Variable | Description |
|----------|-------------|
| `${CTX}` | Path to `context.json` with full iteration context |
| `${PROGRESS}` | Path to progress file |
| `${STATUS}` | Path where agent writes `status.json` |
| `${ITERATION}` | 1-based iteration number |
| `${SESSION_NAME}` | Session name |
| `${OUTPUT}` | Path to write output (multi-stage pipelines) |
| `${INPUTS}` | Previous stage outputs (multi-stage pipelines) |
| `${PERSPECTIVE}` | Current item from perspectives array (fan-out) |

The `context.json` provides complete iteration context:

```json
{
  "session": "auth",
  "pipeline": "loop",
  "stage": { "id": "work", "index": 0, "template": "work" },
  "iteration": 3,
  "paths": {
    "session_dir": ".claude/pipeline-runs/auth",
    "progress": ".claude/pipeline-runs/auth/progress-auth.md",
    "status": ".claude/pipeline-runs/auth/.../iterations/003/status.json"
  },
  "inputs": { "from_stage": {}, "from_previous_iterations": [] },
  "limits": { "max_iterations": 25, "remaining_seconds": -1 }
}
```

## State Management

All sessions run in `.claude/pipeline-runs/{session}/` with unified state tracking:

```
your-project/
├── docs/
│   └── plans/                                    # PRDs
│       └── 2025-01-09-auth-prd.md
├── .claude/
│   ├── locks/                                    # Session locks
│   │   └── auth.lock
│   └── pipeline-runs/
│       └── auth/                                 # Session directory
│           ├── state.json                        # Iteration history + crash recovery
│           ├── progress-auth.md                  # Accumulated context
│           └── stage-00-work/                    # Stage outputs
│               ├── output.md                     # Stage output
│               └── iterations/
│                   ├── 001/
│                   │   ├── context.json          # Iteration context
│                   │   ├── status.json           # Agent decision
│                   │   └── output.md             # Iteration output
│                   └── 002/
│                       └── ...
└── .beads/                                       # Task database
```

### Progress Files

Each iteration appends to the progress file:

```markdown
# Progress: auth

Verify: npm test && npm run build

## Codebase Patterns
(Patterns discovered during implementation)

---

## 2025-01-09 - auth-123
- Implemented JWT validation middleware
- Files: auth/middleware.js, auth/utils.js
- Learning: Token expiry needs graceful handling
---
```

Fresh agents read this file to maintain context without degradation. This is the core of the Ralph loop pattern: each agent is fresh (no token accumulation), but reads accumulated learnings from previous iterations.

### State Files

JSON files track iteration history for completion checks and crash recovery:

```json
{
  "session": "auth",
  "type": "loop",
  "started_at": "2025-01-09T10:00:00Z",
  "status": "running",
  "iteration": 5,
  "iteration_completed": 4,
  "iteration_started": "2025-01-09T10:05:00Z",
  "history": [
    {
      "iteration": 1,
      "timestamp": "2025-01-09T10:00:30Z",
      "decision": "continue",
      "summary": "Implemented user model"
    },
    {
      "iteration": 2,
      "timestamp": "2025-01-09T10:01:00Z",
      "decision": "continue",
      "summary": "Added login endpoint"
    }
  ]
}
```

Key fields:
- `iteration_completed`: Last iteration that fully finished (safe resume point)
- `iteration_started`: When current iteration began (crash detection)
- `history`: Array of all iteration outcomes for plateau detection

## Session Management

### Multi-Session Support

Run multiple pipelines simultaneously. Each has isolated beads, progress, state, and tmux session:

```bash
pipeline-auth      # beads tagged pipeline/auth
pipeline-dashboard # beads tagged pipeline/dashboard
```

### Session Locking

Locks prevent running duplicate sessions with the same name. They are automatically released when a session ends normally or its process dies.

```bash
# List active locks
ls .claude/locks/

# View lock details (PID, start time)
cat .claude/locks/{session}.lock | jq

# Check if a session is locked
test -f .claude/locks/{session}.lock && echo "locked" || echo "available"

# Clear a stale lock manually (only if process is dead)
rm .claude/locks/{session}.lock

# Force start despite existing lock
./scripts/run.sh work my-session 10 --force
```

**When you see "Session is already running":**
1. Check if the PID in the lock file is still alive: `ps -p <pid>`
2. If alive, the session is running - attach or kill it first
3. If dead, the lock is stale - use `--resume` to continue or `--force` to restart

### Crash Recovery

Sessions automatically detect and recover from crashes (API timeouts, network issues, SIGKILL).

**When a session crashes**, you'll see:
```
Session 'auth' failed at iteration 5/25
Last successful iteration: 4
Error: Claude process terminated unexpectedly
Run with --resume to continue from iteration 5
```

**To resume:**
```bash
./scripts/run.sh work auth 25 --resume
```

**How crash detection works:**
1. On startup, engine checks: lock exists + PID dead = crashed
2. State file tracks `iteration_started` and `iteration_completed` for precise resume
3. For hung sessions (PID alive but stuck), use `tmux attach` to diagnose

**What gets preserved on crash:**
- Iteration history (all completed iterations in `state.json`)
- Progress file (accumulated learnings in markdown)
- Completion checkpoint (`iteration_completed` marks the safe point)
- Error context (what went wrong)

**What gets reset on resume:**
- Status returns to "running"
- Error details cleared
- Loop continues from `iteration_completed + 1`

## Debugging

```bash
# Watch a running pipeline
tmux attach -t pipeline-{session}

# Check pipeline state
cat .claude/pipeline-runs/{session}/state.json | jq

# View progress file
cat .claude/pipeline-runs/{session}/progress-{session}.md

# Check remaining beads
bd ready --label=pipeline/{session}

# Check iteration status
cat .claude/pipeline-runs/{session}/stage-*/iterations/*/status.json | jq

# Kill a stuck pipeline
tmux kill-session -t pipeline-{session}

# Check session status (active, failed, completed)
./scripts/run.sh status {session}
```

## Notifications

When a loop completes:
- **macOS**: Native notification center
- **Linux**: `notify-send` (requires `libnotify`)

All completions logged to `.claude/pipeline-completions.json`.

## Environment Variables

Loops export these for hooks and prompts:

| Variable | Description |
|----------|-------------|
| `CLAUDE_PIPELINE_AGENT` | Always `1` when inside a loop |
| `CLAUDE_PIPELINE_SESSION` | Current session name |
| `CLAUDE_PIPELINE_TYPE` | Current stage type |

## Limitations

Loops run locally in tmux. If your machine sleeps, they pause. Use a keep-awake utility for overnight runs.

## License

MIT
