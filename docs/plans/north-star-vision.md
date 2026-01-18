# North Star: Agent Pipelines Platform

## The Vision

A **web-based command center** for orchestrating AI agent workflows with human oversight.

**What it feels like to use:**

1. Open the dashboard. See 10 pipelines running across different projects.
2. One pipeline is paused - it's asking for confirmation on a research direction.
3. Click into it. See the full context: what the agent found, what it's proposing, the iteration history.
4. Type feedback: "Skip the academic papers, focus on production implementations."
5. Hit "Continue". The pipeline resumes with your feedback injected.
6. Go back to the dashboard. Check on other pipelines. Review another human-in-the-loop task.
7. Your job is **managing agents**, not doing the work yourself.

**Key capabilities:**
- **Pipeline Library**: Browse and run pre-built pipelines (refine, research, implement, bug-hunt)
- **Pipeline Designer**: Visual editor to create custom pipelines from stages
- **Multi-Session Dashboard**: See all running pipelines, their progress, health scores
- **Task Panel**: Queue of human-in-the-loop checkpoints waiting for review
- **Context Viewer**: Full visibility into what agents are doing (prompts, outputs, iterations)
- **One-Click Resume**: Review, add feedback, continue - all from the UI

---

## Architecture: How We Get There

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND (Future)                        │
│  React/Next.js dashboard with WebSocket connection              │
│  - Pipeline library browser                                     │
│  - Session dashboard (10 running pipelines)                     │
│  - Task panel (human-in-the-loop queue)                        │
│  - Context viewer (iteration history, prompts, outputs)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ WebSocket / REST API
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      API SERVER (Future)                        │
│  Go HTTP server that wraps the SDK                              │
│  - POST /sessions/start                                         │
│  - POST /sessions/{id}/resume                                   │
│  - GET  /sessions (list all)                                    │
│  - GET  /sessions/{id}/events (WebSocket stream)                │
│  - GET  /tasks (human-in-the-loop queue)                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Go function calls
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      GO SDK (Phase 1-3)                         │
│  import "github.com/dodo-digital/agent-pipelines/pkg/pipelines" │
│                                                                 │
│  engine := pipelines.NewEngine()                                │
│  engine.RegisterProvider("claude", claudeProvider)              │
│  engine.OnIterationEnd(myHook)                                  │
│  engine.Run(ctx, pipeline, session)                             │
│  engine.Resume(ctx, session, "user feedback")                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Reads YAML, executes prompts
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STAGES & PIPELINES (Unchanged)               │
│  scripts/stages/improve-plan/stage.yaml + prompt.md             │
│  scripts/stages/ralph/stage.yaml + prompt.md                    │
│  scripts/pipelines/refine.yaml                                  │
│                                                                 │
│  Users can still create their own stages - just YAML + markdown │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Shell out to CLI
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       PROVIDERS                                  │
│  Claude Code CLI, Codex CLI, (future: E2B, OpenCode)            │
└─────────────────────────────────────────────────────────────────┘
```

---

## What is the SDK?

The SDK is a **Go library** that runs pipelines. It's the engine.

Think of it like this:
- **Docker CLI** is a thin wrapper around the **Docker Engine** (containerd)
- **kubectl** is a thin wrapper around the **Kubernetes API**
- **agent-pipelines CLI** will be a thin wrapper around the **agent-pipelines SDK**

The SDK lets you:
```go
// Import the engine
import "github.com/dodo-digital/agent-pipelines/pkg/pipelines"

// Create an engine
engine := pipelines.NewEngine()

// Run a pipeline (same as: ./scripts/run.sh improve-plan my-session 5)
result, err := engine.Run(ctx, pipelines.RunOptions{
    Pipeline: "improve-plan",
    Session:  "my-session",
    Max:      5,
})

// Resume a paused pipeline with feedback
result, err = engine.Resume(ctx, "my-session", "Focus on X instead of Y")
```

**Why do we need an SDK instead of just a CLI?**

Because the CLI can't:
- Stream events in real-time to a frontend
- Pause and wait for user input programmatically
- Be embedded in an API server
- Run multiple sessions in one process with shared state

The CLI is great for terminal use. The SDK is what powers everything else.

---

## What are Hooks?

Hooks are **pause points** where the engine asks "should I continue?"

### SDK Hooks (Programmatic)

When you write Go code that uses the SDK:

```go
engine := pipelines.NewEngine()

