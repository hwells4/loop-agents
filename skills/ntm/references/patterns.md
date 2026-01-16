<overview>
Common NTM workflows and best practices for multi-agent orchestration.
</overview>

<parallel_implementation>

**Pattern: Divide and conquer**

Spawn agents with different specializations:
```bash
# 3 Claude for analysis, 2 Codex for implementation
ntm spawn feature-x --cc=3 --cod=2

# Assign roles via prompts
ntm send feature-x --cc "Analyze the authentication module. Identify security issues and propose fixes. Do NOT implement yet."

ntm send feature-x --cod "Wait for Claude's analysis, then implement the recommended fixes. Write tests for each fix."
```

**Pattern: Redundant analysis**

Multiple agents analyze same problem for consensus:
```bash
ntm spawn security-audit --cc=3

ntm send security-audit --all "Independently review src/auth/ for security vulnerabilities. List findings with severity ratings."

# Later, collect and compare
ntm copy security-audit --all > findings.txt
```

</parallel_implementation>

<staged_workflow>

**Pattern: Plan → Implement → Review**

```bash
# Stage 1: Planning with Claude
ntm spawn project --cc=2
ntm send project --all "Create detailed implementation plan for user authentication feature"

# Collect plans
ntm save project -o plans/

# Stage 2: Implementation with Codex
ntm add project --cod=3
ntm send project --cod "Implement the authentication feature following the plan in plans/"

# Stage 3: Review with fresh Claude
ntm add project --cc=1
ntm send project --cc "Review the implementation. Check for bugs, security issues, and code quality."
```

</staged_workflow>

<monitoring_patterns>

**Pattern: Continuous monitoring**
```bash
# Terminal 1: Dashboard
ntm dashboard project

# Terminal 2: Activity stream (separate window)
ntm activity project -w --interval 1000
```

**Pattern: Check before proceeding**
```bash
# After sending prompts, wait for completion
ntm activity project  # Check states

# When all show "idle", collect outputs
ntm copy project --all
```

**Pattern: Robot mode for scripts**
```bash
#!/bin/bash
# Wait until all agents idle
while true; do
  states=$(ntm --robot-status | jq -r '.sessions[].agents[].state')
  if ! echo "$states" | grep -q "thinking\|generating"; then
    break
  fi
  sleep 5
done
echo "All agents complete"
```

</monitoring_patterns>

<output_collection>

**Pattern: Aggregate all outputs**
```bash
ntm save project -o ~/outputs/project/
# Creates timestamped files per pane
```

**Pattern: Extract only code**
```bash
ntm extract project --code --copy
# Extracts markdown code blocks to clipboard
```

**Pattern: Filter by pattern**
```bash
ntm copy project --all --pattern "ERROR|WARN"
# Only lines matching pattern
```

**Pattern: Compare agent approaches**
```bash
ntm diff project cc_1 cc_2 --code-only
# Diff code outputs between two Claude agents
```

</output_collection>

<checkpoint_patterns>

**Pattern: Before risky changes**
```bash
ntm checkpoint save project -m "before major refactor"

# Do the refactor
ntm send project --all "Refactor the database layer"

# If something goes wrong, you have the checkpoint
```

**Pattern: Iterative development**
```bash
# Checkpoint at each milestone
ntm checkpoint save project -m "auth complete"
ntm checkpoint save project -m "api complete"
ntm checkpoint save project -m "tests passing"
```

</checkpoint_patterns>

<agent_counts>

**Recommended configurations:**

| Task Type | Claude | Codex | Gemini | Total |
|-----------|--------|-------|--------|-------|
| Quick feature | 1 | 1 | 0 | 2 |
| Standard project | 2 | 2 | 0 | 4 |
| Complex feature | 3 | 2 | 1 | 6 |
| Large refactor | 4 | 4 | 2 | 10 |
| Maximum parallel | 5 | 5 | 3 | 13+ |

**Considerations:**
- More agents = more API costs
- Claude: Best for analysis, planning, complex reasoning
- Codex: Best for implementation, tests, code generation
- Gemini: Good for documentation, diverse perspectives

</agent_counts>

<prompt_strategies>

**Be specific about agent roles:**
```bash
# Good: Clear assignment
ntm send project --cc "You are the architect. Design the API structure."
ntm send project --cod "You are the implementer. Code what the architect designs."

# Bad: Vague
ntm send project --all "Work on the API"
```

**Prevent stepping on each other:**
```bash
# Assign specific files/areas
ntm send project --cc "Focus ONLY on src/api/. Do not modify other directories."
ntm send project --cod "Focus ONLY on src/tests/. Do not modify src/api/."
```

**Sequential coordination:**
```bash
# Agent 1 produces, Agent 2 consumes
ntm send project --cc "Write the specification to docs/spec.md"
# Wait...
ntm send project --cod "Implement according to docs/spec.md"
```

</prompt_strategies>

<cleanup_patterns>

**Pattern: Graceful shutdown**
```bash
ntm send project --all "Finish your current task and write a summary of your progress."
# Wait for completion
ntm save project -o ~/logs/final/
ntm kill project -f
```

**Pattern: Emergency stop**
```bash
ntm interrupt project  # Ctrl+C all agents
ntm checkpoint save project -m "emergency stop"
ntm kill project -f
```

</cleanup_patterns>
