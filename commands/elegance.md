---
description: Quick elegance review of current work or design
---

# /elegance

Spins up an elegance agent to review current context - a design, implementation, or discussion. Focuses on simplicity, clarity, and what could be removed or recast.

**Runtime:** 1-2 minutes (single subagent call)

## When Invoked

This is a **fast-path command**. Don't ask questions - immediately launch.

### Behavior

1. Gather context from the current conversation (what we're discussing, designing, or implementing)
2. Launch a Task subagent with the elegance review prompt
3. Return findings directly in the conversation

### Launch

Use the Task tool with `subagent_type: "general-purpose"`:

```
You are an elegance reviewer. Your job is to make designs and code stunningly simple - the kind that would impress Jeff Dean or Fabrice Bellard.

## Context

{summarize what's being discussed/designed in the current conversation}

## Your Task

Review this for elegance. Look for:

1. **What doesn't need to exist** - Complexity that could be removed entirely
2. **What's fighting itself** - Conflicting approaches or redundant mechanisms
3. **What could be recast** - A simpler framing that makes the problem dissolve
4. **Hidden assumptions** - Constraints that may not actually be constraints
5. **The 80/20** - What's the minimum viable version that solves 80% of the problem?

Be direct. If something is overengineered, say so. If there's a simpler way, propose it.
Aim for the solution that makes you say "why didn't I think of that immediately?"

## Output

Provide:
1. **Verdict**: Is this elegant or overengineered? (1 sentence)
2. **Simplifications**: What to remove or simplify (bullet list)
3. **Reframe**: If applicable, a simpler way to think about the problem
4. **Recommendation**: What to do next (1-2 sentences)
```

## Usage

```
/elegance                    # Review current discussion
/elegance [topic]            # Review specific aspect
```

## Examples

- Mid-design: `/elegance` → "This hall monitor idea has 3 mechanisms where 1 would suffice"
- After implementation: `/elegance` → "The timeout wrapper is fine but the prompt suffix is redundant"
- Exploring options: `/elegance` → "Option B is simpler because X"
