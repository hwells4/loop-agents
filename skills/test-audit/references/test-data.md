# Test Data Management Patterns

Common problems and best practices for test data.

## Test Data Strategies Comparison

| Strategy | Speed | Flexibility | Maintainability | Best For |
|----------|-------|-------------|-----------------|----------|
| **Fixtures** | Fast | Low | Low | Static reference data |
| **Factories** | Medium | High | High | Most test data needs |
| **Builders** | Medium | High | High | Complex domain objects |
| **Faker/Random** | Medium | Medium | High | Unique identifiers |

### When to Use Each

**Fixtures (Static JSON/YAML):**
- Reference data that rarely changes (countries, categories)
- Snapshot data for specific test scenarios
- Legacy test suites (migration path)

**Factories (FactoryBot, Fishery, etc.):**
- Most test data needs
- When you need variations per test
- When objects have relationships

**Builders:**
- Complex objects with many optional fields
- When tests should document relevant data only
- Domain-driven design contexts

**Faker/Random:**
- Unique identifiers to avoid collisions
- Realistic-looking but fake data
- Compliance requirements (no real PII)

## PII and Compliance

### Red Flags (Audit for These)

```javascript
// DANGEROUS: Real-looking personal data
const user = {
  name: "John Smith",           // Could match real person
  email: "john@gmail.com",      // Could be real email
  ssn: "123-45-6789",           // Valid SSN format
  phone: "+1-555-123-4567",     // Could be real
  creditCard: "4111111111111111" // Test card, but risky pattern
};
```

### Safe Patterns

```javascript
// SAFE: Obviously fake data
const user = {
  name: "Test User 001",
  email: "test-001@test.invalid",  // .invalid TLD never routes
  ssn: "000-00-0000",              // Invalid format
  phone: "555-000-0000",           // Reserved test prefix
};

// BETTER: Generated fake data
import { faker } from '@faker-js/faker';

const user = {
  name: faker.person.fullName(),
  email: faker.internet.email({ provider: 'test.invalid' }),
  ssn: faker.string.numeric(9),  // Random, not valid format
};
```

### Detection Commands

```bash
# Find potential SSN patterns
grep -rE "[0-9]{3}-[0-9]{2}-[0-9]{4}" tests/

# Find real email providers
grep -rE "@(gmail|yahoo|hotmail|outlook)\." tests/

# Find credit card patterns
grep -rE "[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}" tests/

# Find phone patterns
grep -rE "\+?1?[- ]?\(?[0-9]{3}\)?[- ]?[0-9]{3}[- ]?[0-9]{4}" tests/
```

## Database State Management

### Transaction Rollback (Fastest)

```ruby
# RSpec with Rails
RSpec.configure do |config|
  config.use_transactional_fixtures = true
end

# Each test runs in transaction, rolled back after
```

**Limitation:** Doesn't work with multiple database connections (e.g., Selenium tests).

### Deletion Strategy (Balanced)

```ruby
# DatabaseCleaner with deletion
config.before(:each) do
  DatabaseCleaner.strategy = :deletion
end

config.after(:each) do
  DatabaseCleaner.clean
end
```

**Better than truncation** for speed, works with foreign keys.

### Truncation Strategy (Slowest, Most Thorough)

```ruby
DatabaseCleaner.strategy = :truncation
```

**Use when:** You need to reset auto-increment counters or have complex constraints.

### Per-Worker Isolation (Parallel Tests)

```ruby
# Each parallel worker uses different database
database: myapp_test<%= ENV['TEST_ENV_NUMBER'] %>
```

Or schema-based isolation:
```sql
CREATE SCHEMA test_worker_1;
CREATE SCHEMA test_worker_2;
```

## State Leakage Detection

### Symptoms

```javascript
// Test A passes alone, fails when run with Test B
npm test -- tests/a.test.js  // PASS
npm test -- tests/b.test.js tests/a.test.js  // FAIL
```

### Common Causes

1. **Global variables modified:**
   ```javascript
   // Leaked state
   let cache = {};

   it("test 1", () => {
     cache.key = "value";  // Modifies global
   });

   it("test 2", () => {
     expect(cache).toEqual({});  // Fails!
   });
   ```

2. **Shared fixtures mutated:**
   ```javascript
   const user = { name: "Test", roles: [] };

   it("admin test", () => {
     user.roles.push("admin");  // Mutates shared object
   });
   ```

3. **Database not cleaned:**
   ```javascript
   it("creates user", async () => {
     await db.users.create({ email: "test@example.com" });
     // No cleanup
   });
   ```

4. **Singleton state:**
   ```javascript
   it("test 1", () => {
     Config.getInstance().setValue("key", "value");
   });

   it("test 2", () => {
     expect(Config.getInstance().getValue("key")).toBeUndefined();  // Fails!
   });
   ```

### Detection

```bash
# Randomize test order to expose dependencies
jest --randomize
rspec --order random
pytest --random-order

# Run tests in isolation
jest --runInBand  # Sequential, one process

# Bisect to find dependent tests
rspec --bisect
```

### Prevention

