---
description: Active debugging companion for pipeline sessions
---

# /monitor

Active debugging companion for pipeline sessions. Watches tmux output, validates state files, reads iteration outputs in real-time, and verifies everything operates correctly.

Unlike `/sessions` which shows status snapshots, `/monitor` is a hands-on debugging companion that follows along as pipelines run.

## Usage

```
/monitor                    # Interactive: choose what to monitor
/monitor start             # Start a pipeline and actively watch it
/monitor attach            # Attach to running session and debug
/monitor validate          # Validate all state files for a session
/monitor watch             # Watch iterations complete in real-time
/monitor health            # Quick health check of a session
```

## Quick Start

```bash
# Start a ralph loop and watch it boot up
/monitor start

# Attach to an existing session and debug
/monitor attach my-session

# Quick health check
/monitor health my-session

# Watch iterations as they complete
/monitor watch my-session
```

## Key Features

- **Start & Watch**: Launches a pipeline and actively monitors startup, verifying all files are created
- **Attach & Debug**: Connects to a running session with full debugging context
- **Validate State**: Comprehensive validation of all state files (JSON validity, required fields, consistency)
- **Watch Iterations**: Polls for new iterations and reads outputs as they complete
- **Health Check**: Quick pass/fail check of all session resources

## What Gets Checked

```
.claude/locks/{session}.lock              # Lock: PID alive?
.claude/pipeline-runs/{session}/
├── state.json                            # Valid JSON? Required fields?
├── progress-{session}.md                 # Growing?
├── stage-NN-{stage}/iterations/NNN/
│   ├── context.json                      # Created? Has inputs/commands?
│   ├── output.md                         # Has content?
│   └── status.json                       # Valid decision?
└── parallel-NN-{block}/                  # Parallel block (if present)
    ├── manifest.json                     # Aggregated outputs
    ├── resume.json                       # Per-provider recovery hints
    └── providers/
        ├── claude/
        │   ├── progress.md               # Provider-isolated progress
        │   ├── state.json                # Provider-specific state
        │   └── stage-NN-{stage}/iterations/NNN/
        └── codex/
            ├── progress.md
            ├── state.json
            └── stage-NN-{stage}/iterations/NNN/
```

---

**Invoke the monitor skill for:** $ARGUMENTS
