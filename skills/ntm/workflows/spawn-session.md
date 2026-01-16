# Workflow: Spawn Multi-Agent Session

<required_reading>
**Read these reference files NOW:**
1. references/commands.md (session creation section)
2. references/configuration.md (if custom config needed)
3. references/patterns.md (agent count recommendations)
</required_reading>

<process>

## Step 1: Verify NTM Installed

```bash
ntm deps -v
```

If not installed:
```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/ntm/main/install.sh | bash
eval "$(ntm init zsh)"
```

## Step 2: Check for Existing Sessions

```bash
ntm list
```

If session name already exists, either:
- Use different name
- Kill existing: `ntm kill {session} -f`

## Step 3: Determine Agent Configuration

**Quick reference:**

| Task Type | Claude | Codex | Gemini |
|-----------|--------|-------|--------|
| Simple task | 1 | 1 | 0 |
| Standard project | 2 | 2 | 0 |
| Complex feature | 3 | 2 | 1 |
| Large refactor | 4 | 4 | 2 |

## Step 4: Spawn Session

```bash
ntm spawn {session} --cc={N} --cod={N} --gmi={N}
```

Example:
```bash
ntm spawn auth-feature --cc=3 --cod=2
```

## Step 5: Verify Session Started

```bash
ntm status {session}
```

Expected output shows agent counts and pane names.

## Step 6: Attach to Session (Optional)

```bash
ntm attach {session}
```

Or use dashboard:
```bash
ntm dashboard {session}
```

</process>

<alternatives>

**Create empty session first, add agents later:**
```bash
ntm create {session} --panes=5
ntm add {session} --cc=3 --cod=2
```

**Quick project with scaffold:**
```bash
ntm quick {project} --template=python --cc=2 --cod=2
```

</alternatives>

<success_criteria>

Session spawned successfully when:
- [ ] `ntm status {session}` shows correct agent counts
- [ ] `ntm activity {session}` shows agents in "idle" state
- [ ] Panes are named correctly ({session}__cc_1, etc.)
- [ ] Can attach and see agent prompts

</success_criteria>
