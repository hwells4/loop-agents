why # Test Scanner

Read context from: ${CTX}
Progress file: ${PROGRESS}
Iteration: ${ITERATION}

${CONTEXT}

## Your Task

You are scanning this codebase for test coverage gaps. Each iteration, you bring fresh eyes to find what previous iterations might have missed.

### Step 1: Load Context

Read the progress file to see what's already been analyzed:
```bash
cat ${PROGRESS}
```

### Step 2: Detect Project Type

Identify the testing framework and structure:
```bash
# Check for common test configurations
ls -la jest.config.* pytest.ini setup.cfg pyproject.toml Gemfile spec/ test/ tests/ __tests__/ 2>/dev/null | head -20

# Find existing test files
find . -type f \( -name "*_test.*" -o -name "*.test.*" -o -name "*_spec.*" -o -name "*.spec.*" -o -name "test_*.*" \) 2>/dev/null | head -30
```

### Step 3: Pick an Unexplored Area

Based on the progress file, choose an area NOT YET thoroughly examined. Rotate through these categories:

1. **Core Business Logic** - The main functionality of the application
2. **API Endpoints / Controllers** - Request handlers and routing
3. **Data Access / Models** - Database interactions and data models
4. **Utilities / Helpers** - Shared utility functions
5. **Error Handling Paths** - Exception handling and edge cases
6. **Integration Points** - Code that connects to external services

### Step 4: Scan for Gaps

For each source file in your chosen area:

1. **Find the source file:**
   ```bash
   # Example: find source files in a directory
   find src/ -name "*.ts" -o -name "*.js" | head -20
   ```

2. **Check if tests exist:**
   - Look for corresponding test file (same name with test/spec suffix)
   - Check if the test file actually tests the functions in the source

3. **Document gaps:**
   - Untested functions/classes (no test at all)
   - Missing edge cases (happy path only)
   - Missing error handling tests
   - Missing integration tests for boundary code

### Step 5: Update Progress

Append your findings to the progress file:

```markdown
## Iteration ${ITERATION} - Test Scanner

### Area Explored
[Which area you focused on]

### Test Gaps Found

| Source File | Gap Type | Description | Priority |
|-------------|----------|-------------|----------|
| path/to/file.ts | Untested | functionName() has no tests | High |
| path/to/other.ts | Edge Case | missing null input handling | Medium |

### Files with Good Coverage
[List files that are well-tested so future iterations can skip them]

### Recommendations
[Specific tests that should be added]
```

### Step 6: Write Result

After scanning, write your result to `${RESULT}` (set `signals.plateau_suspected` true when major areas are covered and remaining gaps are documented):

```json
{
  "summary": "One paragraph describing what gaps you found this iteration",
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

**Priority guide for gaps:**
- **Critical**: Core business logic with no tests
- **High**: Frequently modified code, error handling paths
- **Medium**: Utility functions, edge cases
- **Low**: Configuration, constants, simple getters/setters

Be thorough but focused. Document what you find and what you skip so the next iteration can pick up where you left off.
