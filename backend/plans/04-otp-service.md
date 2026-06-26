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

- [ ] ⚠️ T1  Queue consumer: subscribe to OTP send queue (topic/queue from ADR).
  On message received `{ userId, purpose }`:
  - If `TWILIO_MOCK=true`: skip real SMS send; log `[mock] OTP 123456 sent`
  - If `TWILIO_MOCK=false`: call Twilio API (Verify or Programmable Messaging
    per ADR) wrapped in a circuit breaker (e.g. `opossum` npm package): open
    after `TWILIO_CB_THRESHOLD` consecutive 5xx or network errors; half-open
    probe every `TWILIO_CB_RESET_SECONDS`. Do not retry on 4xx (client errors).
    Handle Twilio errors: invalid number → DLQ; circuit open → DLQ immediately.
  - Generate 6-digit code (CSPRNG)
  - Create `OTPRecord` via Prisma: code (hashed or plain per ADR), purpose,
    maxAttempts (from env), expiresAt (now + TTL from ADR)
  - Set Redis key `otp:{userId}:{purpose}` = code with TTL matching expiresAt
  - Ack job on success; nack → DLQ on failure
  Done when: after a register call triggers a queue job, psql shows OTPRecord
  AND `redis-cli GET otp:{userId}:REGISTER` returns the code.

- [ ] ⚠️ T2  `POST /otp/verify`
  - Accept `{ userId, purpose, code }`
  - Look up Redis key `otp:{userId}:{purpose}` — if missing: return 410 (expired)
  - Compare code; if wrong: increment `OTPRecord.attempts` atomically using
    a single `updateMany WHERE id=$1 AND attempts < maxAttempts` and checking
    the updated row count (plain read-modify-write is a TOCTOU race — two
    simultaneous wrong-code requests for the same userId can both pass the
    max-attempts gate before either write commits)
    - If 0 rows updated (already at max): return 429 (max attempts exceeded)
    - Else: return 400 with `{ attemptsRemaining: maxAttempts - newAttempts }`
  - If correct: set `OTPRecord.verifiedAt = now()` via Prisma; delete Redis key;
    return 200 `{ verified: true }`
  Done when: curl verify with wrong code → 400 + attempts incremented in psql;
  expired key → 410; correct code → 200 + verifiedAt set in psql.

- [ ] ⚠️ T3  `POST /otp/resend`
  - Accept `{ userId, purpose }`
  - Check Redis key `otp:cooldown:{userId}` — if exists: return 429
    `{ reason: "cooldown", retryAfter: <seconds> }`
  - Count OTPRecords for userId + purpose in last 24h via Prisma — if ≥ max
    resends (from env): return 429 `{ reason: "max_resends" }`
  - Emit new OTP send job to queue
  - Set Redis key `otp:cooldown:{userId}` with cooldown TTL (from env)
  - Return 202
  Done when: resend within cooldown → 429 cooldown; resend after cooldown →
  202 + new queue job; max resends exceeded → 429 max_resends.

- [ ] ⚠️ T4  `GET /otp/dlq-count`
  - Query dead-letter queue for pending message count (method per ADR choice)
  - Return 200 `{ count: N }`
  Done when: curl returns a valid JSON response; count increases when a Twilio
  error is forced (use an invalid number with TWILIO_MOCK=false in test).

- [ ] ⚠️ T5  Unit tests with `TWILIO_MOCK=true`:
  - verify: valid code, invalid code (attempts incremented), expired (410),
    max attempts (429)
  - resend: within cooldown (429), after cooldown (202), max resends (429)
  Done when: `pnpm test` passes in the otp-service directory.

- [ ] ⚠️ T6  Integration smoke (stack running, TWILIO_MOCK=true):
  1. POST /auth/register → queue job emitted
  2. Consumer processes job → `psql: SELECT * FROM "OTPRecord"` shows row →
     `redis-cli GET otp:{userId}:REGISTER` shows code with TTL
  3. POST /otp/verify (wrong code) → 400 →
     `psql: SELECT attempts FROM "OTPRecord"` → attempts incremented
  4. POST /otp/verify (correct code) → 200 →
     `psql: SELECT "verifiedAt" FROM "OTPRecord"` → verifiedAt set →
     `redis-cli GET otp:{userId}:REGISTER` → (nil)
  5. POST /otp/resend → 202 → new OTPRecord in psql
  Done when: all five steps complete with DB + Redis state confirmed at each.

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
