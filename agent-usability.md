# Agent Usability Audit

**Analysis Date:** 2026-01-16
**Iterations:** 5
**Focus:** Optimizing agent-pipelines for autonomous agent consumption

---

## Executive Summary

Agent Pipelines is already well-designed for agent use with structured JSON outputs, context.json manifests, and clear termination strategies. However, several improvements would make the system significantly more agent-friendly. This document prioritizes 25 recommendations across 5 categories.

---

## Iteration 1: Scripts Architecture

### Token Efficiency Issues

| Priority | Issue | Current State | Recommendation |
|----------|-------|---------------|----------------|
| P0 | **Verbose bash output** | `run.sh` outputs human-readable tables | Add `--json` flag for machine-parseable output |
| P0 | **Status command prose** | `status` returns formatted text | Return structured JSON with `--json` flag |
| P1 | **List command formatting** | `list` returns ASCII table | Add JSON output mode |
| P1 | **Help text bloat** | `show_help()` is 40+ lines | Add `--brief` for one-liner summaries |
| P2 | **Dry-run markdown output** | Returns markdown tables | Add structured JSON alternative |

### Machine-Readable Gaps

| Priority | File | Issue | Fix |
|----------|------|-------|-----|
| P0 | `engine.sh` | Progress via echo statements | Emit structured events to events.jsonl |
| P0 | `provider.sh` | Execution logs mixed with output | Separate stderr logging from stdout results |
| P1 | `validate.sh` | Validation results as text | Return JSON with `{valid: bool, errors: []}` |
| P1 | `lock.sh` | Lock errors as prose | Return JSON error objects |

### Recommended New CLI Flags

```bash
# Global flags for agent consumption
--json              # Output structured JSON instead of prose
--quiet             # Suppress all non-essential output
--exit-code-only    # Communicate via exit codes, no stdout

# Examples
./scripts/run.sh status auth --json
./scripts/run.sh list --json
./scripts/run.sh lint --json
```

---

## Iteration 2: Prompt Templates

### Prompt Clarity Issues

| Priority | Stage | Issue | Recommendation |
|----------|-------|-------|----------------|
| P0 | All | **Mixed bash/JSON in prompts** | Standardize on context.json consumption pattern |
| P0 | `ralph/prompt.md` | Uses both `${CTX}` and inline paths | Consistently reference context.json for all paths |
| P1 | `improve-plan/prompt.md` | Fallback file discovery with `ls` | Provide explicit input paths in context.json |
| P1 | `elegance/prompt.md` | Vague "Use ultrathink" instruction | Define concrete exploration boundaries |
| P2 | Multiple | Inconsistent result.json vs status.json | Migrate all to result.json format |

### Result Schema Inconsistencies

Currently, prompts instruct agents to write either `status.json` or `result.json`:

**Old format (status.json):**
```json
{
  "decision": "continue",
  "reason": "...",
  "summary": "...",
  "work": {...},
  "errors": []
}
```

**New format (result.json):**
```json
{
  "summary": "...",
  "work": {...},
  "artifacts": {...},
  "signals": {
    "plateau_suspected": false,
    "risk": "low",
    "notes": ""
  }
}
```

**Recommendation:** Migrate all prompts to result.json format. The engine already handles both via `result.sh`, but prompts should be consistent.

### Missing Prompt Patterns

| Pattern | Description | Where Needed |
|---------|-------------|--------------|
| **Error recovery** | What to do when external commands fail | All implementation stages |
| **Context limits** | When to truncate/summarize for token efficiency | Long-running exploration stages |
| **Checkpoint signals** | How to signal partial completion | Multi-step implementation tasks |

---

## Iteration 3: CLI Interface

### Current CLI Strengths

- `context.json` provides comprehensive structured input
- `--provider` and `--model` allow runtime provider switching
- `--input` supports multiple input files
- `--context` enables prompt injection

### CLI Gaps for Agent Use

