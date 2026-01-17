# Codex Playbook

Codex has full shell access in the Codex CLI but does **not** load Claude Code skills, slash commands, or repo hooks. Use this guide to run Agent Pipelines with Codex safely.

## Supported Capabilities

- Run any repo script directly (`./scripts/run.sh …`, `scripts/tests/run_tests.sh --ci`, etc.)
- Edit files inside the workspace and commit using git.
- Use the same pipelines as Claude by passing `--provider=codex` and `--model=<codex-model>` flags.

## Limitations Compared to Claude

- No slash commands (`/start`, `/sessions`, etc.) or skills from `skills/`.
- No automatic hook execution or tmux orchestration view; rely on CLI output.
- No parallel provider blocks with Claude + Codex simultaneously unless manually orchestrated outside the CLI.

## Running Pipelines with Codex

```bash
# Single-stage (Ralph) under Codex
./scripts/run.sh ralph auth 25 --provider=codex --model=gpt-5.2-codex

# Multi-stage pipeline
./scripts/run.sh pipeline refine.yaml my-session \
  --provider=codex \
  --model=gpt-5.2-codex

# Resume or force sessions the same way
./scripts/run.sh ralph auth 25 --resume --provider=codex
./scripts/run.sh ralph auth 25 --force --provider=codex
```

Guidelines:

- Use the same session names you would with Claude; state lives in `.claude/pipeline-runs/<session>/`.
- Codex cannot attach to tmux panes automatically; use `tmux attach -t pipeline-<session>` manually when needed.

## Environment Variables

Codex respects the same pipeline env vars:

- `CLAUDE_PIPELINE_PROVIDER=codex`
- `CLAUDE_PIPELINE_MODEL=gpt-5.2-codex` (or other codex models)
- `CLAUDE_PIPELINE_CONTEXT="..."` to inject extra instructions.

CLI flags override env vars, so prefer flags when invoking pipelines from Codex.

## Workflow Expectations

1. Follow `AGENTS.md` for planning, artifact, and proof-of-done rules.
2. Use repo commands (lint, test, pipeline) exactly as documented; do not rely on external tooling.
3. Capture verification commands and diffs in your final Codex response since there is no automatic skill output.

## Troubleshooting

- **Missing skills/commands**: Translate them to direct CLI calls (e.g., `/sessions list` → `./scripts/run.sh status <session>`).
- **Hooks not installed**: Run `bd hooks install` manually if needed; Codex will not auto-install.
- **Provider errors**: If the pipeline expects Claude-specific prompts, ensure the prompt is provider-agnostic or add Codex instructions to the prompt file before rerunning.

Keep this doc updated whenever new Codex capabilities or limitations emerge.
