# Plan: Unified Dry-Run, Validation, and Test System

> "Validate before you execute, test before you deploy."

## Overview

This plan unifies four related ideas into an elegant developer experience system:
1. **Lint** - Validate configurations before running
2. **Dry Run** - Preview exactly what will happen without executing
3. **Scaffolding** - Generate correct loop/pipeline structures
4. **Test Harness** - Fast iteration with mock Claude responses

## Design Principles

- Claude creates loops/pipelines, not humans - optimize for agent usage
- Fast feedback loops - seconds, not minutes
- Deterministic validation - catch errors before burning Claude credits
- Structured output - humans AND agents can quickly verify correctness

## Directory Structure

```
scripts/
├── run.sh                    # Entry point with new subcommands
├── engine.sh                 # Modified for mock injection
├── lib/
│   ├── validate.sh          # NEW: Core validation library
│   ├── dryrun.sh           # NEW: Dry run generation
│   ├── scaffold.sh         # NEW: Scaffolding templates
│   └── mock.sh             # NEW: Mock Claude responses
└── loops/
    └── {name}/
        ├── loop.yaml
        ├── prompt.md
        └── fixtures/        # NEW: Mock responses
            ├── iteration-1.txt
            ├── default.txt
            └── recorded/    # Captured real responses
```

---

## Component 1: Validation Library (`scripts/lib/validate.sh`)

The core validation module used by lint, dry-run, and scaffolding.

### API Design

```bash
source "$LIB_DIR/validate.sh"

# Validate a loop, returns JSON result
result=$(validate_loop "work")

# Validate a pipeline
result=$(validate_pipeline "full-refine")

# Check if result has errors
if has_errors "$result"; then
  print_validation_report "$result"
  exit 1
fi
```

### Validation Rules for Loops

| Rule ID | Check | Severity |
|---------|-------|----------|
| L001 | `loop.yaml` exists | error |
| L002 | YAML syntax is valid | error |
| L003 | `name` field present | error |
| L004 | `name` matches directory name | warning |
| L005 | `description` field present | warning |
| L006 | `completion` field present | error |
| L007 | Completion strategy file exists in `lib/completions/` | error |
| L008 | `prompt.md` or custom prompt exists | error |
| L009 | Plateau loops have `output_parse` with `plateau:PLATEAU` | error |
| L010 | Plateau loops have `min_iterations >= 2` | warning |
| L011 | Template variables are valid (from known set) | warning |
| L012 | No undefined template variables (typos) | warning |
| L013 | beads-empty loops have `check_before: true` | warning |

### Validation Rules for Pipelines

| Rule ID | Check | Severity |
|---------|-------|----------|
| P001 | Pipeline file exists | error |
| P002 | YAML syntax is valid | error |
| P003 | `name` field present | error |
| P004 | `stages` array present and non-empty | error |
| P005 | Each stage has `name` field | error |
| P006 | Stage names are unique | error |
| P007 | Each stage has `loop` or `prompt` | error |
| P008 | Referenced loops exist | error |
| P009 | `${INPUTS.stage-name}` references valid stage names | error |
| P010 | First stage does not use `${INPUTS}` | warning |
| P011 | Each stage has `runs` field | warning |
| P012 | Inline prompts have `completion` if `runs > 1` | warning |

---

## Component 2: Lint Command (`scripts/run.sh lint`)

### Usage

```bash
# Lint everything
./scripts/run.sh lint

# Lint specific loop
./scripts/run.sh lint loop work

# Lint specific pipeline
./scripts/run.sh lint pipeline full-refine

# JSON output for CI
./scripts/run.sh lint --json

# Strict mode (warnings are errors)
./scripts/run.sh lint --strict
```

### Output Format

