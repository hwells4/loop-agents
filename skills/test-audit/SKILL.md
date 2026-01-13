---
name: test-audit
description: Comprehensive test suite audit for quality issues, anti-patterns, AI-generated test smells, test rot, CI/CD failures, and test data problems. Use when reviewing tests, after AI generates tests, when tests feel unreliable, or for periodic health checks.
---

## What This Skill Does

Analyzes existing tests to find:

**Individual Test Issues:**
1. **AI hardcoding** - Tests that assert exact outputs without understanding why
2. **Mock/reality mismatch** - Mocks that don't match actual implementations
3. **Test anti-patterns** - The Liar, The Giant, The Mockery, etc.
4. **Fixture problems** - Unrealistic data, magic values, missing edge cases
5. **Flaky test indicators** - Time-dependent, order-dependent, race conditions

**Structural Issues:**
6. **Test layer gaps** - Green units, dead system; missing integration coverage
7. **Test rot** - Obsolete tests, abandoned code, tests nobody understands
8. **CI/CD failures** - Works locally, fails in CI; environment drift

**Test Data Issues:**
9. **Data smells** - PII in fixtures, state leakage, shared mutable state
10. **Database isolation** - Transaction leaks, cleanup failures, parallel conflicts

**Suite Health:**
11. **Test debt** - Signs the suite is becoming a liability rather than an asset

This is NOT just about coverage. It's about whether your tests are trustworthy, maintainable, and actually catching bugs.

## When to Use

