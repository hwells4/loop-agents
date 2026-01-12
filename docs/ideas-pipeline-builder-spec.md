# Ideas from pipeline-builder-spec - Iteration 1

> Focus: Ideas to improve the pipeline-builder skills and the experience of creating custom pipelines

---

### 1. Stage Catalog with Live Preview

**Problem:** Users creating pipelines must understand what existing stages do by reading YAML and prompt files. There's no quick way to browse available stages, see examples of their output, or understand their tradeoffs.

**Solution:** Build a stage catalog accessible via `/pipeline catalog`:
- Interactive list showing all stages in `scripts/stages/`
- For each stage: description, termination strategy, model recommendation
- "Example output" showing a real iteration result from that stage
- Recommendation tags: "good for planning", "high-quality output", "fast"
- Can be invoked mid-conversation: "Show me stages that use judgment termination"

**Why now:** The pipeline-builder spec introduces automatic stage selection by the architecture agent. That agent needs a rich understanding of stage capabilities to recommend well. A catalog becomes the source of truth for both humans and agents.

---

### 2. Prompt Composability via Template Includes

**Problem:** The pipeline-builder creates stage prompts from scratch, leading to inconsistency. Every new stage reinvents the "read context" and "write status" patterns. Copy-paste errors accumulate. Best practices diverge.

**Solution:** Add template includes for common patterns:
```markdown
# My Custom Stage

${include:preamble/autonomy-grant.md}

## Your Mission
[Custom content here]

${include:patterns/read-context.md}
${include:patterns/write-status.md}
```
Include library in `scripts/lib/templates/`:
- `autonomy-grant.md` - "This is not a checklist task..." paragraph
- `read-context.md` - Standard cat/jq commands
- `write-status.md` - JSON schema and decision guide
- `subagent-guidance.md` - When and how to spawn subagents

**Why now:** The Stage Creator Agent in the spec will generate many prompts. Includes ensure consistency without requiring the agent to memorize boilerplate. Humans benefit equally when hand-crafting stages.

---

### 3. Pipeline Visualization Command

**Problem:** Multi-stage pipelines are defined in YAML but understanding the flow requires mental parsing. Users can't quickly see: stage order, data flow between stages, estimated iteration counts, or cost implications.

**Solution:** Add `./scripts/run.sh viz {pipeline}` that generates:
- ASCII art showing stage sequence and data flow
- Annotations with iteration counts and models per stage
- Estimated token usage range (min/max based on history)
- Dependency arrows showing `inputs.from` relationships
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  improve-plan   │────▶│  refine-beads   │────▶│    elegance     │
│  5 iters, opus  │     │  5 iters, opus  │     │  3 iters, opus  │
│  ~50k tokens    │     │  ~40k tokens    │     │  ~30k tokens    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Why now:** The pipeline-builder spec introduces complex multi-stage architectures. Visualization bridges the gap between YAML configuration and human understanding. Critical for reviewing architecture agent recommendations.

---

### 4. Confidence Scoring for Architecture Recommendations

**Problem:** The architecture agent returns a recommendation, but users don't know how confident it is. Was this the obvious choice or a toss-up between three options? Should the user ask clarifying questions or trust it?

**Solution:** Add confidence scoring to architecture agent output:
```yaml
recommendation:
  confidence: 0.85  # 0-1 scale
  confidence_breakdown:
    termination_strategy: 0.95  # Very clear this should be judgment
    stage_count: 0.70           # Could be 2 or 3 stages
    model_selection: 0.90       # Opus clearly needed
  areas_of_uncertainty:
    - "Unclear if refine-beads should run before or after elegance"
    - "User's tolerance for cost vs quality tradeoff unknown"
```
Display to user: "I'm 85% confident in this architecture. Key uncertainty: stage ordering."

**Why now:** The spec positions the architecture agent as mandatory before confirmation. Confidence scoring helps users decide whether to accept immediately or probe further. Transparent AI decision-making builds trust.