**Human-readable (default):**
```
Validating loops...

  work
    [PASS] loop.yaml syntax valid
    [PASS] Required fields present
    [PASS] Completion strategy: beads-empty
    [WARN] L013: Should have check_before: true

  improve-plan
    [PASS] All checks passed

Validating pipelines...

  full-refine
    [PASS] YAML syntax valid
    [PASS] All referenced loops exist
    [PASS] Variable flow correct

Summary: 3 targets, 1 warning, 0 errors
```

**JSON output (for CI):**
```json
{
  "passed": true,
  "targets": [
    {
      "type": "loop",
      "name": "work",
      "valid": true,
      "errors": [],
      "warnings": ["L013: Should have check_before: true"]
    }
  ],
  "summary": {
    "total": 3,
    "passed": 3,
    "warnings": 1,
    "errors": 0
  }
}
```

---

## Component 3: Dry Run Mode (`scripts/run.sh dry-run`)

### Purpose

Preview exactly what would happen without executing Claude or modifying files. Produces a structured document showing:
- Resolved prompts with all variables substituted
- Completion strategy and its configuration
- File paths that would be created/modified
- For pipelines: full stage sequence with data flow

### Usage

```bash
# Dry run a loop
./scripts/run.sh dry-run loop work my-session

# Dry run a pipeline
./scripts/run.sh dry-run pipeline full-refine.yaml my-project

# Output to file
./scripts/run.sh dry-run loop work auth > auth-preview.md
```

### Output Format

```markdown
# Dry Run: Loop work

**Session:** auth
**Max iterations:** 25
**Model:** opus
**Completion:** beads-empty

## Configuration

| Field | Value |
|-------|-------|
| name | work |
| description | Implement features from beads until done |
| completion | beads-empty |
| check_before | true |
| delay | 3 |

## Files

| Purpose | Path |
|---------|------|
| State file | .claude/state.json |
| Progress file | .claude/loop-progress/progress-auth.md |
| Completions log | .claude/loop-completions.json |

## Resolved Prompt (Iteration 1)

```markdown
# Autonomous Agent

## Context

Session: auth
Progress file: .claude/loop-progress/progress-auth.md
...
```

## Completion Strategy

**Strategy:** beads-empty

The loop will stop when:
- `bd ready --label=loop/auth` returns 0 results

## Data Flow Diagram

```
┌─────────────────┐
│ Iteration 1     │
│ Model: opus     │
└────────┬────────┘
         │ Updates progress file
         │ Closes beads
         ▼
┌─────────────────┐
│ Iteration 2     │
│ (reads progress)│
└────────┬────────┘
         ▼
        ...
         ▼
┌─────────────────┐
│ Completion      │
│ beads empty     │
└─────────────────┘
```

## Validation

[PASS] All checks passed
```

---

## Component 4: Scaffolding (`scripts/run.sh init`)

### Purpose

Generate correctly-structured loop or pipeline files that Claude can then populate. Designed for Claude (the pipeline-builder skill) to use, not humans.

### Usage

```bash
# Scaffold a new loop
./scripts/run.sh init loop my-new-loop

# Scaffold with specific completion strategy
./scripts/run.sh init loop my-loop --completion plateau

# Scaffold a pipeline
./scripts/run.sh init pipeline my-pipeline
```

### Generated Loop Structure

Creates `scripts/loops/my-loop/`:

**loop.yaml:**
```yaml
name: my-loop
description: TODO - describe what this loop does
completion: plateau
min_iterations: 2
output_parse: "plateau:PLATEAU reasoning:REASONING"
model: opus
delay: 3
```

**prompt.md:**
```markdown
# TODO: Agent Name

Session: ${SESSION_NAME}
Progress file: ${PROGRESS_FILE}
Iteration: ${ITERATION}

## Your Task

TODO: Describe what the agent should do each iteration.

## Completion Output

At the END of your response:

```
PLATEAU: true/false
REASONING: [Your explanation]
```
```

**fixtures/default.txt:**
```
This is a mock response for testing.

PLATEAU: false
REASONING: Mock response - would continue in real execution
```

---

## Component 5: Test Harness (`scripts/run.sh test`)

