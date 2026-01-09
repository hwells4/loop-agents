# Questioning Guide

How to ask good questions. This is guidance, not a script.

## The Goal

Understand enough to write a spec that an AI coding agent can build from without asking follow-up questions.

## Question Categories

When you don't understand something, these are the types of things to ask about:

### Understanding the "What"
- What does the user actually do with this?
- What's the core flow from start to finish?
- What are the key screens/interfaces?
- What data needs to be stored/displayed?

### Understanding the "Why"
- What problem does this solve?
- Why now? What triggered this need?
- What happens if we don't build this?

### Understanding the "Who"
- Who uses this? (Be specific—not "users")
- Are there different user types with different needs?
- Who else is affected? (admins, other teams, etc.)

### Understanding Scope
- What's the minimum viable version?
- What's explicitly NOT included?
- What could wait for v2?

### Understanding Technical Shape
- What systems does this integrate with?
- Are there existing patterns to follow?
- What are the constraints? (performance, security, platform)

### Understanding Risk
- What could go wrong?
- What happens when X fails?
- What are the edge cases?

## How to Use AskUserQuestion

**Group related questions.** Don't ask 10 questions one at a time. Ask 2-4 per round.

**Provide options when helpful:**
```
1. How should users access this feature?
   A. New tab in the main navigation
   B. Button within existing dashboard
   C. Standalone page with direct URL
   D. Other (describe)
```

**Follow up on vague answers.** If user says "it should be easy to use," ask what that means specifically.

**Don't ask what you can infer.** If the user said "Stripe integration," don't ask "will this involve payments?"

## When to Stop

Stop when you can confidently answer:
- What is the user trying to accomplish?
- What are all the features needed?
- What are the acceptance criteria for each feature?
- What are the key technical considerations?
- What's out of scope?
- What could go wrong?

If you're guessing on any of these, ask more questions.

## Common Mistakes

**Asking too many questions:** 3 focused rounds beats 10 shallow ones.

**Asking checklist questions:** Don't ask about "business alignment" if the user is a solo developer.

**Not adapting:** If the user gives detailed technical context, don't ask basic "what is this" questions.

**Missing edge cases:** Always ask "what happens when X fails?" for integrations and user inputs.
