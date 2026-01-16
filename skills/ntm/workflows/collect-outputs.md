# Workflow: Collect Agent Outputs

<required_reading>
**Read these reference files NOW:**
1. references/commands.md (output capture section)
2. references/patterns.md (output collection patterns)
</required_reading>

<process>

## Step 1: Wait for Agents to Complete

```bash
ntm activity {session}
```

Ensure agents are "idle" before collecting outputs.

## Step 2: Choose Collection Method

**Copy to clipboard:**
```bash
ntm copy {session} --all
```

**Save to files:**
```bash
ntm save {session} -o ~/outputs/
```

**Extract code blocks only:**
```bash
ntm extract {session} --code --copy
```

## Step 3: Collect All Outputs

**All agents to clipboard:**
```bash
ntm copy {session} --all
```

**All agents to files:**
```bash
ntm save {session} -o ~/project-outputs/
```

Creates timestamped files per pane.

## Step 4: Collect Specific Agent Types

**Claude agents only:**
```bash
ntm copy {session} --cc
```

**Codex agents only:**
```bash
ntm copy {session} --cod
```

**Single pane:**
```bash
ntm copy {session}:cc_1
```

## Step 5: Filter Output

**By line count:**
```bash
ntm copy {session} --all -l 1000
```

**By regex pattern:**
```bash
ntm copy {session} --all --pattern "TODO|FIXME"
ntm copy {session} --all --pattern "```[\s\S]*?```"  # Code blocks
```

**To file instead of clipboard:**
```bash
ntm copy {session} --all --output ~/output.txt
```

## Step 6: Extract Code Blocks

```bash
# All code blocks
ntm extract {session} --code --copy

# Specific language
ntm extract {session} --lang=python --copy

# Apply extracted code to files (dangerous!)
ntm extract {session} --apply
```

## Step 7: Compare Agent Outputs

```bash
ntm diff {session} cc_1 cc_2 --unified
ntm diff {session} cc_1 cod_1 --code-only
```

</process>

<robot_mode_collection>

For automation:

```bash
# Recent output as JSON
ntm --robot-tail={session}

# File changes with attribution
ntm --robot-files={session}

# Parse specific data
ntm --robot-tail={session} | jq '.panes[] | {name, last_output}'
```

</robot_mode_collection>

<output_organization>

**Recommended structure:**
```
outputs/
├── {session}/
│   ├── {timestamp}/
│   │   ├── cc_1.txt
│   │   ├── cc_2.txt
│   │   ├── cod_1.txt
│   │   └── summary.md
```

**Create summary:**
```bash
ntm save {session} -o outputs/{session}/
cd outputs/{session}/
# Manually review and create summary.md
```

</output_organization>

<success_criteria>

Output collection successful when:
- [ ] All agent outputs captured
- [ ] No truncation (use `-l` for more lines)
- [ ] Code blocks properly extracted
- [ ] Files saved with timestamps
- [ ] Can diff between agents

</success_criteria>
