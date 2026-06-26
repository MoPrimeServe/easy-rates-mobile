# 🔐 Auth Service — Register, Login, Refresh, Forgot Password

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## JWT Configuration Constants

Source of truth: `system-design/docs/security/sessions.md`. Do not change these values
here — update the source document first.

```text
JWT_ALGORITHM              = RS256
JWT_SIGNING_KEY_ID         = <current Azure Key Vault key name>
JWKS_ENDPOINT              = /auth/.well-known/jwks.json
JWKS_CACHE_TTL_MS          = 300_000        // 5 minutes

ACCESS_TOKEN_TTL_SECONDS   = 900            // 15 minutes
ACCESS_TOKEN_STORAGE       = in-memory only (Flutter Riverpod state — never written to disk)

REFRESH_TOKEN_TTL_DAYS     = 30
REFRESH_TOKEN_STORAGE      = flutter_secure_storage (iOS Keychain / Android Keystore)
REFRESH_TOKEN_FORMAT       = opaque 256-bit random hex (not JWT)
REFRESH_TOKEN_ROTATION     = on every use (single-use; rotate atomically)
REFRESH_TOKEN_HASH         = SHA-256, stored in RefreshToken.tokenHash

REVOCATION_STRATEGY        = no Redis blacklist; deletedAt check in JWT middleware;
                             reuse attack detection via familyId chain revocation
MAX_REVOCATION_LAG         = 15 minutes (access token TTL) for theft scenarios;
                             0 seconds for logout and POPIA erasure
```

**Schema gap:** The `RefreshToken` Prisma model is not yet in `schema.prisma`. Add it
before implementing T2. Schema block is in `system-design/docs/security/sessions.md`
under "RefreshToken table".

## Description

Implement the four auth routes that drive the ONBOARDING flow: register, login,
refresh token, and forgot-password. All data access goes through the Prisma
client from `shared/db.ts`. Every auth event is written to AuditLog. OTP
dispatch is queued, not called synchronously.

## Purpose

Covers the ONBOARDING Figma flow from "New User Sign Up" through "Verify Phone
OTP" entry point, and the "Returning User → Log In" and "Forgot Password →
Reset via OTP" branches. Without this plan, the flow walkthrough in plan/07
cannot run.

## Goal

`easy_rates/backend/services/auth-service/` — all four routes implemented,
unit-tested, and integration-smoked. AuditLog rows visible in psql after each
operation.

## Tasks

- [ ] ⚠️ T1  `POST /auth/register`
  - Accept `{ phone, password }` (validate with Zod)
  - Check for duplicate phone via Prisma — return 409 if exists
  - Hash password with bcrypt (saltRounds from env or default 12)
  - Create `User` record via Prisma
  - Emit OTP send job to queue with `{ userId, purpose: "REGISTER" }`
  - Write `AuditLog` entry: event `REGISTER_ATTEMPT`, userId, metadata `{ phone }`
  - Return 201 `{ userId }`
  Done when: curl POST registers a new user; psql confirms User row.

- [ ] ⚠️ T2  `POST /auth/login`
  - Accept `{ phone, password }`
  - Find User by phone via Prisma — return 401 if not found
  - Compare password with `bcrypt.compare` — return 401 if wrong
  - Issue JWT access token (short-lived, from ADR) + refresh token (long-lived)
  - Create `RefreshToken` record via Prisma
  - Write `AuditLog`: event `LOGIN_SUCCESS` or `LOGIN_FAILURE`, userId, metadata
  - Return 200 `{ accessToken, refreshToken }`
  Done when: login with seed returning-user returns 200 with tokens; wrong
  password returns 401; psql shows RefreshToken row.

- [ ] ⚠️ T3  `POST /auth/refresh`
  - Accept `{ refreshToken }` in body or Authorization header (from ADR)
  - Look up RefreshToken record via Prisma — return 401 if not found or revoked
  - Check `expiresAt` — return 401 if expired
  - Issue new access token
  - Write `AuditLog`: event `REFRESH`, userId
  - Return 200 `{ accessToken }`
  Done when: valid refresh token returns new access token; revoked or expired
  token returns 401.

- [ ] ⚠️ T4  `POST /auth/forgot-password`
  - Accept `{ phone }`
  - Find User by phone via Prisma — return 202 even if not found (no enumeration)
  - If found: emit OTP send job with `{ userId, purpose: "FORGOT_PASSWORD" }`
  - Write `AuditLog`: event `FORGOT_PASSWORD`, userId or null
  - Return 202 (always, regardless of whether phone was found)
  Done when: known phone emits queue job and logs AuditLog; unknown phone
  returns 202 with no queue job and no User-specific log entry.