| Priority | Gap | Current Workaround | Proposed Solution |
|----------|-----|-------------------|-------------------|
| P0 | **No programmatic completion check** | Parse `status` output | `./scripts/run.sh poll SESSION --json` returning `{status, iteration, errors}` |
| P0 | **No structured error return** | Check exit codes | Return JSON errors on stderr with `--json` |
| P1 | **Events not streamable** | Tail events.jsonl manually | `./scripts/run.sh events SESSION --follow --json` |
| P1 | **No batch operations** | Loop over sessions | `./scripts/run.sh bulk-status SESSION1,SESSION2 --json` |
| P2 | **Missing discovery API** | Parse help output | `./scripts/run.sh discover --json` listing all stages/pipelines |

### Proposed Agent-Friendly Commands

```bash
# Poll session status (blocking until condition)
./scripts/run.sh wait SESSION --until=complete --timeout=3600

# Get structured session info
./scripts/run.sh info SESSION --json

# Stream events in real-time
./scripts/run.sh events SESSION --follow --format=jsonl

# Discover available resources
./scripts/run.sh discover stages --json
./scripts/run.sh discover pipelines --json

# Validate before execution
./scripts/run.sh validate loop ralph --json
./scripts/run.sh validate pipeline refine.yaml --json
```

---

## Iteration 4: Error Handling & Recovery

### Error Reporting Gaps

| Priority | Scenario | Current Behavior | Agent-Friendly Fix |
|----------|----------|------------------|-------------------|
| P0 | **Agent crash mid-iteration** | Lock orphaned, unclear state | Auto-cleanup + structured crash report in events.jsonl |
| P0 | **Provider timeout** | Generic timeout message | Structured timeout event with retry hints |
| P1 | **Missing dependencies** | Prose error message | JSON error with `{missing: ["bd", "jq"], install_cmd: "..."}` |
| P1 | **Lock conflicts** | Human-readable conflict message | JSON with `{conflict: true, holder_pid: N, age_seconds: N}` |
| P2 | **Validation failures** | List of text errors | JSON array with line numbers and fix suggestions |

### Recovery Workflow Issues

The `--resume` flag works well, but agents need better signals:

```bash
# Current: Agents must parse prose to understand crash state
./scripts/run.sh status auth
# "Session 'auth' failed at iteration 5/25"

# Proposed: Structured crash report
./scripts/run.sh crash-report auth --json
{
  "session": "auth",
  "status": "crashed",
  "last_successful_iteration": 4,
  "crash_iteration": 5,
  "crash_reason": "provider_timeout",
  "resumable": true,
  "resume_command": "./scripts/run.sh ralph auth 25 --resume"
}
```

### Beads Integration Error Handling

When `bd` commands fail, agents receive unclear errors:

```bash
# Current: bd errors mixed with agent output
bd update <bead-id> --status=in_progress
# Error: bead not found

# Proposed: Wrapper with structured errors
./scripts/lib/beads-wrapper.sh claim BEAD_ID --json
{
  "success": false,
  "error": "bead_not_found",
  "bead_id": "BEAD_ID",
  "suggestion": "Run 'bd ready --label=pipeline/SESSION' to list available beads"
}
```

---

## Iteration 5: Documentation & Discoverability

### Documentation Gaps

| Priority | Gap | Impact | Recommendation |
|----------|-----|--------|----------------|
| P0 | **No machine-readable API reference** | Agents can't discover capabilities | Add `api-reference.json` with all commands/flags |
| P0 | **Missing robot-mode stage** | Listed in CLAUDE.md but not implemented | Create `scripts/stages/robot-mode/` |
| P1 | **Inconsistent slash command docs** | Some in commands/, some in skills/ | Consolidate command reference |
| P1 | **No examples directory** | Agents lack concrete patterns | Add `examples/` with common workflows |
| P2 | **CLAUDE.md is 700+ lines** | Too much context for quick reference | Add `CLAUDE-QUICK.md` summary |

### Proposed API Reference Format

