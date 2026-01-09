# PRD Template

Use this structure for all PRDs. Sections can be brief or detailed based on project complexity.

---

## Overview

**What we're building:** [1-2 sentences]

**Why:** [The problem this solves, who has this problem]

**Scope:** [Project-level PRD for full build / Feature PRD within existing project]

---

## User Stories

Group by user type or flow. Use this format:

**As a** [user type], **I want to** [action], **so that** [benefit].

Example:
- As a sales rep, I want to see all my upcoming calls in one view, so that I can prepare efficiently.
- As a manager, I want to see my team's call metrics, so that I can identify coaching opportunities.

Include:
- Happy path scenarios
- Key alternative flows
- Error states users might encounter

---

## Features

Group logically (by user flow, by module, etc.).

### [Feature Group 1 Name]

#### Feature 1.1: [Name]
**Description:** What it does from user's perspective.

**Acceptance Criteria:**
- [ ] Given [context], when [action], then [result]
- [ ] Given [context], when [action], then [result]
- [ ] [Edge case handling]

#### Feature 1.2: [Name]
...

### [Feature Group 2 Name]
...

---

## Technical Approach

High-level only. Enough for an AI agent to understand the shape, not implementation details.

**Architecture:**
- [Key components and how they connect]
- [Data flow]

**Integrations:**
- [External service]: [What we use it for]
- [External service]: [What we use it for]

**Key Technical Decisions:**
- [Decision]: [Why]

**Constraints:**
- [Technical limitation or requirement]

---

## Test Strategy

What types of testing matter for this project.

**Unit Tests:**
- [Component/module that needs unit tests]
- [Component/module that needs unit tests]

**Integration Tests:**
- [Integration point to test]
- [Integration point to test]

**E2E Scenarios:**
Key user flows that need end-to-end testing:
1. [Flow name]: [Brief description]
2. [Flow name]: [Brief description]

**Edge Cases to Test:**
- [Scenario that could break]
- [Scenario that could break]

---

## Out of Scope

Explicitly list what we are NOT building. This prevents scope creep.

- [Feature/capability we're not doing]
- [Feature/capability we're not doing]
- [Future consideration, not for this build]

---

## Open Questions

Things we still need to figure out. Include owner/next step if known.

- [ ] [Question] — [Who needs to answer / How we'll resolve]
- [ ] [Question]

---

## Notes

Optional section for:
- Links to relevant calls/discussions
- Reference materials
- Design mockups (if they exist)
- Related Linear projects/issues