- After AI generates tests (validate they're not just "making it pass")
- When tests feel unreliable or flaky
- Before major refactoring (ensure tests will catch real bugs)
- Code review of test files
- Periodic test suite health check

## Red Flags to Detect

### 1. AI Hardcoding (Most Critical)

AI often writes tests that just assert whatever the code returns, without understanding intent.

**Symptoms:**
```javascript
// RED FLAG: Magic values with no explanation
expect(result).toBe("a]d8f2k9");
expect(hash).toBe("e3b0c44298fc1c149afbf4c8996fb924");

// RED FLAG: Exact object matching on generated data
expect(user).toEqual({
  id: "usr_1705123456789",
  createdAt: "2024-01-13T10:30:45.123Z"
});

// RED FLAG: Suspiciously specific numbers
expect(calculateScore(data)).toBe(847.3291);
```

**What good tests look like:**
```javascript
// GOOD: Tests the property, not the value
expect(result).toMatch(/^[a-z0-9]{10}$/);
expect(hash).toHaveLength(64);

// GOOD: Tests structure and relationships
expect(user.id).toMatch(/^usr_/);
expect(new Date(user.createdAt)).toBeInstanceOf(Date);

// GOOD: Tests behavior with known inputs
expect(calculateScore({ items: [], bonus: 0 })).toBe(0);
expect(calculateScore({ items: [10], bonus: 5 })).toBe(15);
```

### 2. Mock/Reality Mismatch

Mocks that return data the real implementation would never return.

**Symptoms:**
```javascript
// RED FLAG: Mock returns structure that doesn't match real API
mockApi.getUser.mockResolvedValue({ name: "Test" });
// But real API returns: { data: { user: { name: "...", email: "..." } } }

// RED FLAG: Mock never rejects
mockDb.query.mockResolvedValue([]);
// But real DB can throw connection errors

// RED FLAG: Mock has different error format
mockService.call.mockRejectedValue(new Error("fail"));
// But real service returns: { error: { code: "E001", message: "..." } }
```

**What to check:**
- Compare mock return values against actual API responses
- Ensure error mocks match real error formats
- Verify mock method signatures match real implementations

### 3. The Liar (Tests That Don't Test)

Tests that pass but don't actually verify anything meaningful.

**Symptoms:**
```javascript
// RED FLAG: No assertions
it("processes data", async () => {
  await processData(input);
});

// RED FLAG: Only checks it doesn't throw
it("handles user", () => {
  expect(() => handleUser(user)).not.toThrow();
});

// RED FLAG: Asserts on the mock, not the result
it("calls the API", () => {
  service.fetchUser("123");
  expect(mockApi.get).toHaveBeenCalled();
  // But never checks what was DONE with the response!
});
```

### 4. The Giant (Too Many Assertions)

Tests that verify multiple unrelated behaviors.

**Symptoms:**
```javascript
// RED FLAG: Testing everything in one test
it("user service works", () => {
  const user = service.create({ name: "Test" });
  expect(user.id).toBeDefined();
  expect(user.name).toBe("Test");
  expect(user.createdAt).toBeDefined();
  expect(service.count()).toBe(1);
  expect(service.findById(user.id)).toEqual(user);
  expect(service.findByName("Test")).toContain(user);
  service.delete(user.id);
  expect(service.count()).toBe(0);
});
```

**Should be split into:**
- `it("creates user with generated id")`
- `it("sets createdAt timestamp")`
- `it("can find user by id")`
- etc.

### 5. The Mockery (Over-Mocking)

Tests that mock so much they're not testing real behavior.

**Symptoms:**
```javascript
// RED FLAG: Mocking the thing you're testing
jest.mock("./calculator");
it("calculates", () => {
  Calculator.add.mockReturnValue(5);
  expect(Calculator.add(2, 3)).toBe(5); // What are we testing?!
});

// RED FLAG: Mocking internal implementation
jest.spyOn(service, "_privateHelper");
jest.spyOn(service, "_validateInput");
jest.spyOn(service, "_formatOutput");
```

### 6. Fixture Problems

**Symptoms:**
```javascript
// RED FLAG: Minimal fixtures that skip edge cases
const testUser = { name: "Test" };
// Missing: email, id, roles, edge cases

// RED FLAG: Magic values without explanation
const config = { threshold: 42, factor: 3.14159 };

// RED FLAG: Copy-pasted fixtures with no variation
const user1 = { id: "1", name: "Test", email: "test@test.com" };
const user2 = { id: "2", name: "Test", email: "test@test.com" };
const user3 = { id: "3", name: "Test", email: "test@test.com" };
```

### 7. Flaky Test Indicators

**Symptoms:**
```javascript
// RED FLAG: Time-dependent
expect(result.timestamp).toBe(Date.now());

// RED FLAG: Random without seeding
const id = generateId();
expect(id).toBe("abc123"); // Will fail randomly

// RED FLAG: Order-dependent
let counter = 0;
it("first test", () => { counter++; expect(counter).toBe(1); });
it("second test", () => { expect(counter).toBe(1); }); // Depends on first!

// RED FLAG: Async without proper waiting
setTimeout(() => { result = "done"; }, 100);
expect(result).toBe("done"); // Race condition
```

### 8. Green Units, Dead System (Test Layer Gaps)

All unit tests pass but the system doesn't work. This happens when units are tested in isolation but never verified to work together.

**Pattern A: Orphan Functions**
```javascript
// Unit test passes:
describe("validateEmail", () => {
  it("returns true for valid email", () => {
    expect(validateEmail("test@example.com")).toBe(true);
  });
});

// BUT: validateEmail is never actually called anywhere!
// The registration form uses a different validator.
```

**Pattern B: Missing Wiring Tests**
```javascript
// Unit tests pass for each piece:
// ✅ UserService.create() works
// ✅ EmailService.send() works
// ✅ AuditLogger.log() works

// BUT: No test verifies they're wired together:
// When a user is created, does it actually send the email?
// Does it actually log the audit event?
```

**Pattern C: Interface Drift**
```javascript
// Unit test mocks the dependency:
it("processes order", () => {
  mockPaymentService.charge.mockResolvedValue({ success: true });
  const result = await orderService.process(order);
  expect(result.status).toBe("completed");
});

// BUT: PaymentService.charge() signature changed!
// It now returns { charged: true, transactionId: "..." }
// Unit test passes, real system fails
```

**Pattern D: Call Path Gaps**
```javascript
// You have tests for:
// - Controller.handleRequest() ✅
// - Service.processData() ✅
// - Repository.save() ✅

// But no test verifies:
// Controller → Service → Repository actually chains correctly
// Maybe Controller calls wrong Service method
// Maybe Service doesn't call Repository at all
```

**How to detect:**

1. **Find untested call paths:**
```bash
# Find all function definitions
grep -r "function\|const.*=.*=>" src/

# Find all function calls in tests
grep -r "expect\|spy\|mock" tests/

# Compare: which functions are defined but never appear in test call chains?
```

2. **Check for integration test coverage:**
```bash
# If you only have unit tests and no integration tests, you likely have this problem
ls tests/unit/      # Many files
ls tests/integration/  # Empty or few files? RED FLAG
```

3. **Trace entry points:**
   - Find your API endpoints / CLI commands / event handlers
   - For each, verify there's a test that exercises the full path
   - Not mocked, actually calling through the layers

4. **Mock audit:**
   - List every mock in your test suite
   - For each mock, ask: "Is there an integration test that uses the real implementation?"
   - If answer is "no" for critical paths, you have this problem

**What good coverage looks like:**
```
Entry Point (API/CLI/Event)
    ↓
  [Integration Test] ← Verifies full path works
    ↓
Controller/Handler
    ↓
  [Unit Test] ← Verifies logic in isolation
    ↓
Service Layer
    ↓
  [Unit Test] ← Verifies logic in isolation
    ↓
Repository/External
    ↓
  [Contract Test] ← Verifies interface matches reality
```

**Minimum viable integration coverage:**
- Every public API endpoint has at least one integration test
- Every CLI command has at least one end-to-end test
- Every event handler has at least one test with real (or realistic fake) dependencies

### 9. The Inverse: Integration Without Units

Having integration tests but no unit tests creates different problems.

**Symptoms:**
```javascript
// Only integration tests exist:
it("user registration flow", async () => {
  const response = await request(app)
    .post("/register")
    .send({ email: "test@example.com", password: "password123" });

  expect(response.status).toBe(201);
});

// But no unit tests for:
// - Email validation logic
// - Password hashing
// - User model constraints
// - Edge cases (duplicate email, weak password, etc.)
```

**Problems:**
- Tests are slow (full stack for every scenario)
- Hard to test edge cases
- Failures are hard to diagnose (which layer broke?)
- Can't run tests in parallel easily

**Detection:**
```bash
# Check test execution time
time npm test

# If basic test suite takes > 30 seconds, likely over-relying on integration tests

# Check test type ratio
find tests -name "*.test.*" | wc -l  # Total tests
find tests/integration -name "*.test.*" | wc -l  # Integration tests
# If integration > 50% of total, investigate
```

### 10. Test Rot (Obsolete Tests)

Tests that no longer serve their purpose but remain in the codebase, creating maintenance burden and false confidence.

**Pattern A: Abandoned Tests**
```javascript
// RED FLAG: Tests for features that no longer exist
describe("LegacyPaymentGateway", () => {
  // This gateway was replaced 6 months ago
  // Tests still run and pass, providing zero value
});

// RED FLAG: Skipped tests with no explanation
it.skip("handles edge case");
xit("validates input");
// How long has this been skipped? Why?
```

**Pattern B: Tests Nobody Understands**
```javascript
// RED FLAG: Cryptic test with no context
it("returns 42", () => {
  expect(calculate(data)).toBe(42);
  // Why 42? What is this testing? Nobody knows.
});

// RED FLAG: Test name doesn't match behavior
it("validates user", () => {
  // Actually tests email formatting, not user validation
  expect(formatEmail("TEST")).toBe("test");
});
```

**Pattern C: Always-Pass Tests**
```javascript
// RED FLAG: Test that cannot fail
it("handles data", () => {
  const result = process(data) || defaultValue;
  expect(result).toBeDefined(); // Always true!
});

// RED FLAG: Catch-all that swallows failures
it("processes without error", async () => {
  try {
    await processData();
    expect(true).toBe(true);
  } catch {
    expect(true).toBe(true); // Passes even on error!
  }
});
```

**Detection:**
```bash
# Find tests not modified in 90+ days
find tests -name "*.test.*" -mtime +90

# Find skipped tests
grep -r "\.skip\|xit\|xdescribe\|@Disabled\|@Ignore" tests/

# Find tests with TODO/FIXME
grep -r "TODO\|FIXME\|HACK" tests/

# Check git blame for ancient tests
git log --oneline --since="6 months ago" -- tests/ | wc -l
# If very few commits, tests may be rotting
```

**Questions to ask:**
- When was this test last modified?
- Does anyone know what this test is supposed to verify?
- If this test was deleted, would anyone notice?
- Is the feature this tests still in the product?

### 11. CI/CD Environment Issues

Tests that pass locally but fail in CI, or vice versa.

**Pattern A: Environment Drift**
```javascript
// RED FLAG: OS-specific paths
const configPath = "C:\\Users\\dev\\config.json";
const configPath = "/Users/dev/config.json";
// Fails on Linux CI runners

// RED FLAG: Timezone assumptions
expect(formatDate(date)).toBe("1/15/2025");
// Fails when CI runs in UTC

// RED FLAG: Locale-dependent
expect(formatCurrency(1000)).toBe("$1,000.00");
// Fails in non-US locales
```

**Pattern B: Resource Assumptions**
```javascript
// RED FLAG: Hardcoded ports
const server = app.listen(3000);
// Fails if port in use on CI

// RED FLAG: File system assumptions
fs.writeFileSync("./temp/output.txt", data);
// Fails if ./temp doesn't exist in CI

// RED FLAG: Memory-intensive operations
const hugeArray = new Array(10_000_000).fill(0);
// OOM on resource-constrained CI runners
```

**Pattern C: Timing Issues**
```javascript
// RED FLAG: Tight timeouts
await waitFor(() => element.isVisible(), { timeout: 100 });
// CI is slower, needs more time

// RED FLAG: Sleep-based synchronization
await sleep(500);
expect(result).toBe("done");
// Works locally (fast), fails in CI (slow)
```

**Pattern D: Missing Dependencies**
```javascript
// RED FLAG: Assuming global tools
exec("convert image.png output.jpg");  // ImageMagick
exec("wkhtmltopdf page.html output.pdf");  // wkhtmltopdf
// Not installed in CI

// RED FLAG: Assuming services
const redis = new Redis("localhost:6379");
// No Redis in CI environment
```

**Detection checklist:**
- [ ] Any hardcoded file paths?
- [ ] Any hardcoded ports?
- [ ] Any timezone-sensitive assertions?
- [ ] Any locale-sensitive formatting?
- [ ] Any tight timeouts (<1s)?
- [ ] Any external tool dependencies?
- [ ] Any assumptions about available services?

### 12. Test Data Smells

Problems with how test data is created, managed, and cleaned up.

**Pattern A: PII in Fixtures (Compliance Risk)**
```javascript
// RED FLAG: Real-looking personal data
const testUser = {
  name: "John Smith",  // Could be a real person
  email: "john.smith@gmail.com",  // Could be real
  ssn: "123-45-6789",  // Valid SSN format
  phone: "555-123-4567"
};

// BETTER: Obviously fake data
const testUser = {
  name: "Test User 001",
  email: "test-001@test.invalid",
  ssn: "000-00-0000",  // Invalid format
  phone: "555-000-0000"  // Reserved test prefix
};

// BEST: Generated fake data
const testUser = {
  name: faker.person.fullName(),
  email: faker.internet.email({ provider: 'test.invalid' }),
  // etc.
};
```

**Pattern B: Shared Mutable State**
```javascript
// RED FLAG: Global state modified by tests
let globalCounter = 0;

it("test 1", () => {
  globalCounter++;
  expect(globalCounter).toBe(1);
});

it("test 2", () => {
  expect(globalCounter).toBe(0);  // Fails! State leaked from test 1
});

// RED FLAG: Shared fixture mutation
const sharedUser = { name: "Test", permissions: [] };

it("admin test", () => {
  sharedUser.permissions.push("admin");  // Mutates shared object!
});

it("user test", () => {
  expect(sharedUser.permissions).toEqual([]);  // Fails!
});
```

**Pattern C: Database State Leakage**
```javascript
// RED FLAG: No cleanup between tests
it("creates user", async () => {
  await db.users.create({ email: "test@example.com" });
  // No cleanup!
});

it("checks unique email", async () => {
  // Fails because user from previous test still exists
  await expect(
    db.users.create({ email: "test@example.com" })
  ).rejects.toThrow("duplicate");
});

// RED FLAG: Order-dependent database tests
it("first: seed data", async () => {
  await seedDatabase();
});

it("second: query data", async () => {
  const results = await db.query("...");
  expect(results).toHaveLength(10);  // Depends on first test!
});
```

**Pattern D: Fixtures Too Minimal or Too Maximal**
```javascript
// RED FLAG: Minimal fixture misses real-world complexity
const order = { total: 100 };
// Real orders have: items, shipping, tax, discounts, user, timestamps...

// RED FLAG: Maximal fixture obscures test intent
const order = {
  id: "ord-123",
  userId: "user-456",
  items: [{ id: "item-1", name: "Widget", price: 50, quantity: 2 }],
  shipping: { method: "express", cost: 15, address: {...} },
  billing: { card: {...}, address: {...} },
  discounts: [{ code: "SAVE10", amount: 10 }],
  tax: 8.50,
  total: 113.50,
  status: "pending",
  createdAt: "2025-01-15T10:00:00Z",
  updatedAt: "2025-01-15T10:00:00Z",
  // ... 20 more fields
};
// What is this test actually about? Hard to tell.

// GOOD: Factory with relevant overrides
const order = createOrder({ discounts: [tenPercentOff] });
// Clear: this test is about discount handling
```

**Detection:**
```bash
# Find potential PII patterns
grep -rE "[0-9]{3}-[0-9]{2}-[0-9]{4}" tests/  # SSN pattern
grep -rE "[a-z]+@(gmail|yahoo|hotmail)" tests/  # Real email providers

# Find global state
grep -r "^let \|^var " tests/  # Top-level mutable variables

# Find missing cleanup
grep -L "afterEach\|teardown\|cleanup" tests/**/*.test.*
```

### 13. Test Debt Indicators (Suite Becoming a Liability)

Signs that your test suite is costing more than it's worth.

**Warning Sign A: Ignored Failures**
```
Team behavior:
- "Just re-run it, that test is flaky"
- "Ignore the red, it's always like that"
- "We'll fix that test later" (never happens)
- Tests commented out instead of fixed
```

**Warning Sign B: Velocity Drain**
```
Symptoms:
- A one-line change requires updating 20+ tests
- Developers avoid certain areas because "tests are a nightmare"
- More time debugging tests than debugging code
- Tests break on unrelated changes
```

**Warning Sign C: False Confidence**
```
Symptoms:
- Tests pass but bugs reach production
- High coverage numbers but users still find bugs
- "All tests pass" but demo fails
- Tests pass on feature branch, fail on main
```

**Warning Sign D: Abandonment**
```
Symptoms:
- Tests marked as skip/pending for months
- Test files with no recent git commits
- Entire test directories nobody runs
- "I don't know what that test does"
```

**Quantitative Detection:**
```bash
# Flakiness rate (should be < 1%)
# Track: failures that pass on retry / total runs

# Test modification frequency
git log --since="3 months ago" --name-only -- tests/ | sort | uniq -c | sort -rn
# Tests modified frequently may be brittle

# Skipped test count
grep -rc "\.skip\|xit\|xdescribe" tests/ | awk -F: '$2>0'

# Test-to-code ratio
echo "Test lines: $(find tests -name '*.test.*' -exec wc -l {} + | tail -1)"
echo "Source lines: $(find src -name '*.ts' -exec wc -l {} + | tail -1)"
# Healthy ratio: 0.8:1 to 1.4:1
```

**Questions to diagnose test debt:**
1. How long does the test suite take to run?
   - Unit tests > 5 min → too slow
   - Full suite > 30 min → problematic
2. How often do tests fail for non-bug reasons?
   - > 5% flakiness → significant debt
3. When a test fails, how long to diagnose?
   - > 10 min → tests not providing value
4. How often are tests updated vs code?
   - Tests rarely updated → likely rotting

## Process

### 1. Identify Scope

Ask what to audit:
- Specific test file(s)?
- All tests in a directory?
- Tests for a specific feature?
- Recently AI-generated tests?

### 2. Read Tests and Source

For each test file:
1. Read the test file completely
2. Read the corresponding source file
3. Identify what's being mocked vs real

### 3. Check Each Test Against Red Flags

For each test, evaluate:
- [ ] Are assertions meaningful or just "whatever it returned"?
- [ ] Do mocks match real implementation signatures/responses?
- [ ] Is there at least one meaningful assertion?
- [ ] Is it testing one behavior or many?
- [ ] Are fixtures realistic and varied?
- [ ] Any time/random dependencies without controls?

### 4. Cross-Reference Mocks

For any mocked dependency:
1. Find the real implementation
2. Compare mock return values to real return values
3. Flag mismatches

### 5. Report Findings

Group findings by severity:

**Critical (Tests are lying):**
- AI hardcoded values that will break on any change
- Mocks that return impossible data
- Tests with no assertions

**High (Tests are fragile):**
- Flaky test indicators
- Over-mocking real behavior
- Giant tests that hide failures

**Medium (Tests could be better):**
- Minimal fixtures
- Testing implementation vs behavior
- Missing edge cases

**Low (Style issues):**
- Inconsistent naming
- Duplicated setup
- Poor organization

### 6. Suggest Fixes

For each issue, provide:
- What's wrong
- Why it matters
- How to fix it (with example)

## Output Format

```markdown
# Test Audit Report

## Summary
- Files audited: X
- Tests reviewed: Y
- Critical issues: N
- High issues: N
- Medium issues: N

## Critical Issues

### [filename:line] AI Hardcoded Assertion
**Test:** `it("generates token")`
**Problem:** Asserts exact token value `"abc123xyz"` which appears to be hardcoded from a single run
**Impact:** Test will fail when token generation changes, but won't catch actual bugs
**Fix:**
```javascript
// Instead of:
expect(token).toBe("abc123xyz");

// Use:
expect(token).toMatch(/^[a-z0-9]{9}$/);
expect(token).toHaveLength(9);
```

### [filename:line] Mock Returns Impossible Data
**Test:** `it("fetches user")`
**Problem:** Mock returns `{ name: "Test" }` but real API returns `{ data: { user: {...} } }`
**Impact:** Test passes but real code would fail on `response.data.user`
**Fix:** Update mock to match real API response structure

## High Issues
...

## Recommendations
1. ...
2. ...
```

## Success Criteria

**Individual Test Quality:**
- [ ] Identified AI hardcoding patterns
- [ ] Cross-referenced mocks against real implementations
- [ ] Flagged tests without meaningful assertions
- [ ] Noted fixture quality issues
- [ ] Identified flaky test patterns

**Structural Analysis:**
- [ ] Analyzed test layer balance (unit vs integration vs e2e)
- [ ] Identified orphan functions (tested but never called)
- [ ] Verified critical paths have integration coverage
- [ ] Found test rot (obsolete, abandoned, skipped tests)

**Environment & Data:**
- [ ] Checked for CI/CD environment issues
- [ ] Audited test data for PII and compliance risks
- [ ] Identified state leakage between tests
- [ ] Verified database cleanup patterns

**Suite Health:**
- [ ] Assessed overall test debt level
- [ ] Identified signs of suite becoming a liability
- [ ] Measured key health metrics (flakiness, execution time)

**Deliverables:**
- [ ] Provided actionable fix suggestions
- [ ] Report organized by severity
- [ ] Prioritized recommendations

## References

- `references/anti-patterns.md` - Detailed anti-pattern detection heuristics
- `references/quick-checklist.md` - Rapid audit checklist
- `references/layer-analysis.md` - Test layer gap detection
- `references/ci-cd-issues.md` - CI/CD environment problem patterns
- `references/test-data.md` - Test data management patterns
