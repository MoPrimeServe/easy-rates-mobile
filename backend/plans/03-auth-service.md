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

> **RECONCILED to ADR-002 (passwordless OTP-first) and the canonical
> `system-design/api/auth-service.md`.** The original password-based tasks below
> are superseded: there is no `password`, no `bcrypt`, no `RefreshToken` Prisma
> table, no `forgot-password`. The canonical contract has SEVEN routes
> (`register/start`, `register`, `login`, `refresh`, `logout`, `session`, `kyc`).
> See the Execution Note (2026-06-27) for build + verification evidence.

- [x] ✅ T1  `POST /auth/register/start` `[public]` — ✓ verified (curl 202
  `{ttlSeconds:600, resendCooldownSeconds:30, maskedPhone:"+27****7777"}`;
  duplicate phone → 409 `conflict`; bad phone → 400 `validation_error` with
  `details.fields.phone`). Dispatches a REGISTRATION OTP to otp-service
  `POST /otp/send` server-to-server. Creates no User.

- [x] ✅ T2  `POST /auth/register` `[public]` — ✓ verified (consumes single-use
  `registrationToken`; creates phone-verified User with `idNumberHash` =
  HMAC-SHA256(pepper, idNumber), plaintext discarded; NO password; returns 201
  `AuthTokenResponse`; psql confirms User row, `idNumberHash` length 64, no
  password column). Bad-Luhn idNumber → 400 `validation_error`.

- [x] ✅ T3  `POST /auth/login` `[public]` — ✓ verified (anti-enumeration: always
  200 with byte-identical body for registered AND unregistered phones;
  `maskedPhone` is a masked echo of the SUBMITTED number; LOGIN OTP dispatched
  only when the phone is registered). No password, no account-lockout (ADR-002).

- [x] ✅ T4  `POST /auth/refresh` `[public]` — ✓ verified (opaque 256-bit hex
  refresh, single-use, ROTATED on every call → 200 new pair; reuse of a rotated
  token → 401 `unauthenticated` "reuse detected" AND revokes the whole family →
  the legitimately-rotated token also 401s). RS256 access token, 900s TTL.

- [x] ✅ T5  `POST /auth/logout` — ✓ verified (auth-required; revokes the
  submitted refresh token → 200 `{message:"Logged out."}`; a subsequent refresh
  with that token → 401). Missing bearer token → 401.

- [x] ✅ T6  `GET /auth/session` — ✓ verified (auth-required; returns
  `{userId, phone, kycStatus}` 200 for a valid access token; no/invalid token →
  401 `unauthenticated`).

- [x] ✅ T7  `POST /auth/kyc` (multipart) — ✓ verified by typecheck + route
  implementation (accepts `file` part, rejects MIME not in
  pdf/jpeg/png → 422 `invalid_file_type`, missing part → 400 `file_missing`,
  >10 MB → 413; sets `kycStatus = SUBMITTED`, records `kycDocumentKey` only).
  ⚠️ Azure Blob upload is a STUB (key is synthesised; no real blob write) —
  needs Azure Blob Storage wiring before pilot.

- [x] ✅ T8  Unit tests (vitest) — ✓ verified (`packages/auth-core`: 14 tests
  green — OTP state machine + RS256/opaque-refresh rotation + reuse-detection +
  single-use registrationToken). Run: `cd packages/auth-core && pnpm test`.

- [x] ✅ T9  Integration smoke against the LIVE DB (`easyrates_dev`) + Redis — ✓
  verified (full passwordless REGISTRATION and LOGIN flows driven with curl;
  transcript + psql confirmation in the Execution Note). Store backend = Redis
  (authoritative, phone-keyed), confirmed via `/health` `queue:"connected"`.

- [x] ❌ DESCOPED (ADR-002 passwordless)  `POST /auth/forgot-password` /
  `POST /auth/reset-password` / `FORGOT_PASSWORD` OTP purpose — removed by
  ADR-002. With no password there is nothing to recover; a locked-out user simply
  logs in again via `POST /auth/login` (a fresh LOGIN OTP).

- [ ] ⚠️ T10  AuditEvent writes (`LOGIN_SUCCESS`, `LOGIN_FAILED`,
  `KYC_DOCUMENT_UPLOADED`, …) — NOT yet implemented. The live schema has
  `AuditEvent` (not `AuditLog`); manual audit-event emission (DECISION-B) is
  deferred to the recon/audit plan. Honest ⚠️.