### Purpose

Run loops and pipelines with mock Claude responses for fast iteration on loop development.

### Usage

```bash
# Test a loop with fixtures
./scripts/run.sh test loop work

# Test with recording (captures real responses for future tests)
./scripts/run.sh test loop work --record

# Test specific iterations
./scripts/run.sh test loop work --iterations 3

# Verbose output (show prompts sent)
./scripts/run.sh test loop work --verbose
```

### Fixture System

```
fixtures/
├── iteration-1.txt    # Response for iteration 1
├── iteration-2.txt    # Response for iteration 2
├── default.txt        # Fallback if no specific fixture
└── recorded/          # Captured real responses (--record)
    └── 2026-01-10-150000/
```

### Mock Response Selection

1. Check for `fixtures/iteration-{N}.txt`
2. Fall back to `fixtures/default.txt`
3. If neither exists, generate minimal valid response based on completion strategy

### Test Output

```
Testing loop: work
Session: test-20260110-150000
Mode: mock (fixtures from scripts/loops/work/fixtures/)

Iteration 1:
  Prompt: 1,234 chars
  Fixture: iteration-1.txt
  Response: 456 chars
  Parsed: {changes: 5}

Iteration 2:
  Prompt: 1,456 chars
  Fixture: default.txt
  Response: 234 chars
  Parsed: {plateau: false}

Completion: plateau detected at iteration 3
Duration: 0.8s

Prompts saved to: .claude/test-runs/work-test-20260110-150000/prompts/
```

---

## Pipeline-Builder Integration

The pipeline-builder skill should run validation automatically after creating configurations.

### Updated Verification Protocol

After the skill creates a loop or pipeline:

1. **Lint the configuration**
   ```bash
   ./scripts/run.sh lint loop {name}
   ```

2. **Generate dry-run preview**
   ```bash
   ./scripts/run.sh dry-run loop {name} test-session
   ```

3. **Run test if fixtures exist**
   ```bash
   ./scripts/run.sh test loop {name} --iterations 2
   ```

4. **Report results to user**

---

## Implementation Phases

### Phase 1: Validation Library
- Create `scripts/lib/validate.sh` with core validation functions
- Implement loop validation rules (L001-L013)
- Implement pipeline validation rules (P001-P012)

### Phase 2: Lint Command
- Extend `scripts/run.sh` with `lint` subcommand
- Human-readable and JSON output formats
- `--strict` and `--all` flags

### Phase 3: Dry Run Mode
- Create `scripts/lib/dryrun.sh`
- `dry_run_loop()` with full report generation
- `dry_run_pipeline()` with data flow diagram

### Phase 4: Scaffolding
- Create `scripts/lib/scaffold.sh`
- Templates for each completion strategy
- Generate default fixtures

### Phase 5: Test Harness
- Create `scripts/lib/mock.sh` with mock/record modes
- Modify `execute_claude()` for mock injection
- Fixture loading and minimal response generation

### Phase 6: Pipeline-Builder Integration
- Update verification protocol
- Add automated validation to workflows

---

## Success Criteria

- [ ] Lint catches common errors (missing fields, invalid strategies, undefined variables)
- [ ] Dry run shows resolved prompts, file paths, data flow
- [ ] Scaffolding generates loops that pass lint without modification
- [ ] Tests complete in under 2 seconds with mock responses
- [ ] Recording captures real responses as reusable fixtures
- [ ] CI ready: `./scripts/run.sh lint --json` returns proper exit codes
- [ ] Pipeline-builder runs validation automatically after creation

---

## Critical Files

| File | Purpose |
|------|---------|
| `scripts/run.sh` | Entry point - needs new subcommands |
| `scripts/engine.sh` | Core execution - needs mock injection point |
| `scripts/lib/resolve.sh` | Template resolution - reuse in dry-run |
| `skills/pipeline-builder/SKILL.md` | Needs updated verification protocol |