```javascript
// Reset state in beforeEach
beforeEach(() => {
  jest.resetModules();
  jest.clearAllMocks();
  cache = {};  // Reset global state
});

// Use fresh objects per test
const createUser = () => ({ name: "Test", roles: [] });

it("admin test", () => {
  const user = createUser();  // Fresh object
  user.roles.push("admin");
});
```

## External Dependencies

### Mock vs Real Decision Matrix

| Factor | Use Mocks | Use Real |
|--------|-----------|----------|
| Speed | Need fast tests | Can tolerate slower |
| Reliability | Unreliable service | Stable service |
| Cost | Expensive API | Free/low cost |
| Control | Need error scenarios | Need real behavior |
| Environment | No service in CI | Service available |

### Testcontainers Pattern

```javascript
// Real PostgreSQL in Docker for tests
const { PostgreSqlContainer } = require('testcontainers');

let container;

beforeAll(async () => {
  container = await new PostgreSqlContainer()
    .withDatabase('test')
    .start();

  process.env.DATABASE_URL = container.getConnectionUri();
});

afterAll(async () => {
  await container.stop();
});
```

### VCR/Recording Pattern

```ruby
# Record HTTP interactions once, replay in future runs
VCR.use_cassette('stripe_charge') do
  result = Stripe::Charge.create(amount: 1000, currency: 'usd')
  expect(result.id).to start_with('ch_')
end
```

**First run:** Makes real HTTP call, saves to cassette file
**Subsequent runs:** Replays from cassette, no network call

### Service Virtualization

```javascript
// WireMock for complex API simulation
wiremock.stubFor(
  get(urlEqualTo("/users/123"))
    .willReturn(aResponse()
      .withStatus(200)
      .withBody('{"id": "123", "name": "Test"}'))
);
```

## Factory Best Practices

### Minimal Defaults

```ruby
# BAD: Factory creates everything
factory :user do
  name { Faker::Name.name }
  email { Faker::Internet.email }
  admin { false }
  verified { true }
  created_at { Time.now }
  # ... 20 more attributes
end

# GOOD: Minimal defaults, traits for variations
factory :user do
  sequence(:email) { |n| "user#{n}@test.invalid" }

  trait :admin do
    admin { true }
  end

  trait :unverified do
    verified { false }
  end
end

# Usage shows intent
create(:user)                    # Basic user
create(:user, :admin)            # Admin user
create(:user, :admin, :unverified)  # Specific scenario
```

### Avoid Callbacks for Unrelated Setup

```ruby
# BAD: Factory does too much
factory :user do
  after(:create) do |user|
    create(:profile, user: user)
    create(:subscription, user: user)
    create_list(:posts, 3, author: user)
  end
end

# GOOD: Explicit associations via traits
factory :user do
  trait :with_profile do
    after(:create) { |user| create(:profile, user: user) }
  end

  trait :with_posts do
    transient { posts_count { 3 } }
    after(:create) do |user, evaluator|
      create_list(:post, evaluator.posts_count, author: user)
    end
  end
end

# Usage is explicit
create(:user, :with_profile, :with_posts, posts_count: 5)
```

### Sequence for Uniqueness

```ruby
# BAD: Hardcoded values cause collisions in parallel tests
factory :user do
  email { "test@example.com" }  # Collision!
end

# GOOD: Sequences ensure uniqueness
factory :user do
  sequence(:email) { |n| "user-#{n}@test.invalid" }
end
```

## Large Dataset Testing

### Strategies

1. **SQL-based bulk generation:**
   ```sql
   INSERT INTO orders (user_id, total, created_at)
   SELECT
     (random() * 10000)::int,
     (random() * 1000)::decimal(10,2),
     NOW() - (random() * interval '365 days')
   FROM generate_series(1, 1000000);
   ```

2. **Statistical sampling:**
   - 1-5% sample often sufficient
   - Ensure edge cases represented
   - Maintain distribution of key attributes

3. **Synthetic generation at scale:**
   - Use Faker with seed for reproducibility
   - Generate in batches to manage memory
   - Store generated data for reuse

### Performance Testing Volumes

| Scale | Records | Use Case |
|-------|---------|----------|
| Small | 10,000 | Functional validation |
| Medium | 100,000 | Integration testing |
| Large | 1,000,000 | Performance baseline |
| X-Large | 10,000,000 | Stress testing |

## Audit Checklist

### PII Compliance
- [ ] No real names that could match actual people?
- [ ] No real email domains (gmail, yahoo, etc.)?
- [ ] No valid SSN/national ID formats?
- [ ] No real phone numbers?
- [ ] Credit card numbers use designated test numbers?

### State Isolation
- [ ] Each test cleans up after itself?
- [ ] No global variables mutated by tests?
- [ ] Database state reset between tests?
- [ ] Singletons/caches cleared in beforeEach?

### Factory Quality
- [ ] Factories have minimal defaults?
- [ ] Variations use traits, not overrides?
- [ ] Sequences for unique values?
- [ ] No heavy callbacks in base factory?

### External Dependencies
- [ ] External APIs mocked or recorded?
- [ ] Database uses testcontainers or dedicated test instance?
- [ ] No hardcoded service URLs?
- [ ] Graceful handling when services unavailable?
