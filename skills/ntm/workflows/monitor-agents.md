# Workflow: Monitor Agent Progress

<required_reading>
**Read these reference files NOW:**
1. references/commands.md (monitoring section)
2. references/patterns.md (monitoring patterns)
</required_reading>

<process>

## Step 1: Quick Status Check

```bash
ntm status {session}
```

Shows agent counts and session info.

## Step 2: Check Agent States

```bash
ntm activity {session}
```

States:
- `idle` - Waiting for input
- `thinking` - Processing prompt
- `generating` - Producing output
- `error` - Something went wrong
- `rate_limit` - API rate limited

## Step 3: Choose Monitoring Method

**For occasional checks:**
```bash
ntm activity {session}
```

**For continuous monitoring:**
```bash
ntm activity {session} -w --interval 1000
```

**For visual dashboard:**
```bash
ntm dashboard {session}
```

Dashboard features:
- Color-coded agent cards
- Token velocity badges
- Number keys (1-9) to select panes
- `c` to check context usage
- `r` to refresh

## Step 4: Health Check

```bash
ntm health {session}
```

Reports:
- Agent process status
- Context window usage
- Error states

## Step 5: Watch Specific Output

Stream output from specific agent type:
```bash
ntm watch {session} --cc --tail 50
```

## Step 6: Search Outputs

Find specific patterns across all panes:
```bash
ntm grep "ERROR" {session} -i
ntm grep "TODO" {session}
```

</process>

<robot_mode_monitoring>

For automation/scripting:

```bash
# Get JSON status
ntm --robot-status

# Get context usage
ntm --robot-context={session}

# Full state snapshot
ntm --robot-snapshot

# Parse with jq
ntm --robot-status | jq '.sessions[0].agents[] | {name, state}'
```

**Wait for completion script:**
```bash
#!/bin/bash
while true; do
  busy=$(ntm --robot-status | jq '[.sessions[].agents[] | select(.state != "idle")] | length')
  if [ "$busy" -eq 0 ]; then
    echo "All agents idle"
    break
  fi
  sleep 5
done
```

</robot_mode_monitoring>

<when_to_intervene>

**Interrupt if:**
- Agent stuck in "thinking" for 10+ minutes
- Agent producing nonsense output
- Wrong files being modified

```bash
ntm interrupt {session}
```

**Add more agents if:**
- Work is progressing slowly
- Need parallel analysis

```bash
ntm add {session} --cc=2
```

</when_to_intervene>

<success_criteria>

Monitoring successful when:
- [ ] Can see all agent states
- [ ] Can identify problems quickly
- [ ] Dashboard/activity updates in real-time
- [ ] Can grep for specific patterns
- [ ] Robot mode returns valid JSON

</success_criteria>