---

### 5. Stage A/B Testing Framework

**Problem:** Users can't empirically compare different stage configurations. Does 3-consensus outperform 2-consensus? Is Sonnet good enough for this task? Currently: guess and hope.

**Solution:** Add A/B testing support:
```bash
./scripts/run.sh ab-test \
  --config-a "elegance-3consensus.yaml" \
  --config-b "elegance-2consensus.yaml" \
  --trials 5 \
  --session-prefix "elegance-ab"
```
- Runs both configurations N times with identical inputs
- Records: iterations-to-complete, token usage, output quality (via LLM eval)
- Generates comparison report with statistical significance
- Stores results in `.claude/ab-tests/` for future reference

**Why now:** The pipeline-builder empowers users to create custom stages with arbitrary configurations. Without measurement, they can't optimize. A/B testing turns pipeline design from art into science.

---

## Ideas from pipeline-builder-spec - Iteration 2

> Focus: Operational reliability, cost control, and production-readiness for pipeline execution

---

### 6. Human-in-the-Loop Checkpoints

**Problem:** Once a pipeline starts, it runs to completion with no opportunity for human intervention. A user can't review stage outputs before the next stage begins. This is risky for expensive pipelines or when early stages might go off-track.

**Solution:** Add checkpoint configuration to pipeline definitions:
```yaml
stages:
  - name: architecture-design
    loop: design
    runs: 5
    checkpoint: true  # Pause after this stage

  - name: implementation
    loop: work
    runs: 10
```
When a checkpoint is reached:
- Engine pauses and notifies user (terminal + desktop notification)
- User reviews outputs from completed stage
- Commands: `./scripts/run.sh continue {session}` or `./scripts/run.sh abort {session}`
- Optional: `--unattended` flag skips all checkpoints

**Why now:** The pipeline-builder enables users to create arbitrary multi-stage pipelines. Some will be expensive (many iterations with Opus). Checkpoints let users validate early stages before committing to full execution. Production pipelines need this.

---

### 7. Token Budget Allocation

**Problem:** Users set max_iterations per stage but have no way to control total token spend. A 5-stage pipeline could consume $50 in tokens before anyone notices. Cost overruns are only discovered after the fact.

**Solution:** Add budget configuration at pipeline and stage levels:
```yaml
name: expensive-pipeline
budget:
  total_tokens: 500000        # Hard cap for entire pipeline
  per_stage: 100000           # Default per-stage cap
  alert_threshold: 0.8        # Warn at 80% usage

stages:
  - name: complex-analysis
    loop: analyze
    budget:
      tokens: 200000          # Override: this stage gets more
```
Runtime behavior:
- Engine tracks token usage from Claude API responses
- Pause and notify when alert_threshold reached
- Hard stop when budget exhausted (graceful termination)
- After pipeline: show token usage breakdown by stage

**Why now:** The pipeline-builder democratizes complex pipeline creation. Users who don't understand token economics will create expensive configurations. Budget guardrails prevent surprise bills. Essential for team adoption.

---

### 8. Stage Output Caching and Replay

**Problem:** Re-running a pipeline means re-doing all stages from scratch. If you want to tweak stage 3 of a 4-stage pipeline, you must run stages 1-2 again. This wastes tokens and time, especially for deterministic early stages.

**Solution:** Add caching infrastructure:
```bash
# Cache stage outputs (stored in .claude/cache/)
./scripts/run.sh pipeline full-refine.yaml my-session --cache

# Replay with cached stage 1, re-run stages 2+
./scripts/run.sh pipeline full-refine.yaml my-session --from-stage=2

# Invalidate specific stage cache
./scripts/run.sh cache clear my-session stage-1
```
Cache format:
- `.claude/cache/{session}/{stage}/output.json` - Serialized stage outputs
- `.claude/cache/{session}/{stage}/inputs.hash` - Hash of inputs (for cache invalidation)
- Auto-invalidate when stage config or inputs change

