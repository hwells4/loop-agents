# Workflow: Refinement Loop

Run iterative refinement agents in a loop until improvements plateau. Automates the "check your beads N times" pattern.

## Philosophy

> "I used to only run that once or twice before starting implementation, but I experimented recently with running it 6+ times, and it kept making useful refinements."

This workflow automates that pattern - running refinement iterations until you hit diminishing returns.

## When to Use
- After creating beads from a plan (run bead-refiner loop)
- After drafting a markdown plan (run plan-improver loop)
- When you want hands-off iterative refinement

## Steps

### 1. Detect Mode

Check what exists:

```bash
# Check for beads
bd list --status=open 2>/dev/null | head -5

# Check for plan file (user may provide)
```

Ask user:

```
What should I refine iteratively?

[1] Beads (run bead-refiner loop)
[2] Plan file (run plan-improver loop)
[3] Both in sequence (plan → beads → refine beads)
```

### 2. Get Parameters

```
How many iterations? (Recommended: 5-10 for complex projects)

[1] 5 iterations (quick pass)
[2] 10 iterations (thorough)
[3] Until plateau (auto-detect diminishing returns)
[4] Custom number
```

If plan mode, also ask for plan file path.

### 3. Run the Loop

**For each iteration:**

1. Spawn the appropriate Opus agent (bead-refiner or plan-improver)
2. Wait for completion
3. Parse output for:
   - Changes made (count)
   - Plateau signals ("no significant changes", "minor adjustments only")
4. Report progress to user
5. If plateau detected AND iterations > 3, offer to stop early

**Progress output after each iteration:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ITERATION 3/10 COMPLETE

Changes this round:
  • Updated bead-abc: Clarified acceptance criteria
  • Added bead-xyz: Missing edge case handling
  • Added dependency: bead-xyz → bead-abc

Total changes: 3
Cumulative changes: 12

Status: Continuing... (improvements still being found)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Plateau detection output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ITERATION 6/10 COMPLETE

Changes this round:
  • Minor wording tweak to bead-abc

Total changes: 1 (↓ from 3 last round)
Cumulative changes: 18

⚠️  PLATEAU DETECTED
Improvements are diminishing. Options:

[1] Continue anyway (3 iterations remaining)
[2] Stop here - ready for implementation
[3] Fresh session (start new CC session for fresh perspective)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 4. Loop Implementation

```python
iteration = 0
cumulative_changes = 0
last_change_count = float('inf')
plateau_count = 0

while iteration < max_iterations:
    iteration += 1

    # Spawn agent
    result = Task(
        subagent_type="general-purpose",
        model="opus",
        description=f"Refinement iteration {iteration}",
        prompt=AGENT_PROMPT
    )

    # Parse changes from result
    changes = parse_changes(result)
    cumulative_changes += len(changes)

    # Report progress
    print_progress(iteration, max_iterations, changes, cumulative_changes)

    # Plateau detection
    if len(changes) <= 1 and last_change_count <= 2:
        plateau_count += 1
    else:
        plateau_count = 0

    if plateau_count >= 2 and iteration >= 3:
        # Offer to stop
        choice = ask_user_plateau_options()
        if choice == "stop":
            break
        elif choice == "fresh":
            suggest_fresh_session()
            break

    last_change_count = len(changes)

# Final summary
print_final_summary(cumulative_changes, iteration)
```

### 5. Final Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REFINEMENT LOOP COMPLETE

Iterations run: 6
Total changes made: 18
  • Beads updated: 8
  • Beads added: 4
  • Dependencies added: 6

Plateau reached at iteration 6.

Next steps:
[1] Start implementation
[2] Fresh session + review (/plan-refinery context → review)
[3] Run idea wizard for more improvements
[4] View final beads (bd list)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Mode: Both (Plan → Beads → Refine)

If user selects "Both in sequence":

1. **Phase 1: Plan Improvement**
   - Run plan-improver loop (5 iterations)
   - Stop at plateau

2. **Phase 2: Convert to Beads**
   - User converts plan to beads (separate workflow or manual)
   - Or auto-convert if conversion workflow exists

3. **Phase 3: Bead Refinement**
   - Run bead-refiner loop (5 iterations)
   - Stop at plateau

## Running in Background

For long loops, consider running in background:

```bash
# The orchestrator can run this as a background task
Task(
    ...,
    run_in_background=True
)
```

User can check progress with `/tasks` or by reading output file.

## Success Criteria
- [ ] Mode detected or selected (beads vs plan)
- [ ] Iteration count configured
- [ ] Loop runs with progress reporting
- [ ] Plateau detection works (2+ low-change rounds)
- [ ] User offered early stop at plateau
- [ ] Final summary shows cumulative impact
- [ ] Clear next steps provided
