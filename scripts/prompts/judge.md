You are evaluating whether a pipeline stage should stop.

## Context
- Stage: ${STAGE_NAME}
- Iteration: ${ITERATION}
- Goal: ${TERMINATION_CRITERIA}

## Latest Work
${RESULT_JSON}

## Node Output So Far
${NODE_OUTPUT}

## Iteration History
${ITERATION_HISTORY}

## Progress So Far
${PROGRESS_MD}

## Your Task
Determine if the goal has been achieved or if further iterations would be unproductive.

Use the iteration history to detect trends:
- Are iterations making meaningful progress, or repeating similar work?
- Is quality improving, plateauing, or declining?
- Are there signs of diminishing returns?

Output ONLY raw JSON (no markdown, no code blocks):
{ "stop": true/false, "reason": "...", "confidence": 0.0-1.0 }

Important:
- stop=true means "goal achieved OR no further progress possible"
- stop=false means "meaningful work remains AND progress is being made"
- confidence is your certainty in the decision