**Why now:** The pipeline-builder encourages experimentation with multi-stage configurations. Without caching, every experiment re-runs everything. Caching enables rapid iteration on later stages while preserving expensive early-stage work.

---

### 9. Stage Timeout Configuration

**Problem:** A stage can run indefinitely if an agent gets stuck or the judgment termination never reaches consensus. There's no safety valve. A stuck pipeline silently consumes resources until someone notices.

**Solution:** Add timeout configuration:
```yaml
name: my-stage
termination:
  type: judgment
  timeout:
    per_iteration: 300       # 5 minutes per iteration
    total: 1800              # 30 minutes for entire stage
    action: error            # 'error' | 'force_stop' | 'notify'
```
Timeout behavior:
- `error`: Mark stage as failed, pipeline stops
- `force_stop`: Write `decision: stop` and continue (graceful degradation)
- `notify`: Alert user but keep running

Also add pipeline-level timeout:
```yaml
name: my-pipeline
timeout: 7200  # 2 hours total
```

**Why now:** The pipeline-builder creates stages that may behave unexpectedly. Runaway iterations are a real risk with judgment termination (what if agents never agree?). Timeouts are table-stakes for production reliability.

---

### 10. One-Click Stage Cloning with Variants

**Problem:** Users often want "elegance but stricter" or "refine-beads but for security". Currently they must manually copy files, modify YAML, edit prompts. This friction discourages customization.

**Solution:** Add clone command with variant configuration:
```bash
# Clone a stage with modifications
./scripts/run.sh stage clone elegance elegance-strict \
  --consensus=3 \
  --min-iterations=5 \
  --model=opus

# Interactive clone (asks what to change)
./scripts/run.sh stage clone work work-security
```
For complex modifications:
```yaml
# .claude/stage-variants/elegance-strict.yaml
base: elegance
changes:
  termination:
    consensus: 3
    min_iterations: 5
  prompt:
    prepend: |
      IMPORTANT: Be extremely strict in your evaluation.
      Reject any code that is merely "good enough".
```
Benefits:
- Preserves relationship to base stage (for updates)
- Diff-based tracking of customizations
- Can list all variants: `./scripts/run.sh stage list --variants`

**Why now:** The pipeline-builder's architecture agent recommends existing stages. Users will want to tweak them. Making customization frictionless multiplies the value of each base stage. Variants are the extension mechanism.

---

## Ideas from pipeline-builder-spec - Iteration 3

> Focus: Learning, adaptation, and intelligence—making the pipeline system smarter over time

---

### 11. Pipeline Execution Analytics Dashboard

**Problem:** Users run pipelines but have no aggregate view of what's working. Which stages have the best completion rates? Which pipelines consume the most tokens per successful run? There's no way to identify systemic inefficiencies or track improvement over time.

**Solution:** Build an analytics layer that tracks execution metrics:
```bash
./scripts/run.sh analytics
```
Displays:
- **Stage performance**: Average iterations to completion, token efficiency, failure rates
- **Pipeline performance**: End-to-end completion rates, total cost trends
- **Termination patterns**: How often judgment stages reach consensus at min_iterations vs max
- **Time series**: Are pipelines getting more efficient over time?

Data stored in `.claude/analytics/`:
```json
{
  "stage": "elegance",
  "runs": 47,
  "avg_iterations": 3.2,
  "consensus_at_min": 0.68,
  "avg_tokens": 42000,
  "failure_rate": 0.02
}
```

**Why now:** The pipeline-builder democratizes pipeline creation. Without analytics, users create pipelines blindly. Data-driven insights reveal what stage configurations actually work, informing better architecture agent recommendations.

---

### 12. Architecture Agent Memory: Learning from Past Designs

**Problem:** Every invocation of the architecture agent starts from scratch. It doesn't know which architectures succeeded or failed for similar problems. The agent makes the same recommendations repeatedly, even when historical data suggests better alternatives.

