# Writing Style Guide

This document captures writing patterns and anti-patterns based on documentation preferences.

## Anti-Patterns (Never Do These)

### AI Tells
These phrases immediately signal AI-generated content:

- "Run it Friday night, come back Monday morning"
- "Run it overnight"
- "Start it Friday evening, review Monday morning"
- "X iterations while you sleep"
- "Set and forget"
- "That's 38 iterations of autonomous work" (counting things for emphasis)
- "bulletproof" (marketing superlatives)

### Punctuation to Avoid

**Em-dashes (—):** Never use them. Restructure the sentence instead.
- Bad: "The stages are independent—one can use Claude for planning"
- Good: "The stages are independent, so one can use Claude for planning"
- Good: "The stages are independent. One can use Claude for planning"

**Semicolons:** Avoid. Use periods or restructure.

**Ellipses (...):** Don't use them.

### Sentence Structure Problems

**Choppy robot sentences:** Two short sentences that should be one compound sentence.
- Bad: "Two-agent consensus means both must independently agree before stopping. Prevents one agent from calling it done too early."

**The "not X, not Y, it's Z" pattern:** Classic AI tell.
- Bad: "It's not about speed. It's not about cost. It's about quality."
- Good: Just say what it's about.

### Structural Anti-Patterns

**"The Problem / The Solution" template:** Too formulaic.

**Numbered philosophy lists with bold headers:**
- Bad: "1. **Fresh > stale.** A new agent beats an old one. 2. **Consensus > confidence.** One agent's done is another's wait."
- Good: Write prose that explains the concepts naturally.

### Content Anti-Patterns

**Over-explaining why:** Don't explain why Ralph loops are good. People reading this already know. Explain what YOUR thing adds.

**Manual instructions for plugin users:** If it's a Claude Code plugin, users won't manually create files. They'll use slash commands. Don't tell them to mkdir.

## Patterns (Do These)

### Voice and Tone

- Paul Graham style: simple, direct, conversational
- Practical: "here is what it does" said concisely
- No hedging, no fluff
- Professional but not formal

### Sentence Structure

Use proper compound sentences that flow naturally:
- "Each stage in a pipeline is its own Ralph loop. It takes inputs, manages its own state, and when it finishes, passes outputs and accumulated learnings to the next stage."

### Lists and Bullets

Bold the key term, then describe:
- **Loop on anything.** Each stage can iterate on plan files, task queues, codebases, URL lists, CSVs. Whatever.
- **Chain stages together.** Planning → task refinement → implementation.

Keep descriptions punchy. End with "Whatever." or similar if it adds voice.

### Tables

Use tables for reference information:
- Commands and their purposes
- Built-in stages/pipelines
- Configuration options

### Visual Structure

ASCII diagrams with boxes work well for showing flow:
```
┌─────────────────┐     ┌─────────────────┐
│ Stage 1         │     │ Stage 2         │
│ ─────────────── │ ──▶ │ ─────────────── │
│ Plan            │     │ Implement       │
└─────────────────┘     └─────────────────┘
```

### Document Structure

1. **Start with what it is** (one line)
2. **Bullet the key features** (what it lets you do)
3. **Show an example** (visual diagram)
4. **Explain the concepts** (how it works)
5. **Reference tables** (what's built-in)
6. **Getting Started** (actionable steps at the end, can repeat install instructions)

### Getting Started Sections

Put practical "here's what to do" at the end after concepts are explained:
```
## Getting Started

[install commands]

Then in Claude Code:
1. `/sessions plan` - describe your feature, get a PRD and tasks
2. `/refine` - iterate on the plan until two agents agree it's solid
3. `/ralph` - implement the tasks until the queue is empty

Pipelines run in tmux, so they keep going even if you close Claude Code.
```

## Quick Checklist

Before finalizing documentation:

- [ ] No em-dashes
- [ ] No semicolons
- [ ] No "sleep on it" / "overnight" language
- [ ] No choppy two-sentence patterns that should be compound
- [ ] No "not X, not Y, it's Z" constructions
- [ ] No Problem/Solution structure
- [ ] No numbered philosophy lists
- [ ] Compound sentences flow naturally
- [ ] Tables for reference info
- [ ] Getting Started at the end with concrete steps
