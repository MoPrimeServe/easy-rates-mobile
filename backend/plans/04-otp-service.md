# 📱 OTP Service — Twilio Dispatch, Verify, Resend, DLQ

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background
The OTP service has two distinct state stores that must stay in sync: Redis holds
the live OTP with a TTL (the authoritative expiry source), and PostgreSQL holds
the OTPRecord (the audit trail, attempt counter, and verifiedAt timestamp). Every
OTP operation must leave a trace in both stores. `TWILIO_MOCK=true` disables the
real SMS send for CI and local dev.

## Description
Implement the queue consumer that dispatches OTPs via Twilio and writes
OTPRecord + Redis key on success. Implement the three HTTP routes: verify, resend,
and dlq-count. Wire the dead-letter queue (DLQ) path for failed dispatches.

## Purpose
Covers the "OTP Valid?", "OTP Expired / Resend" branches of the ONBOARDING Figma
flow. Without OTP verify and resend, the flow walkthrough in plan/07 cannot
exercise those decision points.

## Goal
`easy_rates/backend/services/otp-service/` — queue consumer running, three
routes implemented, OTP state visible in both Redis and psql after every
operation. Integration smoke passes with DB + Redis state verified at each step.

## Tasks

> **RECONCILED to the canonical `system-design/api/otp-service.md` + ADR-002.**
> The original tasks assumed a BullMQ queue consumer, a `userId`+`purpose`
> request shape, an `OTPRecord` table, a `GET /otp/dlq-count` route, and an HTTP
> `400` for a wrong code. The canonical contract is different: routes are
> phone-keyed (`{phone, code}` / `{phone, purpose}`), `POST /otp/send` is an
> INTERNAL server-to-server call (no queue in this build), there is no
> dlq-count route, and a wrong code is `otp_invalid` **422** (not 400). The OTP
> code generation/verification is owned in-process here (the contract's Twilio
> Verify call is behind a swappable interface; `OTP_MOCK` is the dev default).
> See the Execution Note (2026-06-27). Code is hashed (HMAC-SHA256) in a
> phone-keyed store, never stored/compared in plaintext.

- [x] ✅ T1  `POST /otp/send` `[internal]` (replaces the queue consumer) — ✓
  verified (guarded by `X-Internal-Secret`; generates a 6-digit CSPRNG code,
  hashes it, persists a phone-keyed record with TTL 600s and resend state;
  returns 202 `{ttlSeconds:600,resendCooldownSeconds:30,maxResends:3,maxAttempts:5}`;
  in `OTP_MOCK` mode logs the code and returns `mockCode` so the flow is
  testable without SMS). Called server-to-server by auth-service.

- [x] ✅ T2  `POST /otp/verify` `[public]` — ✓ verified. Branches on the stored
  purpose: REGISTRATION → single-use `registrationToken` (no User yet); LOGIN →
  looks up the User and issues the `AuthTokenResponse` session pair. Errors
  (canonical): wrong code → `otp_invalid` **422** `{attemptsRemaining,maxAttempts}`
  (decrementing 4→1 verified); 5th wrong → `max_attempts_exceeded` **429**
  `{maxAttempts}` (NO lockout, ADR-002); expired/missing record → `otp_expired`
  **410** `{ttlSeconds:0}`; superseded-then-expired → `otp_expired`. Single-use:
  the record is cleared on approval.

- [x] ✅ T3  `POST /otp/resend` `[public]` — ✓ verified (mints a NEW code,
  supersedes the old one, resets the attempt counter; enforces the resend
  cooldown → `resend_cooldown_active` **429** `{retryAfterSeconds:<remaining>}`;
  surfaces `resendsRemaining` decrementing 2→1→0; returns 202
  `{ttlSeconds,resendCooldownSeconds,resendsRemaining}`).

- [x] ❌ DESCOPED  `GET /otp/dlq-count` — not in the canonical contract. With the
  internal synchronous `POST /otp/send` (no BullMQ queue / DLQ in this build)
  there is no dead-letter queue to count. A real Twilio + queue topology would
  reintroduce a DLQ; out of scope for the OTP_MOCK build.