**Solution:** Give the architecture agent access to execution history:
```markdown
# Architecture Agent (Enhanced)

## Historical Context

Before recommending, review past executions:
- `.claude/analytics/by-intent/` - Indexed by problem type
- `.claude/analytics/successful-runs/` - Completed pipelines
- `.claude/analytics/failed-runs/` - Failed attempts with failure reasons

Consider:
- Which stage configurations worked for similar problems?
- What termination settings led to efficient completion?
- What patterns correlate with failure?

Weight your recommendations toward proven patterns.
```

The system indexes executions by:
- **Intent tags**: "refactoring", "documentation", "testing", etc.
- **Termination outcomes**: Successful completion, timeout, budget exhaustion
- **Efficiency metrics**: Iterations used vs. max, token cost

**Why now:** The pipeline-builder spec positions the architecture agent as the critical decision-maker. Learning from history transforms it from "best-guess" to "evidence-based." Each execution makes the system smarter.

---

### 13. Prompt Effectiveness Scoring

**Problem:** Stage prompts are written once and assumed good. But some prompts lead to confused agents, excessive iterations, or low-quality outputs. There's no feedback loop to improve prompts based on execution outcomes.

**Solution:** Score prompt effectiveness based on execution patterns:
```bash
./scripts/run.sh prompt-health {stage}
```
Outputs:
```
Stage: elegance
Prompt Health Score: 73/100

Metrics:
- Clarity: 85/100 (agents rarely ask clarifying questions)
- Efficiency: 62/100 (often exceeds min_iterations before consensus)
- Consistency: 72/100 (outputs vary in structure)

Improvement Suggestions:
- Add explicit output format example (would improve consistency)
- Clarify "quality plateau" criteria (would improve efficiency)
- Consider adding decision rubric (would accelerate consensus)
```

Scoring factors:
- **Clarity**: Low re-reads of context, few clarifying questions
- **Efficiency**: Completion near min_iterations, low token usage
- **Consistency**: Similar output structures across runs
- **Success rate**: Completions vs. errors/timeouts

**Why now:** The Stage Creator Agent generates prompts. Prompt effectiveness scoring provides a feedback signal to improve generation quality. It also helps humans diagnose why a stage isn't performing well.

---

### 14. Smart Defaults from Corpus Analysis

**Problem:** The pipeline-builder spec requires configuration decisions: termination strategies, iteration counts, model selection. Users guess. The architecture agent applies heuristics. But the codebase contains a corpus of real configurations that could inform smarter defaults.

**Solution:** Analyze existing stages and pipelines to derive statistical defaults:
```bash
./scripts/run.sh analyze-corpus
```
Generates `.claude/corpus-analysis.json`:
```json
{
  "termination_patterns": {
    "judgment": {
      "typical_min_iterations": 2,
      "typical_consensus": 2,
      "correlation_quality_cost": 0.73
    },
    "queue": {
      "typical_delay": 3,
      "common_check_before": true
    }
  },
  "model_usage": {
    "opus": ["planning", "architecture", "quality-review"],
    "sonnet": ["implementation", "testing"],
    "haiku": ["validation", "formatting"]
  },
  "stage_relationships": {
    "refine_before_work": 0.85,
    "elegance_at_end": 0.90
  }
}
```

The architecture agent consults this analysis:
- "For judgment stages, corpus shows consensus=2 works in 80% of cases"
- "For implementation work, sonnet is sufficient in 70% of pipelines"
- "Quality review stages typically follow implementation"

**Why now:** The pipeline-builder creates new configurations. Without corpus intelligence, every new pipeline reinvents wheel. Mining existing patterns accelerates configuration with proven values.

---

### 15. Semantic Stage Similarity Search

**Problem:** Users describe what they want ("a stage that reviews code for security issues") but don't know which existing stages might fit. The architecture agent recommends, but its knowledge is static. Users can't search by intent.

