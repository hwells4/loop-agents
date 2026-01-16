# Workflow: Send Prompts to Agents

<required_reading>
**Read these reference files NOW:**
1. references/commands.md (agent management section)
2. references/patterns.md (prompt strategies)
</required_reading>

<process>

## Step 1: Check Session Status

```bash
ntm activity {session}
```

Ensure agents are in "idle" state before sending prompts.

## Step 2: Choose Target

**Options:**
- `--all` - All agents receive the prompt
- `--cc` - Only Claude agents
- `--cod` - Only Codex agents
- `--gmi` - Only Gemini agents

## Step 3: Send Prompt

**To all agents:**
```bash
ntm send {session} --all "Your prompt here"
```

**To specific agent type:**
```bash
ntm send {session} --cc "Analyze the codebase structure"
ntm send {session} --cod "Implement the user authentication"
```

**Multi-line prompts (use quotes and newlines):**
```bash
ntm send {session} --cc "Task: Review security
Files: src/auth/
Output: List vulnerabilities with severity"
```

## Step 4: Monitor Delivery

```bash
ntm activity {session}
```

Agents should transition from "idle" → "thinking" → "generating".

## Step 5: Wait for Completion

Watch until all targeted agents return to "idle":
```bash
ntm activity {session} -w
```

Or use dashboard for visual monitoring:
```bash
ntm dashboard {session}
```

</process>

<prompt_patterns>

**Assign specific roles:**
```bash
ntm send {session} --cc "You are the architect. Design the API structure. Do NOT implement."
ntm send {session} --cod "You are the implementer. Wait for the architect's design, then code it."
```

**Assign specific files:**
```bash
ntm send {session} --cc "Focus ONLY on src/api/. Do not modify other directories."
ntm send {session} --cod "Focus ONLY on tests/. Do not modify src/."
```

**Sequential handoff:**
```bash
ntm send {session} --cc "Write the specification to docs/spec.md"
# Wait for completion...
ntm send {session} --cod "Implement according to docs/spec.md"
```

**Parallel analysis:**
```bash
ntm send {session} --all "Independently analyze src/auth/ for security issues. List findings."
```

</prompt_patterns>

<anti_patterns>

Avoid:
- Sending to "thinking" agents (wait for idle)
- Vague prompts without file/area scope
- Overlapping responsibilities (causes conflicts)
- Long prompts that fill context quickly

</anti_patterns>

<success_criteria>

Prompts sent successfully when:
- [ ] `ntm activity {session}` shows agents processing
- [ ] No error messages from send command
- [ ] Agents eventually return to "idle"
- [ ] Output visible in panes (check with `ntm copy`)

</success_criteria>
