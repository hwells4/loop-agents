---
name: plan-refinery
description: Iterative planning refinement using specialized Opus subagents. "Check your beads N times, implement once." Refine beads, synthesize competing plans, and improve markdown plans before burning implementation tokens.
context_budget:
  skill_md: 250
  max_references: 2
---

<objective>
Maximize plan quality before implementation begins. Planning tokens are cheaper than implementation tokens - models reason better about detailed plans that fit easily in context. This skill orchestrates specialized Opus subagents to iteratively refine beads, synthesize competing LLM outputs, and improve markdown plans.
</objective>

<usage>
```
/plan-refinery                    # Interactive mode - choose workflow
/plan-refinery refine             # Refine existing beads (run N times)
/plan-refinery context            # Load fresh context for new session
/plan-refinery review             # Review beads after context load
/plan-refinery synthesize         # Merge competing LLM plans
/plan-refinery improve            # Improve markdown plan iteratively
/plan-refinery ideas              # Generate 30 ideas, winnow to best 5
/plan-refinery robot              # Design agent-optimized CLI interface
/plan-refinery loop               # Run iterative refinement until plateau
/plan-refinery loop 10            # Run exactly 10 iterations
```
</usage>

<essential_principles>
1. **Measure N times, cut once:** Run refinement multiple times (6+) for complex plans
2. **Plans are cheap:** A complex markdown plan is still smaller than a few code files
3. **Opus for depth:** All subagents use Opus 4.5 with ultrathink for maximum reasoning
4. **Preserve features:** Refinement must NOT oversimplify or lose functionality
5. **Test coverage:** Plans must include comprehensive unit tests and e2e scripts
6. **Stop on plateau:** When incremental improvements flatline, move to implementation
7. **Fresh sessions help:** Starting new CC session can break out of local optima
</essential_principles>

<intake>
If no subcommand provided, use AskUserQuestion:

```json
{
  "questions": [{
    "question": "Which planning refinement workflow do you need?",
    "header": "Workflow",
    "options": [
      {"label": "Refine Beads", "description": "Iteratively improve existing beads (run N times)"},
      {"label": "Load Context", "description": "Fresh session - load project context first"},
      {"label": "Review After Context", "description": "Review beads after loading context"},
      {"label": "Synthesize Plans", "description": "Merge competing LLM plans into best-of-all"},
      {"label": "Improve Plan", "description": "Iteratively improve a markdown plan"},
      {"label": "Idea Wizard", "description": "Generate 30 ideas, winnow to very best 5"},
      {"label": "Robot Mode", "description": "Design agent-optimized CLI interface"},
      {"label": "Loop", "description": "Run iterative refinement until plateau (Recommended)"}
    ],
    "multiSelect": false
  }]
}
```
</intake>

<routing>
| Response | Workflow |
|----------|----------|
| "Refine Beads" or `refine` | `workflows/refine-beads.md` |
| "Load Context" or `context` | `workflows/load-context.md` |
| "Review After Context" or `review` | `workflows/review-after-context.md` |
| "Synthesize Plans" or `synthesize` | `workflows/synthesize-plans.md` |
| "Improve Plan" or `improve` | `workflows/improve-plan.md` |
| "Idea Wizard" or `ideas` | `workflows/idea-wizard.md` |
| "Robot Mode" or `robot` | `workflows/robot-mode.md` |
| "Loop" or `loop` | `workflows/loop.md` |
</routing>

<quick_start>
**For new project with markdown plan (RECOMMENDED):**
1. Turn markdown plan into beads (separate workflow)
2. Run `/plan-refinery loop` - auto-runs 5-10 iterations until plateau
3. When plateau detected, start new session
4. Run `/plan-refinery context` then `/plan-refinery review`
5. Implement only after beads are optimal

**For merging LLM outputs:**
1. Collect outputs from GPT Pro, Gemini Deep Think, Grok Heavy, Opus
2. Run `/plan-refinery synthesize` to create best-of-all hybrid
3. Run `/plan-refinery improve` to further refine

**For existing markdown plan:**
1. Run `/plan-refinery improve` iteratively
2. Each pass proposes architecture/feature/robustness improvements
3. Stop when incremental gains diminish

**For fresh ideas (breaking tunnel vision):**
1. Run `/plan-refinery ideas` to generate 30 ideas
2. Agent winnows to best 5 with full rationale
3. Add selected ideas to beads or plan

**For agent-friendly tooling:**
1. Run `/plan-refinery robot` with project context
2. Agent designs CLI optimized for agent consumption
3. Implement the design or convert to beads
</quick_start>

<references_index>
| Reference | Purpose |
|-----------|---------|
| references/sub-agents.md | Opus subagent definitions and exact prompts |
</references_index>

<workflows_index>
| Workflow | Purpose |
|----------|---------|
| refine-beads.md | Iteratively improve beads using bead-refiner agent |
| load-context.md | Load project context in fresh session |
| review-after-context.md | Review beads after context loading |
| synthesize-plans.md | Merge competing LLM plans |
| improve-plan.md | Iteratively improve markdown plan |
| idea-wizard.md | Generate 30 ideas, winnow to best 5 |
| robot-mode.md | Design agent-optimized CLI interface |
| loop.md | Run iterative refinement until plateau |
</workflows_index>

<success_criteria>
- [ ] User selected workflow (or provided subcommand)
- [ ] Correct subagent spawned with full prompt
- [ ] Agent uses Opus 4.5 with ultrathink
- [ ] Agent output returned to orchestrator
- [ ] For iterative workflows: user prompted to run again
- [ ] Plateau detection: note when improvements diminish
- [ ] Features preserved: no oversimplification
- [ ] Test coverage: unit tests and e2e scripts included
</success_criteria>