**Solution:** Add semantic search over stage definitions:
```bash
./scripts/run.sh stage search "security review for vulnerabilities"
```
Returns:
```
Matches:
1. elegance (score: 0.72)
   - Similarity: Also does code review
   - Difference: Focus is style, not security
   - Variant suggestion: Clone with security lens

2. refine-beads (score: 0.54)
   - Similarity: Quality improvement iterations
   - Difference: Operates on beads, not code

Recommendation: No direct match. Create new stage or clone elegance with security focus.
```

Implementation:
- Embed stage descriptions and prompt content
- Store embeddings in `.claude/stage-embeddings/`
- Search via cosine similarity on user query
- Include in architecture agent context

**Why now:** The pipeline-builder encourages stage reuse. Semantic search makes discovery frictionless. Users find existing stages or near-matches before creating new ones. This compounds the value of each new stage added to the system.

---

## Ideas from pipeline-builder-spec - Iteration 4

> Focus: Composability, error resilience, and external integration—making pipelines more flexible, robust, and connected

---

### 16. Stage Parameterization for Reusable Templates

**Problem:** Stages are currently monolithic—`elegance` is always elegance. But users often want "elegance but stricter" or "elegance for security". The only options are to clone entire stages (duplicating prompt content) or live with the default configuration. This limits reuse.

**Solution:** Add parameterized stages that accept configuration at invocation time:
```yaml
# scripts/stages/code-review/loop.yaml
name: code-review
description: General code review with configurable focus
parameters:
  - name: focus
    description: What aspect to emphasize
    default: "general quality"
  - name: strictness
    type: enum
    values: [lenient, balanced, strict]
    default: balanced
```

Pipeline configuration uses parameters:
```yaml
stages:
  - name: security-review
    loop: code-review
    runs: 5
    with:
      focus: "security vulnerabilities and OWASP top 10"
      strictness: strict

  - name: style-review
    loop: code-review
    runs: 3
    with:
      focus: "code style and naming conventions"
      strictness: balanced
```

The prompt accesses parameters via `${PARAMS.focus}` and `${PARAMS.strictness}`.

**Why now:** The pipeline-builder creates stages for users. Parameters enable a single well-designed stage to serve many purposes. This dramatically increases ROI on stage development—one investment, many applications.

---

### 17. Webhook Callbacks for External Integration

**Problem:** Pipelines run in isolation. External systems (Slack, CI/CD, monitoring) have no visibility into progress or completion. Users must manually check status. Integration requires custom scripting.

**Solution:** Add webhook configuration at pipeline and stage boundaries:
```yaml
name: my-pipeline
webhooks:
  on_start: https://hooks.slack.com/T.../B.../xxx
  on_stage_complete: https://api.example.com/pipeline-events
  on_complete: https://hooks.slack.com/T.../B.../yyy
  on_error: https://pagerduty.com/integration/xxx

stages:
  - name: critical-stage
    loop: analyze
    webhooks:
      on_complete:
        url: https://api.example.com/critical-complete
        include_output: true
```

Webhook payload:
```json
{
  "event": "stage_complete",
  "pipeline": "my-pipeline",
  "session": "auth-feature",
  "stage": "critical-stage",
  "iteration": 5,
  "status": "success",
  "summary": "Identified 3 security issues",
  "timestamp": "2026-01-12T10:30:00Z"
}
```

**Why now:** Pipelines are becoming the standard execution model for complex work. External visibility is essential for team adoption—managers need status updates, CI systems need completion signals, and monitoring needs error alerts.

---

### 18. Intelligent Retry Strategies with Backoff

**Problem:** When iterations fail (API timeout, rate limit, transient error), the pipeline treats it as a hard failure. The only recovery is manual `--resume`. This is fragile for production use—transient failures shouldn't require human intervention.

**Solution:** Add configurable retry strategies:
```yaml
name: my-stage
retry:
  max_attempts: 3
  backoff:
    type: exponential  # linear, exponential, fixed
    initial: 5s
    max: 60s
  on_errors:
    - "rate_limit"
    - "timeout"
    - "api_error"
  exclude_errors:
    - "validation_error"
    - "status_parse_error"
```