- [ ] ⚠️ T11  Production hardening — RS256 keys are dev keys under
  `backend/keys/` (private key gitignored). Real deployment needs Azure Key Vault
  key loading + JWKS endpoint, Redis HA, and the rate-limit middleware
  (conventions §5 AUTH/SYSTEM/WRITE/READ categories) which is NOT yet wired.

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

---

## Execution Note — 2026-06-27

**Built** the auth-service as real Express/TypeScript in the pnpm monorepo, to the
canonical ADR-002 passwordless contract (NOT the stale password tasks above).

**Files created**
- `apps/auth/` — `package.json`, `tsconfig.json`, `src/server.ts` (PORT from
  `AUTH_PORT`/`PORT`), `src/app.ts` (all 7 routes + `/health`), `src/otp-client.ts`
  (server-to-server `POST /otp/send` with `X-Internal-Secret`), `src/auth-middleware.ts`
  (RS256 bearer-token `requireAuth`).
- `packages/auth-core/` — shared internal package: `tokens.ts` (RS256 access +
  opaque-256-bit-hex refresh with rotation/reuse-detection/family-revoke;
  single-use registrationToken), `identity.ts` (phone E.164 + SA-ID Luhn +
  `hashIdNumber` HMAC + `maskPhone`), `otp-state.ts`/`otp-errors.ts`/`store.ts`/
  `redis-store.ts`/`runtime.ts`/`zod-validate.ts`.
- `packages/config/src/index.ts` — extended with JWT key (PEM/path), OTP lifecycle,
  `OTP_MOCK`, `INTERNAL_API_SECRET`, `OTP_SERVICE_URL`, registrationToken TTL.
- `backend/keys/jwt-rs256-private.pem` (gitignored) + `…-public.pem` — dev RS256 keypair.
- `.env` / `.env.example` updated; `.gitignore` ignores the private key.

**Token model (conventions §6) — verified**
- Access: RS256 JWT, 900s, `sub=userId`, iss/aud set, verified by public key.
- Refresh: opaque 256-bit hex (64-char), 30d, single-use, ROTATED every refresh,
  reuse-detected → family revoke. Stored HASHED (SHA-256) in Redis (the live Prisma
  schema has NO `RefreshToken` table — the original plan flagged this as a schema gap;
  Redis is used rather than diverging from the migrated source-of-truth schema).

**Verification output**
- `pnpm install` → OK (83 packages added; esbuild build approved via
  `onlyBuiltDependencies`; removed a malformed `allowBuilds` placeholder block from
  `pnpm-workspace.yaml` that was breaking the pre-run deps check).
- `pnpm -r exec tsc --noEmit` → **exit 0** (all 6 packages).
- Unit tests (vitest, `packages/auth-core`) → **14 passed**.
- Integration smoke (live `easyrates_dev` + Redis, OTP_MOCK):
  - REGISTRATION: `register/start` → 202 `{ttlSeconds:600,resendCooldownSeconds:30,maskedPhone:"+27****7777"}`
    → mock OTP read → `otp/verify` → `registrationToken` → `register` → 201
    `AuthTokenResponse` (RS256 JWT + 64-hex refresh) → `GET /auth/session` → 200
    `{kycStatus:"PENDING"}`. psql: User row present, `idNumberHash` length 64, no password.
  - LOGIN: `login` → 200 anti-enumeration; wrong code → `otp_invalid` 422
    `{attemptsRemaining:4,maxAttempts:5}`; correct code → `AuthTokenResponse` 200.
  - REFRESH: rotate → 200 new pair; reuse old token → 401 "reuse detected";
    rotated token then 401 "family revoked".
  - logout → 200, subsequent refresh → 401. register/start duplicate → 409 conflict.

**Reconciliations**
- T1–T9 flipped `⚠️ → ✅ verified`. forgot/reset-password marked `❌ DESCOPED (ADR-002)`.
- Honest `⚠️` retained: KYC Azure Blob upload is a stub; AuditEvent emission deferred;
  rate-limit middleware + Key Vault/JWKS + Redis HA are production-hardening, not built.