Create `docs/api-reference.json`:

```json
{
  "version": "1.0.0",
  "commands": {
    "run.sh": {
      "subcommands": {
        "status": {
          "args": ["session"],
          "flags": ["--json"],
          "returns": {"status": "string", "iteration": "int", "errors": "array"}
        },
        "list": {
          "args": ["count?"],
          "flags": ["--json"],
          "returns": {"sessions": "array"}
        }
      }
    }
  },
  "stages": {
    "ralph": {
      "termination": "fixed",
      "inputs": ["from_initial", "from_stage"],
      "outputs": ["result.json", "output.md"]
    }
  },
  "result_schema": {
    "summary": "string",
    "work": {"items_completed": "array", "files_touched": "array"},
    "artifacts": {"outputs": "array", "paths": "array"},
    "signals": {"plateau_suspected": "bool", "risk": "enum", "notes": "string"}
  }
}
```

### Missing Stage: robot-mode

CLAUDE.md documents `/robot-mode` but the stage doesn't exist. Create:

```yaml
# scripts/stages/robot-mode/stage.yaml
name: robot-mode
description: Analyze codebase for agent usability improvements

termination:
  type: fixed
  iterations: 3

delay: 2
output_path: docs/agent-usability-${SESSION}.md
```

---

## Priority Summary

### P0 - Critical for Agent Use (Do First)

1. Add `--json` flag to `status`, `list`, `lint` commands
2. Standardize all prompts on result.json format
3. Create structured error objects for all failure modes
4. Implement missing `robot-mode` stage
5. Add `poll`/`wait` command for blocking completion checks

### P1 - Significant Improvements

6. Separate stderr logging from stdout in provider.sh
7. Add `events` command with `--follow` for streaming
8. Create `discover` command for capability enumeration
9. Add `crash-report` command with structured output
10. Create beads wrapper with JSON error handling
11. Add `--quiet` and `--brief` flags globally
12. Consolidate slash command documentation

### P2 - Nice to Have

13. Add `--exit-code-only` mode
14. Create `bulk-status` for multiple sessions
15. Add dry-run JSON output mode
16. Create `CLAUDE-QUICK.md` summary
17. Add `examples/` directory with common patterns

---

## Implementation Roadmap

### Phase 1: CLI JSON Output (1-2 beads)
- Add `--json` flag parsing to run.sh
- Implement JSON formatters for status, list, lint
- Update engine.sh to emit structured events

### Phase 2: Prompt Standardization (1 bead)
- Migrate all prompts to result.json
- Add consistent error handling patterns
- Document result schema in prompts

### Phase 3: Error Handling (2 beads)
- Create structured error types
- Implement crash-report command
- Add beads-wrapper.sh with JSON errors

### Phase 4: Documentation (1-2 beads)
- Create api-reference.json
- Implement robot-mode stage
- Add examples/ directory

---

## Appendix: Context.json Reference

The existing context.json format is excellent for agents:

```json
{
  "session": "auth",
  "pipeline": "refine",
  "stage": {"id": "improve-plan", "index": 0, "template": "improve-plan"},
  "iteration": 3,
  "paths": {
    "session_dir": ".claude/pipeline-runs/auth",
    "stage_dir": ".claude/pipeline-runs/auth/stage-00-improve-plan",
    "progress": ".claude/pipeline-runs/auth/progress-auth.md",
    "output": ".claude/pipeline-runs/auth/stage-00-improve-plan/output.md",
    "status": ".../status.json",
    "result": ".../result.json"
  },
  "inputs": {
    "from_initial": [],
    "from_stage": {},
    "from_parallel": {}
  },
  "limits": {"max_iterations": 5, "remaining_seconds": -1},
  "commands": {"test": "npm test", "lint": "npm run lint"}
}
```

**Strengths:**
- All paths are absolute and explicit
- Inputs are structured by source
- Commands are project-configurable
- Limits provide iteration awareness

**No changes needed** - this is already agent-optimized.