Retry behavior:
- On transient error, wait `backoff` seconds and retry same iteration
- Errors categorized by pattern matching on Claude output
- After `max_attempts`, mark as failed (or fallback to error webhook)
- State file tracks retry attempts for visibility

Pipeline-level defaults:
```yaml
name: production-pipeline
defaults:
  retry:
    max_attempts: 3
    backoff:
      type: exponential
      initial: 5s
```

**Why now:** As pipelines run longer and with more iterations, transient failures become inevitable. API rate limits, network hiccups, and temporary service issues shouldn't derail multi-hour pipelines. Retry is table-stakes for production reliability.

---

### 19. Interactive Pipeline Debugger

**Problem:** When a stage behaves unexpectedly, debugging requires manual inspection: read the progress file, check iteration outputs, examine status.json. There's no unified debugging experience. Understanding "what went wrong at iteration 7" requires archaeology.

**Solution:** Add `./scripts/run.sh debug {session}` with interactive capabilities:
```
$ ./scripts/run.sh debug auth-feature

Pipeline Debugger: auth-feature
Stage: improve-plan (iteration 7/10)
Status: running

Commands:
  [s]tatus    - Show current state and recent history
  [i]teration N - Jump to iteration N output
  [p]rogress  - Show progress file
  [c]ontext   - Show context.json for current iteration
  [d]iff N M  - Diff iteration N vs M outputs
  [t]imeline  - Show iteration timeline with decisions
  [l]og       - Tail Claude execution log
  [w]atch     - Live watch mode (auto-refresh)
  [q]uit      - Exit debugger

> timeline
┌─────────────────────────────────────────────────────────────────────────────┐
│ improve-plan: auth-feature                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1 ────▶ 2 ────▶ 3 ────▶ 4 ────▶ 5 ────▶ 6 ────▶ 7 (running)              │
│ cont   cont    cont    cont    stop    cont*   ...                        │
│ 42k    38k     51k     29k     35k     41k                                │
└─────────────────────────────────────────────────────────────────────────────┘
* = override: plateau broken by iteration 6 (new issue discovered)

> iteration 5
Iteration 5 (completed 10:23:15, decision: stop)
Reason: "All identified improvements have been applied..."
Files touched: [PLAN.md, docs/architecture.md]
```

**Why now:** The pipeline-builder empowers users to create complex multi-stage pipelines. Complexity breeds failure modes. A first-class debugging experience is essential for troubleshooting. Current approach (manual file inspection) doesn't scale.

---

### 20. Partial Completion Handling with Savepoints

**Problem:** If a pipeline fails mid-stage, the only options are resume (redo the failed iteration) or restart (lose all progress). There's no way to salvage partial progress within an iteration. Long iterations might do useful work before failing—that work is lost.

**Solution:** Add savepoint capability for mid-iteration preservation:
```yaml
name: long-stage
savepoints:
  enabled: true
  interval: 60s          # Auto-save every 60 seconds
  on_file_change: true   # Save when files are modified
```

Engine behavior:
- Monitor iteration progress (file modifications, progress updates)
- Create timestamped savepoints: `.claude/savepoints/{session}/{iteration}/{timestamp}/`
- On failure: offer rollback options
```
$ ./scripts/run.sh status auth-feature

Pipeline: auth-feature
Status: FAILED at stage improve-plan, iteration 7

Savepoints available:
  1. 10:23:15 (3 files modified, 2 beads closed)
  2. 10:24:30 (5 files modified, 3 beads closed)
  3. 10:25:45 (5 files modified, 4 beads closed) <-- most recent

Options:
  [1-3] Restore savepoint and continue
  [r]esume - Retry iteration 7 from scratch
  [a]bort  - Stop pipeline
```

On restore:
- Roll back file modifications to savepoint state
- Update progress file to reflect restored state
- Continue from savepoint context

