# Bug Discovery

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

${CONTEXT}

First, read the progress file to see what previous iterations explored and found:
```bash
cat ${PROGRESS}
```

**Check for input context** (bug reports, areas of concern, or previous analysis):
```bash
# Initial inputs (CLI --input files)
jq -r '.inputs.from_initial[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading input: $file"
  cat "$file"
done

# Previous stage outputs (from multi-stage pipelines)
jq -r '.inputs.from_stage | to_entries[] | .value[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading previous stage: $file"
  cat "$file"
done

# Parallel block outputs (from multiple providers)
jq -r '.inputs.from_parallel | to_entries[] | .value[]' ${CTX} 2>/dev/null | while read file; do
  echo "Reading parallel output: $file"
  cat "$file"
done
```

I want you to sort of randomly explore the code files in this project, choosing code files to deeply investigate and understand and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, I want you to do a super careful, methodical, and critical check with "fresh eyes" to find any obvious bugs, problems, errors, issues, silly mistakes, etc.

**Do NOT fix the bugs.** Just document them—the bugs, the recommended fixes, and any changes you'd make.

Append what you find to the progress file. Include:
- Which files/areas you explored
- Any bugs you found (what the bug is, where it is, what the fix would be)
- Suspicious patterns worth investigating later
- What areas you intentionally skipped so future iterations don't repeat your work

Use ultrathink. Be methodical. Be critical.

## Write Result

After exploring, write your result to `${RESULT}` (set `signals.plateau_suspected` true when no further progress is likely):

```json
{
  "summary": "Brief summary of what you found",
  "work": {
    "items_completed": [],
    "files_touched": []
  },
  "artifacts": {
    "outputs": [],
    "paths": []
  },
  "signals": {
    "plateau_suspected": false,
    "risk": "low",
    "notes": ""
  }
}
```
