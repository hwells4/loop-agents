# Example prd.json

Good example of stories with verifiable acceptance criteria:

```json
{
  "branchName": "feature/user-authentication",
  "userStories": [
    {
      "id": "US-001",
      "title": "Create user model and database schema",
      "acceptanceCriteria": [
        "User model has email, password_hash, created_at fields",
        "Migration creates users table",
        "Test: can create user with valid data",
        "Test: rejects duplicate email",
        "npm test passes",
        "typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Add password hashing utility",
      "acceptanceCriteria": [
        "hashPassword() returns bcrypt hash",
        "verifyPassword() compares password to hash",
        "Test: hashed password is not plaintext",
        "Test: verifyPassword returns true for correct password",
        "Test: verifyPassword returns false for wrong password",
        "npm test passes",
        "typecheck passes"
      ],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Create registration endpoint",
      "acceptanceCriteria": [
        "POST /api/register accepts email and password",
        "Returns 201 with user object on success",
        "Returns 400 if email already exists",
        "Returns 400 if password too short",
        "Password is hashed before storing",
        "Test: successful registration returns 201",
        "Test: duplicate email returns 400",
        "Test: short password returns 400",
        "npm test passes",
        "typecheck passes"
      ],
      "priority": 3,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-004",
      "title": "Create login endpoint",
      "acceptanceCriteria": [
        "POST /api/login accepts email and password",
        "Returns 200 with JWT token on success",
        "Returns 401 if email not found",
        "Returns 401 if password wrong",
        "Test: valid credentials returns 200 with token",
        "Test: wrong password returns 401",
        "Test: unknown email returns 401",
        "npm test passes",
        "typecheck passes"
      ],
      "priority": 4,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## What Makes These Good

1. **Sequential dependencies** - Each story builds on the previous
2. **Explicit test cases** - "Test:" prefix makes them unambiguous
3. **Verification commands** - npm test, typecheck at the end of each
4. **One concern per story** - Model, utility, endpoint, endpoint
5. **Verifiable criteria** - Agent can objectively check each one