// This function gets called after every iteration
engine.OnIterationEnd(func(ctx *pipelines.HookContext) pipelines.HookResult {
    // Check if this is a checkpoint iteration
    if ctx.Iteration % 5 == 0 {
        // Pause and wait for human review
        return pipelines.Pause("Checkpoint: please review progress")
    }
    // Otherwise continue
    return pipelines.Continue()
})
```

This is for when you're building an API server or custom tooling in Go.

### YAML Hooks (Declarative)

When you write pipeline YAML (for CLI or simple use):

```yaml
name: research-pipeline
hooks:
  stage_end:
    - stage: research
      action: confirm
      message: "Research complete. Review findings?"

nodes:
  - id: research
    stage: research-plan
    runs: 5
```

This is for when you want to define checkpoints in the pipeline itself, without writing Go code.

**Both do the same thing** - they create pause points. SDK hooks are programmatic (you write Go code). YAML hooks are declarative (you write YAML).

---

## Do Users Still Build Their Own Stages?

**Yes, absolutely.** Nothing changes about stages.

A stage is still:
```
scripts/stages/my-custom-stage/
├── stage.yaml    # Config: termination strategy, provider, etc.
└── prompt.md     # The prompt template
```

The SDK just provides a different way to **run** stages. It doesn't change how stages are **defined**.

**The SDK comes with:**
- The engine to run pipelines
- Built-in providers (Claude, Codex)
- Hook system for human-in-the-loop

**The SDK does NOT come with:**
- Pre-built stages (those are in the repo, not the SDK)
- Your specific workflows

Users still:
1. Create their own stages (YAML + prompt.md)
2. Create their own pipelines (YAML that chains stages)
3. Run them via CLI or SDK

---

## What Needs to Be Built (In Order)

### Phase 1: Go Engine (MVP)
**Goal:** `./agent-pipelines improve-plan my-session 5` works identically to Bash

- Go CLI that parses commands
- YAML compilation to plan.json
- Run stages with Claude provider
- State management, events, resume

**You can use it from terminal. Everything works like before, but in Go.**

### Phase 2: Full Parity + SDK Foundation
**Goal:** All Bash features work, plus SDK is importable

- All termination strategies (fixed, judgment, queue)
- Multi-stage pipelines, parallel blocks
- Provider interface and registry
- Public `pkg/` packages that can be imported

**You can import the SDK in Go code and run pipelines programmatically.**

### Phase 3: Hooks + Human-in-the-Loop
**Goal:** Pipelines can pause and resume with context

- Hook system (all hook points)
- Pause/resume with context injection
- Event streaming via channels
- `--resume --context` CLI support

**Pipelines can now pause for human review and continue with feedback.**

### Phase 4: API Server + Frontend
**Goal:** The North Star vision

- HTTP API server wrapping the SDK
- WebSocket event streaming
- React/Next.js dashboard
- Pipeline library browser
- Task panel for human-in-the-loop
- Multi-session monitoring

**The full vision: managing 10 agents from a web dashboard.**

---

## CLI vs SDK: You Build Both

This isn't either/or. The CLI is a thin wrapper around the SDK:

```go
// cmd/agent-pipelines/main.go

func main() {
    // Parse CLI args
    args := parseArgs()

    // Create SDK engine
    engine := pipelines.NewEngine()

    // Run the pipeline
    result, err := engine.Run(ctx, pipelines.RunOptions{
        Pipeline: args.Pipeline,
        Session:  args.Session,
        Max:      args.Max,
    })

    // Print result
    fmt.Println(result.Summary)
}
```

The CLI is for terminal users. The SDK is for building everything else (API servers, frontends, custom tooling).

---

## Summary

| Question | Answer |
|----------|--------|
| CLI or SDK? | Both. CLI wraps SDK. |
| Do users still build stages? | Yes, stages are unchanged (YAML + prompt.md) |
| Does SDK come with stages? | No, stages are separate from the engine |
| What are SDK hooks? | Go code that runs at lifecycle points |
| What are YAML hooks? | Declarative pause points in pipeline YAML |
| How does frontend connect? | API server wraps SDK, exposes REST/WebSocket |
| What's the end goal? | Web dashboard for managing multiple agent pipelines with human oversight |

---

## The Path Forward

1. **Now:** Finish the Go engine PRD (done)
2. **Next:** Implement Phase 1 (Go CLI with engine parity)
3. **Then:** Phase 2 (SDK packages, full feature parity)
4. **Then:** Phase 3 (hooks, pause/resume)
5. **Finally:** Phase 4 (API server, frontend)

Each phase is usable on its own:
- Phase 1: Use from terminal (like today)
- Phase 2: Import in Go code
- Phase 3: Human-in-the-loop from terminal
- Phase 4: Full web dashboard