- [ ] ⚠️ T5  Confirm AuditLog is written for all four routes by running each
  endpoint once and querying:
  `SELECT event, "userId", "createdAt" FROM "AuditLog" ORDER BY "createdAt" DESC LIMIT 10;`
  Done when: REGISTER_ATTEMPT, LOGIN_SUCCESS, REFRESH, FORGOT_PASSWORD all
  appear as distinct rows.

- [ ] ⚠️ T6  Unit tests (vitest or jest — from ADR):
  - register: happy path, duplicate phone → 409, missing field → 400
  - login: valid, wrong password → 401, unknown phone → 401
  - refresh: valid token, expired token → 401, revoked token → 401
  - forgot-password: known phone → 202 + job, unknown phone → 202 + no job
  Done when: all unit tests pass with `pnpm test` in the auth-service directory.

- [ ] ⚠️ T7  Integration smoke (stack running):
  1. `POST /auth/register` → 201 → `psql: SELECT id FROM "User" WHERE phone=...`
  2. Confirm OTP job in queue (CLI or management UI)
  3. `POST /auth/login` → 200 → `psql: SELECT id FROM "RefreshToken" WHERE ...`
  4. `POST /auth/refresh` → 200 with new access token
  Done when: all four steps complete and DB state confirmed at each step.

## Recommended skill
▶ `/build-to-contract` ✅ — builds the service implementation from the API
   contract defined in `system-design/api/auth.md`.
   alt: `/verify-contract` ✅ — after T6, verifies the implementation matches
   the contract.

## Engagement Instructions

```bash
# 1. Unit tests green
cd easy_rates/backend/services/auth-service && pnpm test
# Expected: all tests pass, 0 failures

# 2. AuditLog written for all 4 auth operations
psql "$DATABASE_URL" -t -c \
  'SELECT event FROM "AuditLog" ORDER BY "createdAt" DESC LIMIT 10;'
# Expected: REGISTER_ATTEMPT, LOGIN_SUCCESS, REFRESH, FORGOT_PASSWORD all present

# 3. Register: new user created in DB
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${AUTH_PORT:-3001}/auth/register \
  -H "Content-Type: application/json" \
  -d '{"phone":"+27820000099","password":"Test1234!"}')
echo "register: HTTP $CODE"   # Expected: 201
psql "$DATABASE_URL" -t -c "SELECT phone FROM \"User\" WHERE phone='+27820000099';"
# Expected: 1 row

# 4. Duplicate register returns 409
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${AUTH_PORT:-3001}/auth/register \
  -H "Content-Type: application/json" \
  -d '{"phone":"+27820000099","password":"Test1234!"}')
echo "duplicate register: HTTP $CODE"   # Expected: 409

# 5. Login with seed returning user: tokens issued, RefreshToken row created
TOKENS=$(curl -s -X POST http://localhost:${AUTH_PORT:-3001}/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"+27821000002","password":"ReturnPass1!"}')
echo "$TOKENS" | jq -r '.accessToken' | grep -q "^ey" && echo "accessToken: OK"
psql "$DATABASE_URL" -t -c 'SELECT COUNT(*) FROM "RefreshToken";'
# Expected: ≥ 1 row

# 6. Refresh: new access token issued
REFRESH=$(echo "$TOKENS" | jq -r '.refreshToken')
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${AUTH_PORT:-3001}/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refreshToken\":\"$REFRESH\"}")
echo "refresh: HTTP $CODE"   # Expected: 200

# 7. Forgot-password always returns 202 — no phone enumeration
for phone in "+27821000002" "+27899999999"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST http://localhost:${AUTH_PORT:-3001}/auth/forgot-password \
    -H "Content-Type: application/json" \
    -d "{\"phone\":\"$phone\"}")
  printf "forgot-password (%s): HTTP %s\n" "$phone" "$CODE"
done
# Expected: both 202
```

Gate: checks 1 and 2 must pass before plan/04 starts — OTP consumer depends on
auth publishing to the queue. Check 2 is non-negotiable: AuditLog absent means
the audit trail is broken from day one. Integration smoke (T7) must run against
the live Podman stack, not mocks, with DB state confirmed via psql at each step.