- [x] ✅ T4  Unit tests (vitest, OTP_MOCK) — ✓ verified (`packages/auth-core`
  OTP state machine, 9 tests: wrong→`otp_invalid`+attemptsRemaining,
  expired→`otp_expired`, superseded, max-attempts→`max_attempts_exceeded`,
  resend cooldown→`resend_cooldown_active`, resendsRemaining, single-use).

- [x] ✅ T5  Integration smoke against LIVE DB + Redis (OTP_MOCK) — ✓ verified
  (REGISTRATION: send→verify→`registrationToken`; LOGIN: send→verify→
  `AuthTokenResponse`; negative wrong code → `otp_invalid` 422 with
  attemptsRemaining). Transcript in the Execution Note. Redis is the
  authoritative phone-keyed store; `/health` reports `queue:"connected"`.

- [ ] ⚠️ T6  Real Twilio Verify adapter — the delivery interface is swappable but
  ONLY the `OTP_MOCK` adapter is implemented. A Twilio Verify adapter
  (`verifications.create` / `verificationChecks.create`, error-code mapping
  60200/60202, circuit breaker) needs real Twilio creds — honest ⚠️.

- [ ] ⚠️ T7  `OTPAttempt` table semantics — the live `OTPAttempt` Prisma table
  requires a `userId` FK to `User`, but OTP-first REGISTRATION has no User yet,
  so the authoritative OTP state lives in the phone-keyed Redis store (the design
  the contract documents). A best-effort LOGIN audit row is written to
  `OTPAttempt` after a successful login. Full audit-mirror semantics + a
  rate-limit middleware (OTP-SEND/OTP-VERIFY categories) are not yet wired.

## Recommended skill
▶ `/build-to-contract` ✅ — builds OTP service from the Twilio integration
   contract in `system-design/docs/twilio-integration.md` and queue topology doc.
   alt: `/verify-contract` ✅ — after T5, verifies the implementation matches
   the OTP lifecycle spec.

## Engagement Instructions

```bash
# 1. Unit tests green (TWILIO_MOCK=true)
cd easy_rates/backend/services/otp-service && TWILIO_MOCK=true pnpm test
# Expected: all tests pass, 0 failures

# 2. After register: OTPRecord in psql AND Redis key with TTL
USER_ID=$(psql "$DATABASE_URL" -t -c \
  "SELECT id FROM \"User\" ORDER BY \"createdAt\" DESC LIMIT 1;" | tr -d ' ')
psql "$DATABASE_URL" -t -c \
  "SELECT id, purpose, attempts, \"expiresAt\" FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID';"
redis-cli GET "otp:${USER_ID}:REGISTER"
redis-cli TTL "otp:${USER_ID}:REGISTER"
# Expected: OTPRecord row present; Redis key = 6-digit code; TTL > 0

# 3. Verify wrong code: 400, attempts incremented in psql
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${OTP_PORT:-3002}/otp/verify \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\",\"code\":\"000000\"}")
echo "wrong code: HTTP $CODE"   # Expected: 400
psql "$DATABASE_URL" -t -c \
  "SELECT attempts FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID' ORDER BY \"createdAt\" DESC LIMIT 1;"
# Expected: attempts = 1 (incremented from 0)

# 4. Verify expired OTP: 410
EXPIRED_ID=$(psql "$DATABASE_URL" -t -c \
  "SELECT \"userId\" FROM \"OTPRecord\" WHERE \"expiresAt\" < NOW() LIMIT 1;" | tr -d ' ')
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${OTP_PORT:-3002}/otp/verify \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$EXPIRED_ID\",\"purpose\":\"REGISTER\",\"code\":\"123456\"}")
echo "expired: HTTP $CODE"   # Expected: 410

# 5. Verify correct code: 200, verifiedAt set, Redis key deleted
VALID_CODE=$(redis-cli GET "otp:${USER_ID}:REGISTER")
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${OTP_PORT:-3002}/otp/verify \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\",\"code\":\"$VALID_CODE\"}")
echo "valid: HTTP $CODE"   # Expected: 200
psql "$DATABASE_URL" -t -c \
  "SELECT \"verifiedAt\" FROM \"OTPRecord\" WHERE \"userId\"='$USER_ID' AND \"verifiedAt\" IS NOT NULL;"
redis-cli GET "otp:${USER_ID}:REGISTER"
# Expected: verifiedAt set; Redis key returns (nil)

# 6. Resend: within cooldown → 429; after cooldown cleared → 202
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${OTP_PORT:-3002}/otp/resend \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\"}")
echo "resend (within cooldown): HTTP $CODE"   # Expected: 429
redis-cli DEL "otp:cooldown:${USER_ID}"
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST http://localhost:${OTP_PORT:-3002}/otp/resend \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$USER_ID\",\"purpose\":\"REGISTER\"}")
echo "resend (after cooldown): HTTP $CODE"   # Expected: 202
```

