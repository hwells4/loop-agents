# Repository Guidelines

## Issue Tracking

This project uses **bd (beads)** for issue tracking.
Run `bd prime` for workflow context, or install hooks (`bd hooks install`) for auto-injection.

**Quick reference:**
- `bd ready` - Find unblocked work
- `bd create "Title" --type task --priority 2` - Create issue
- `bd close <id>` - Complete work
- `bd sync` - Sync with git (run at session end)

For full workflow details: `bd prime`

## Project Structure & Module Organization

The automation engine lives in `scripts/`: `run.sh` is the CLI entry point, `engine.sh` drives each iteration, and `lib/` holds reusable YAML/state helpers. Stage prompts plus stop criteria live in `scripts/stages/<stage>/{stage.yaml,prompt.md}`, while composed flows sit in `scripts/pipelines/*.yaml` with human-facing cues in `commands/`. Agent briefs live in `agents/`, durable references in `docs/`, reusable prompt snippets in `skills/`, and every regression fixture or shell suite belongs in `scripts/tests/` beside the logic it protects.

## Build, Test, and Development Commands

- `./scripts/run.sh pipeline bug-hunt.yaml overnight` — run the bundled multi-stage pipeline.
- `./scripts/run.sh loop ralph auth 25 --tmux` — kick off a single stage with persistent tmux output.
- `./scripts/run.sh lint [loop|pipeline] [name]` — schema-check stage or pipeline definitions.
- `./scripts/run.sh test [name] --verbose` or `scripts/tests/run_tests.sh --ci` — execute regression suites.
- `./scripts/run.sh status <session>` — inspect locks before resuming or forcing reruns.

## Coding Style & Naming Conventions

Bash is the canonical implementation language; keep shebangs at `#!/bin/bash`, enable `set -euo pipefail`, and favor snake_case helpers that declare locals explicitly. YAML uses two-space indents, lowercase kebab-case directories, and descriptive `description` lines surfaced by `run.sh`. Prompts and Markdown should stay imperative and concise, mirroring the `commands/*.md` tone.

## Testing Guidelines

Shell suites follow the `scripts/tests/test_*.sh` pattern and rely on fixtures under `scripts/tests/fixtures`. Add or update fixtures when state machines or prompt IO change, and lean on the shared helpers already sourced at the top of each test file for assertions. Always run `./scripts/run.sh test <target>` before submitting, and capture tmux output when validating new sessions.

## Commit & Pull Request Guidelines

Commits follow conventional prefixes seen in history (`feat:`, `docs:`, etc.) and should stay focused on one stage or helper tweak. Reference the bd issue ID in the commit body and PR description, summarize intent, list validation commands, and attach key CLI or tmux snippets for reviewer context. Call out every touched stage/pipeline so automation runners know which lint/test paths to rerun.
