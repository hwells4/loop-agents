# Provider Configuration Hierarchy

Add CLI and environment variable overrides for provider/model selection.

## Overview

Enable users to override provider (Claude/Codex) and model via CLI flags or environment variables without editing stage.yaml files.

## Problem Statement

Currently, provider configuration requires editing `stage.yaml`. Users need:
- One-shot overrides for testing with different providers
- Environment variable overrides for CI/CD
- No file editing for quick experimentation

## Proposed Solution

**4-level hierarchy (not 6):**

```
CLI Flags → Env Vars → Stage Config → Built-in Defaults
```

| Level | Source | Example |
|-------|--------|---------|
| 1. CLI Flags | `--provider=codex --model=o3` | One-shot overrides |
| 2. Env Vars | `CLAUDE_PIPELINE_PROVIDER=codex` | CI/CD, shell config |
| 3. Stage Config | `stage.yaml: provider: codex` | Already works |
| 4. Built-in | Hardcoded | `claude` / `opus` |

**What we're NOT building:**
- No new `config.sh` library
- No `defaults.yaml` file
- No run-level config files
- No provider immutability on resume

## Technical Approach

### File Changes

**Total: ~15 lines changed across 2 files**

#### 1. `scripts/run.sh` - Add flag parsing (~10 lines)

```bash
# Add to flag parsing loop (around line 30)
case "$arg" in
  --provider=*) export PIPELINE_CLI_PROVIDER="${arg#*=}" ;;
  --model=*) export PIPELINE_CLI_MODEL="${arg#*=}" ;;
  # ... existing flags
esac
```

#### 2. `scripts/engine.sh` - Respect precedence (4 lines changed)

```bash
# Replace line ~108 (single-stage model)
STAGE_MODEL=${PIPELINE_CLI_MODEL:-${CLAUDE_PIPELINE_MODEL:-$(json_get "$STAGE_CONFIG" ".model" "opus")}}

# Replace line ~115 (single-stage provider)
STAGE_PROVIDER=${PIPELINE_CLI_PROVIDER:-${CLAUDE_PIPELINE_PROVIDER:-$(json_get "$STAGE_CONFIG" ".provider" "claude")}}

# Replace line ~476 (pipeline default model)
local default_model=${PIPELINE_CLI_MODEL:-${CLAUDE_PIPELINE_MODEL:-$(json_get "$pipeline_json" ".defaults.model" "opus")}}

# Replace line ~477 (pipeline default provider)
local default_provider=${PIPELINE_CLI_PROVIDER:-${CLAUDE_PIPELINE_PROVIDER:-$(json_get "$pipeline_json" ".defaults.provider" "claude")}}
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_PIPELINE_PROVIDER` | Override provider (claude, codex) |
| `CLAUDE_PIPELINE_MODEL` | Override model (opus, o3, etc.) |

Existing `CODEX_MODEL` and `CODEX_REASONING_EFFORT` continue working unchanged.

## Usage Examples

```bash
# CLI override (highest precedence)
./scripts/run.sh ralph auth 25 --provider=codex --model=o3

# Environment override (CI/CD)
CLAUDE_PIPELINE_PROVIDER=codex ./scripts/run.sh ralph auth 25

# Combined
CLAUDE_PIPELINE_MODEL=sonnet ./scripts/run.sh ralph auth 25 --provider=claude

# Stage config (already works, unchanged)
# scripts/stages/my-stage/stage.yaml
# provider: codex
# model: gpt-5.2-codex

# Pipeline with mixed providers (already works)
# scripts/pipelines/my-pipeline.yaml
# defaults:
#   provider: claude
# stages:
#   - name: think
#     stage: improve-plan
#     provider: codex  # override for this stage
```

## Acceptance Criteria

- [ ] `--provider=X` flag overrides all other config
- [ ] `--model=X` flag overrides all other config
- [ ] `CLAUDE_PIPELINE_PROVIDER` env var overrides stage config
- [ ] `CLAUDE_PIPELINE_MODEL` env var overrides stage config
- [ ] Existing stage.yaml `provider:` field still works
- [ ] Pipeline `defaults.provider` still works
- [ ] `--help` shows new flags
- [ ] All existing tests pass

## Test Plan

Add to `scripts/tests/test_providers.sh`:

```bash
test_cli_provider_override() {
  export PIPELINE_CLI_PROVIDER="codex"
  # Verify codex is used
  unset PIPELINE_CLI_PROVIDER
}

test_env_provider_override() {
  export CLAUDE_PIPELINE_PROVIDER="codex"
  # Verify codex is used when no CLI flag
  unset CLAUDE_PIPELINE_PROVIDER
}

test_cli_overrides_env() {
  export PIPELINE_CLI_PROVIDER="codex"
  export CLAUDE_PIPELINE_PROVIDER="claude"
  # Verify codex wins (CLI > env)
  unset PIPELINE_CLI_PROVIDER CLAUDE_PIPELINE_PROVIDER
}
```

## Implementation Time

~30 minutes

## References

- `scripts/run.sh:24-39` - Existing flag parsing
- `scripts/engine.sh:108` - Model loading
- `scripts/engine.sh:115` - Provider loading
- `scripts/lib/provider.sh` - Provider abstraction (unchanged)
