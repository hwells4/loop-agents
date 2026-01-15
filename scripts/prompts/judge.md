You are evaluating whether a pipeline stage should stop.

## Context
- Stage: ${STAGE_NAME}
- Iteration: ${ITERATION}
- Goal: ${TERMINATION_CRITERIA}

## Latest Work
${RESULT_JSON}

## Node Output So Far
${NODE_OUTPUT}

## Progress So Far
${PROGRESS_MD}

## Your Task
Determine if the goal has been achieved or if further iterations would be unproductive.

Output exactly:
```json
{ "stop": true/false, "reason": "...", "confidence": 0.0-1.0 }
```

Important:
- stop=true means "goal achieved OR no further progress possible"
- stop=false means "meaningful work remains AND progress is being made"
- confidence is your certainty in the decision