**Why now:** As iterations do more work (especially work stages that modify many files), mid-iteration failures become costly. Savepoints provide insurance against lost work. This is especially critical for expensive Opus iterations that might run for minutes.

---

## Ideas from pipeline-builder-spec - Iteration 5

> Focus: Collaboration, governance, and human-agent partnership—how teams work together on pipelines and how humans and agents can collaborate more effectively

---

### 21. Pipeline Approval Workflows for Team Governance

**Problem:** When one person creates a pipeline, there's no review process before it consumes team resources. A junior developer might create an expensive 50-iteration Opus pipeline without understanding the cost implications. Organizations need approval gates without slowing down individual experimentation.

**Solution:** Add approval workflow configuration:
```yaml
# .claude/governance/approval-rules.yaml
rules:
  - condition:
      or:
        - estimated_tokens: "> 100000"
        - stages_count: "> 3"
        - uses_model: "opus"
    requires:
      approvers: ["@senior-dev", "@team-lead"]
      min_approvals: 1

  - condition:
      estimated_cost: "> $5"
    requires:
      approvers: ["@finance-admin"]
      min_approvals: 1
```

Workflow:
1. Pipeline designer calculates estimated resource usage
2. If rules trigger, pipeline enters pending state
3. Designated approvers review via `/pipeline review {id}`
4. Approved pipelines can be executed; rejected ones return feedback
5. Authors with sufficient track record can be auto-approved

**Why now:** The pipeline-builder democratizes pipeline creation. Without governance, this leads to uncontrolled resource consumption. Approval workflows enable delegation while maintaining oversight—essential for team adoption.

---

### 22. Collaborative Pipeline Editing with Live Presence

**Problem:** Pipeline design is inherently collaborative—architects, domain experts, and implementers all have insights. But current workflows are single-user. When two people want to iterate on a pipeline design, they must take turns or coordinate out-of-band.

**Solution:** Add collaborative editing support:
```bash
# Start collaborative session
./scripts/run.sh collaborate {session} --share

# Returns shareable link
Collaboration session started: https://pipeline.local/collab/abc123
Share this link with collaborators (requires same network)
```

Collaboration features:
- **Live presence**: See who's viewing the pipeline spec
- **Annotation mode**: Leave comments on specific stages or configuration choices
- **Suggestion mode**: Propose changes that the owner can accept/reject
- **Voice notes**: Quick audio annotations for complex reasoning

For async collaboration:
```bash
./scripts/run.sh pipeline review-request {pipeline} \
  --reviewer=@senior-dev \
  --message="Please review the termination strategy choice"
```

**Why now:** The pipeline-builder creates artifacts (specs, stages) that benefit from review. Current git-based review (PRs) is too heavyweight for rapid iteration. Lightweight collaboration accelerates design convergence.

---

### 23. Agent Handoff Notes for Human Takeover

**Problem:** When a pipeline stalls, errors, or produces unexpected results, a human must take over. But the agent's context—why it made decisions, what alternatives it considered, what it was about to try—is lost. The human starts cold, wasting time rediscovering the agent's mental state.

**Solution:** Add structured handoff documentation that agents maintain:
```json
// .claude/pipeline-runs/{session}/handoff.json
{
  "current_focus": "Refactoring authentication module",
  "decision_log": [
    {
      "iteration": 5,
      "decision": "Chose JWT over session-based auth",
      "reasoning": "User mentioned API-first architecture",
      "alternatives_considered": ["session-based", "OAuth only"],
      "confidence": 0.85
    }
  ],
  "blocked_on": {
    "issue": "Unclear if rate limiting should be per-user or per-API-key",
    "question_for_human": "Which rate limiting strategy do you prefer?",
    "context": "Found conflicting patterns in existing code"
  },
  "next_steps_if_continued": [
    "Implement token refresh endpoint",
    "Add rate limiting (pending clarification)",
    "Write integration tests"
  ],
  "files_to_review": ["src/auth/jwt.ts", "src/middleware/rate-limit.ts"]
}
```