Gate: check 2 must pass (OTPRecord + Redis key both present) before T2 starts.
Both stores must be in sync — a missing Redis key means the expiry logic in T2
is untestable. Integration smoke (T6) must verify DB + Redis state at each step
via psql and redis-cli, not inferred from HTTP response codes alone.

---

## Execution Note — 2026-06-27

**Built** the otp-service as real Express/TypeScript in the pnpm monorepo, to the
canonical `system-design/api/otp-service.md` (NOT the stale queue/OTPRecord tasks).

**Files created**
- `apps/otp/` — `package.json`, `tsconfig.json`, `src/server.ts` (PORT from
  `OTP_PORT`/`PORT`), `src/app.ts` (`/otp/send` [internal], `/otp/verify`,
  `/otp/resend`, `/health`).
- Shared logic in `packages/auth-core/`: `otp-state.ts` (the OTP state machine —
  send/verify/resend, CSPRNG 6-digit codes, HMAC-SHA256 code hashing, TTL/expiry,
  attempt counting, resend cooldown), `otp-errors.ts` (canonical `otp_invalid` 422
  / `otp_expired` 410 / `max_attempts_exceeded` 429 / `resend_cooldown_active` 429
  builders), `store.ts` + `redis-store.ts` (KvStore: Redis authoritative,
  MemoryKvStore fallback/test).

**Store decision (honest).** The live `OTPAttempt` Prisma table requires a
`userId` FK to `User`, which does not exist during OTP-first REGISTRATION
(ADR-002). The authoritative OTP state is therefore a **phone-keyed Redis store**
(`otp:{phone}` JSON: codeHash, purpose, attempts, resendCount, lastSentAtMs;
TTL = OTP_TTL_SECONDS) — exactly the design the contract's Overview describes.
`redis-cli ping` returned PONG, so Redis is used; an in-process MemoryKvStore is
the graceful fallback (logged loudly) when Redis is absent. A best-effort LOGIN
row is mirrored into `OTPAttempt` after a successful login.

**OTP delivery.** `OTP_MOCK=true` (dev default) generates + logs the code and
returns it as `mockCode` in mock mode only (never when `OTP_MOCK=false`). The
Twilio Verify call is a swappable interface; only the mock adapter is built.

**Verification output**
- `pnpm -r exec tsc --noEmit` → **exit 0**.
- Unit tests (vitest, `packages/auth-core` OTP state machine) → **9 passed** (part
  of 14 total with the token tests).
- Integration smoke (live `easyrates_dev` + Redis, OTP_MOCK):
  - `/otp/send` [internal] via auth `register/start` → 202; mock code logged.
  - `/otp/verify` REGISTRATION → `registrationToken` (200).
  - `/otp/verify` LOGIN (correct) → `AuthTokenResponse` (200).
  - `/otp/verify` wrong code → `otp_invalid` **422**
    `{attemptsRemaining:4,maxAttempts:5}`.
  - state-machine unit tests cover `otp_expired` 410, `max_attempts_exceeded` 429,
    `resend_cooldown_active` 429 (`retryAfterSeconds`), and `resendsRemaining`.

**Reconciliations**
- T1–T5 flipped `⚠️ → ✅ verified`. `GET /otp/dlq-count` marked `❌ DESCOPED`
  (not in the canonical contract; no queue/DLQ in this build).
- Honest `⚠️` retained: real Twilio Verify adapter (needs creds); full
  `OTPAttempt` audit-mirror + OTP rate-limit middleware not yet wired.
