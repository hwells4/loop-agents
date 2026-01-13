# CI/CD Test Failure Patterns

Common reasons tests pass locally but fail in CI (or vice versa).

## Environment Drift

### Operating System Differences

| Issue | Local | CI | Fix |
|-------|-------|----|----|
| Path separators | `\` (Windows) | `/` (Linux) | Use `path.join()` |
| Case sensitivity | Insensitive (macOS) | Sensitive (Linux) | Consistent casing |
| Line endings | CRLF (Windows) | LF (Linux) | `.gitattributes` |
| File permissions | 755 | 644 | Explicit `chmod` in CI |

### Timezone Issues

```javascript
// PROBLEM: Assumes local timezone
expect(formatDate(date)).toBe("1/15/2025");

// FIX: Use UTC or mock timezone
expect(formatDate(date)).toBe("2025-01-15T00:00:00.000Z");

// OR: Set TZ in CI
// env:
//   TZ: America/New_York
```

### Locale Issues

```javascript
// PROBLEM: Locale-dependent formatting
expect(formatNumber(1000)).toBe("1,000");  // US
// Fails in Germany: "1.000"

// FIX: Specify locale explicitly
expect(formatNumber(1000, 'en-US')).toBe("1,000");
```

## Resource Constraints

### Memory Limits

CI runners have fixed memory (often 2-4GB). Watch for:
- Large array allocations
- Image processing
- Memory leaks in tests
- Too many parallel tests

**Detection:**
```bash
# Monitor memory in CI
node --expose-gc --max-old-space-size=4096 test.js
```

### Port Conflicts

```javascript
// PROBLEM: Hardcoded port
const server = app.listen(3000);

// FIX: Dynamic port
const server = app.listen(0);  // OS assigns available port
const { port } = server.address();
```

### Disk Space

CI runners have limited disk. Watch for:
- Temporary files not cleaned up
- Large test artifacts
- Log file accumulation

## Timing Issues

### Tight Timeouts

```javascript
// PROBLEM: Works on fast local machine
await waitFor(() => element.isVisible(), { timeout: 100 });

// FIX: Generous timeouts for CI
await waitFor(() => element.isVisible(), { timeout: 5000 });

// BETTER: Environment-aware timeouts
const TIMEOUT = process.env.CI ? 10000 : 1000;
```

### Sleep-Based Synchronization

```javascript
// PROBLEM: Race condition
triggerAsyncOperation();
await sleep(100);
expect(result).toBe("done");

// FIX: Condition-based waiting
await waitFor(() => result === "done");
```

### Parallel Test Interference

```javascript
// PROBLEM: Tests share database
// Test A: INSERT user 'test@example.com'
// Test B: INSERT user 'test@example.com' → FAILS (duplicate)

// FIX: Unique test data per worker
const email = `test-${process.env.JEST_WORKER_ID}@example.com`;
```

## Missing Dependencies

### System Tools

```javascript
// PROBLEM: Assumes ImageMagick installed
exec("convert input.png output.jpg");

// FIX: Check availability or mock
if (!which("convert")) {
  console.warn("ImageMagick not found, skipping test");
  return;
}
```

### Services

```javascript
// PROBLEM: Assumes Redis available
const redis = new Redis("localhost:6379");

// FIX: Use testcontainers or mock
const container = await new GenericContainer("redis:7").start();
const redis = new Redis(container.getHost(), container.getMappedPort(6379));
```

## Network Issues

### External API Calls

```javascript
// PROBLEM: Calls real API
const response = await fetch("https://api.stripe.com/...");

// Issues:
// - Rate limiting
// - Network failures
// - API changes
// - Cost (paid APIs)

// FIX: Mock external APIs
jest.mock("stripe");
// OR: Use VCR pattern to record/replay
```

### DNS Resolution

CI environments may have different DNS or firewall rules.

```javascript
// PROBLEM: Assumes localhost resolves
fetch("http://localhost:3000");

// FIX: Use 127.0.0.1 explicitly
fetch("http://127.0.0.1:3000");
```

## Secret Management

### Missing Secrets

```yaml
# Secrets not available in PR from forks (security feature)
# Tests that need secrets will fail on external PRs

# FIX: Skip tests that need secrets when not available
if (!process.env.API_KEY) {
  console.warn("API_KEY not set, skipping integration tests");
  return;
}
```

### Hardcoded Credentials

```javascript
// PROBLEM: Works locally with hardcoded key
const apiKey = "sk_test_abc123";

// FIX: Environment variable
const apiKey = process.env.STRIPE_TEST_KEY;
```

## Caching Issues

### Stale Dependencies

```yaml
# PROBLEM: Cache key doesn't include lockfile hash
cache:
  key: npm-cache  # Never invalidates!

# FIX: Content-based cache key
cache:
  key: npm-${{ hashFiles('package-lock.json') }}
```

### Outdated Cache

After major changes:
- Dependency manager version change
- Node/Python version change
- Major dependency updates

**Fix:** Clear cache manually or bump cache key version.

## Detection Checklist

Run this audit on your test suite:

```bash
# Hardcoded paths
grep -rE '"/Users/|"C:\\|"/home/' tests/

# Hardcoded ports
grep -rE ':\d{4}[^0-9]' tests/ | grep -v mock

# Time-sensitive tests
grep -rE 'Date\.now|new Date\(\)|setTimeout' tests/

# Locale-sensitive
grep -rE 'toLocaleString|toLocaleDateString|Intl\.' tests/

# External API calls
grep -rE 'fetch\(|axios\.|http\.get' tests/ | grep -v mock

# Environment assumptions
grep -rE 'process\.env\.' tests/
```

## CI Configuration Best Practices

```yaml
# GitHub Actions example
jobs:
  test:
    runs-on: ubuntu-latest
    env:
      TZ: UTC  # Explicit timezone
      CI: true  # Signal to tests
      NODE_ENV: test
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'  # Pin version
          cache: 'npm'

      - name: Install dependencies
        run: npm ci  # Clean install, not npm install

      - name: Run tests
        run: npm test
        timeout-minutes: 10  # Explicit timeout

      - name: Upload artifacts on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: test-results/
```

## Debugging CI Failures

1. **Enable debug logging:**
   ```yaml
   env:
     ACTIONS_STEP_DEBUG: true
     DEBUG: "*"
   ```

2. **Compare environments:**
   ```bash
   # In CI
   node --version
   npm --version
   uname -a
   env | sort
   ```

3. **Run locally in CI-like environment:**
   ```bash
   # Use act for GitHub Actions
   act -j test

   # Or Docker
   docker run -it --rm -v $(pwd):/app node:20 bash
   cd /app && npm ci && npm test
   ```

4. **Bisect to find the breaking commit:**
   ```bash
   git bisect start
   git bisect bad HEAD
   git bisect good <last-known-good-commit>
   # Git will help find the breaking commit
   ```