On pipeline pause/error:
```
$ ./scripts/run.sh takeover auth-feature

Agent Handoff Summary:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Current Focus: Refactoring authentication module

Blocked On: Rate limiting strategy unclear
Question for you: Per-user or per-API-key rate limiting?

Recent Decisions:
- Chose JWT over session-based (confidence: 85%)
- ...

Suggested Next Steps:
1. Clarify rate limiting approach
2. Review: src/auth/jwt.ts (major changes)
3. Continue implementation

Commands:
  [c]ontinue  - Resume pipeline with answer
  [r]eview    - Review changed files
  [a]bort     - Stop and preserve state
```

**Why now:** Human-agent collaboration is a loop, not a handoff. When agents get stuck, clean handoff documentation enables seamless human intervention. This is the difference between "agent failed" and "agent and human collaborated."

---

### 24. Pipeline Templates with Team Conventions

**Problem:** Teams develop patterns for how they structure pipelines—certain stage orderings, preferred termination strategies, naming conventions. But each new pipeline starts from scratch. Knowledge stays in individuals' heads rather than being encoded in reusable templates.

**Solution:** Add team template system:
```yaml
# .claude/templates/team-standard.yaml
name: team-standard
description: Our standard feature implementation pipeline
author: "@team-lead"
tags: [production, reviewed]

template:
  stages:
    - name: plan-${feature}
      loop: improve-plan
      runs: 5
      description: "Refine the implementation plan"

    - name: implement-${feature}
      loop: work
      runs: 15
      inputs:
        from: plan-${feature}

    - name: review-${feature}
      loop: elegance
      runs: 3
      checkpoint: true  # Human review before final stage

  defaults:
    model: sonnet
    retry:
      max_attempts: 3

  conventions:
    session_naming: "{ticket}-{feature}"
    required_labels: ["pipeline/${feature}"]
```

Usage:
```bash
./scripts/run.sh pipeline from-template team-standard \
  --feature=auth \
  --ticket=JIRA-123
```

Template discovery:
```bash
./scripts/run.sh templates list
./scripts/run.sh templates inspect team-standard
```

Architecture agent suggests templates:
```
Recommendation: Use "team-standard" template (91% match to your requirements)
Modifications needed:
- Increase plan iterations to 8 (complex feature)
- Add security-review stage after implementation
```

**Why now:** The pipeline-builder creates pipelines from scratch every time. Templates capture team learning and accelerate creation. Over time, the template library becomes a codified best-practices repository.

---

### 25. Agent Reflection Prompts for Continuous Improvement

**Problem:** Agents complete iterations and move on. There's no mechanism for agents to reflect on what worked, what didn't, and what they'd do differently. Learning happens at the system level (analytics, corpus analysis) but not at the individual execution level.

**Solution:** Add optional reflection prompts at stage boundaries:
```yaml
# In loop.yaml
reflection:
  enabled: true
  trigger: on_stage_complete  # or: every_n_iterations: 3
```

When triggered, the engine injects a reflection prompt:
```markdown
## Reflection Checkpoint

Before moving to the next stage, pause and reflect:

1. **What worked well this stage?**
   - Which approaches were most effective?
   - What decisions do you feel confident about?

2. **What could have gone better?**
   - Where did you get stuck or backtrack?
   - What would you do differently next time?

3. **Insights for future agents?**
   - What patterns should be reused?
   - What anti-patterns should be avoided?

Write your reflection to: ${REFLECTION_FILE}
```

Reflections are stored in `.claude/reflections/{session}/` and:
- Fed to the architecture agent for future recommendations
- Aggregated for prompt effectiveness scoring
- Available for human review during pipeline debugging

**Why now:** The pipeline-builder creates stages that run repeatedly. Reflection prompts create a feedback loop where agents actively contribute to system improvement. This is meta-learning—agents helping future agents be better.

---
