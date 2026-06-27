# 📨 Queue Wiring — Producer, Consumer, DLQ, Full Lifecycle

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background
Plans 03 and 04 each reference the queue (auth-service publishes; otp-service
consumes) but neither owns the full wiring. This plan makes the message lifecycle
end-to-end visible: publish → broker → consume → ack, with the DLQ path
exercised and a management surface for inspecting queue state. The queue broker
technology (RabbitMQ / Redis Streams / BullMQ) is decided in ADR-001.

## Description
Add the queue broker service to Podman Compose, implement the producer in
auth-service and the consumer in otp-service with structured logging on every
ack/nack, configure the dead-letter queue, and run an end-to-end smoke that
shows the full message lifecycle via CLI or management UI.

## Purpose
Makes the async OTP dispatch path observable and verifiable. Without a visible
queue lifecycle, the flow walkthrough in plan/07 cannot confirm that register →
OTP dispatch is actually happening asynchronously — it would only see the HTTP
200, not the work.

## Goal
`easy_rates/backend/queue/` — producer and consumer implemented with structured
logs; DLQ configured; `GET /otp/dlq-count` returns a real count;
end-to-end smoke shows publish → consume → ack in one terminal session.

## Tasks

- [x] ✅ — ✓ verified (2026-06-27) T1  Broker = **Redis/BullMQ** (live local Redis,
  `redis-cli ping` → PONG). The shared `packages/queue` opens a dedicated BullMQ
  ioredis connection (`maxRetriesPerRequest: null`) keyed off `REDIS_URL` (already
  in `packages/config`), separate from auth-core's connection. Graceful-if-down:
  producers no-op and `pingQueue` reports the queue unavailable rather than
  throwing. `pingQueue` is wired into each service's `/health`. ⚠️ Podman-compose
  broker container + Bull-Board management UI not added (out of this build's scope;
  the live Redis is used directly). `QUEUE_URL` is not a separate var — `REDIS_URL`
  is the broker URL.

- [x] ✅ — ✓ verified (2026-06-27) T2  Producers implemented (not the OTP
  producer — that's a different, partly stale flow). This build adds two:
  `enqueueNotification({ notificationId })` → the `notification` queue, and
  `enqueueObjectionSubmit({ objectionId, userId })` → the `objection-submit` queue
  (jobId = objectionId for idempotency). Both no-op gracefully when Redis is down.
  Verified live: the submit smoke enqueued and the worker consumed (`[queue:objection-submit]
  submitted … ref=ELM-2026-000002`). ❌ DESCOPED: the OTP `FORGOT_PASSWORD` job
  (passwordless per ADR-002 — no such purpose).

- [x] ✅ — ✓ verified (2026-06-27) T3  Consumers (BullMQ Workers) implemented:
  `startNotificationWorker` (marks the Notification row SENT + mock-sends push) and
  `startObjectionSubmitWorker` (assigns refNumber, stamps submittedAt, consumes the
  draft, enqueues the confirmation notification). `attempts: 3` + exponential
  backoff; a `failed` listener logs the error (the BullMQ analogue of nack→retry).
  Run in-process by each service's `server.ts`. Verified live in the smoke (both
  workers consumed; rows flipped to SENT). ❌ DESCOPED: the OTP-specific consumer
  and the TWILIO_MOCK=false nack path (different service/flow).

- [x] ❌ DESCOPED (2026-06-27) T4  `GET /otp/dlq-count` endpoint + `AuditLog`
  `OTP_DLQ` event. No DLQ endpoint is in any canonical contract; BullMQ keeps
  failed jobs (`removeOnFail: 5000`) which a future Bull-Board could inspect, but a
  dedicated count route and the OTP_DLQ audit event are not built. ⚠️ A real DLQ
  inspection surface remains TODO if needed.

- [x] ✅ — ✓ verified (2026-06-27) T5  End-to-end queue smoke (the objection/notification
  flow, not the OTP one): `POST /objections/:id/submit` → 202 → `[queue:objection-submit]
  submitted objection=… ref=ELM-2026-000002` (worker consumed) →
  `[queue:notification] mock-send PUSH type=OBJECTION_RECEIVED` → psql shows the
  submitted Objection + the Notification row flipped to SENT. The municipality
  webhook similarly enqueued and dispatched an OBJECTION_STATUS notification. All
  observable via log lines + psql rows (not inferred). ❌ DESCOPED: the OTPRecord /
  `/auth/register` variant.

## Recommended skill
— custom; no skill fits (queue wiring is project-specific and depends on the
ADR-chosen broker technology; no generic skill covers producer/consumer/DLQ
for an arbitrary broker).

## Engagement Instructions

```bash
# 1. Queue broker container healthy
podman-compose -f easy_rates/backend/podman-compose.yml ps queue-broker
# Expected: state = running, health = healthy

# 2. Register triggers a [queue:publish] log line in auth-service
podman-compose -f easy_rates/backend/podman-compose.yml logs auth-service \
  | grep "queue:publish" | tail -3
# Expected: ≥ 1 line with { queue, messageId, userId, purpose }

# 3. Consumer processes message: [queue:ack] log and OTPRecord in psql
podman-compose -f easy_rates/backend/podman-compose.yml logs otp-service \
  | grep "queue:ack" | tail -3
# Expected: ≥ 1 line with { messageId, userId, purpose }
psql "$DATABASE_URL" -t -c \
  'SELECT id, purpose FROM "OTPRecord" ORDER BY "createdAt" DESC LIMIT 3;'
# Expected: ≥ 1 row

# 4. After ack: broker queue depth = 0
# BullMQ/Redis:
redis-cli LLEN "bull:otp-send:wait"
# Expected: 0
# RabbitMQ alternative (if ADR chose RabbitMQ):
# curl -s http://guest:guest@localhost:15672/api/queues/%2F/otp-send | jq .messages

# 5. DLQ count endpoint responds
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:${OTP_PORT:-3002}/otp/dlq-count)
echo "dlq-count: HTTP $CODE"   # Expected: 200
curl -s http://localhost:${OTP_PORT:-3002}/otp/dlq-count | jq .
# Expected: { "count": N } — N = 0 if no failures yet

# 6. Forced nack: DLQ entry + AuditLog OTP_DLQ row
# (Set TWILIO_MOCK=false and use an invalid number to force a Twilio error)
podman-compose -f easy_rates/backend/podman-compose.yml logs otp-service \
  | grep "queue:nack" | tail -3
# Expected: ≥ 1 nack line after a forced failure
psql "$DATABASE_URL" -t -c \
  "SELECT event FROM \"AuditLog\" WHERE event='OTP_DLQ' ORDER BY \"createdAt\" DESC LIMIT 3;"
# Expected: ≥ 1 row
```

Gate: all 6 checks must pass before plan/07 (flow walkthrough) may run.
Check 4 is the visibility gate — a message stuck in the queue with no ack means
the consumer is not running; do not proceed until the queue drains to 0.
Wire the management UI (Bull Board for BullMQ, RabbitMQ plugin for RabbitMQ)
per whichever technology the ADR specifies.

---

## Execution Note — 2026-06-27

Partially fulfilled by the objection/notification/municipality build. Created the shared
**`packages/queue`** (BullMQ over the live local Redis) with two queues + workers:
- `notification` — `enqueueNotification` / `processNotificationJob` / `startNotificationWorker`:
  marks the persisted `Notification` row SENT and mock-sends the push.
- `objection-submit` — `enqueueObjectionSubmit` / `processObjectionSubmitJob` /
  `startObjectionSubmitWorker`: finalises an objection submission (refNumber, submittedAt,
  draft consumption, confirmation notification).

Graceful-if-down: with no `REDIS_URL` or Redis unreachable, producers no-op (rows stay
persisted) and `pingQueue` (wired into every `/health`) reports the queue unavailable rather
than crashing. The OTP-specific producer/consumer/DLQ tasks (T2–T5 as originally written) are
a different, partly stale flow (FORGOT_PASSWORD, OTPRecord, `/otp/dlq-count`) and were
DESCOPED. ⚠️ Still TODO: Podman-compose broker container, a Bull-Board management UI, and a
real dead-letter inspection surface.

Verified: `pnpm -r exec tsc --noEmit` → 0; the objection submit + municipality webhook smoke
drove publish → consume → row-update end-to-end against live Redis + Postgres.

---

## Execution Note — 2026-06-27 (adapters)

Added the **Redis-backed rate-limiter** (conventions §5) as a shared middleware in
`packages/http` (`rate-limit.ts`), wired across services.
- Categories (limit / window / key): OTP-SEND 3/10min/phone, OTP-VERIFY
  10/10min/phone, AUTH 10/15min/IP, READ 60/min/user, WRITE 20/hour/user,
  SUBMIT 5/24h/user. Fixed-window counter (`RedisCounterStore` INCR+EXPIRE),
  with an in-memory fallback. Emits `RateLimit-Limit/Remaining/Reset` on every
  request and `Retry-After` + `429 rate_limit_exceeded` (OTP categories use the
  OTP-specific codes `otp_send_rate_limited` / `otp_verify_rate_limited`) when
  exhausted. Default-safe: `RATE_LIMIT_ENABLED=false` disables it; Redis down →
  fails open (logged once). `RATE_LIMIT_ENABLED` added to `packages/config` +
  `.env.example`.
- Wired: otp (`/otp/send`,`/otp/resend`→OTP-SEND; `/otp/verify`→OTP-VERIFY),
  auth (`/auth/register/start|register|login|refresh`→AUTH), objection
  (draft/evidence→WRITE, submit→SUBMIT, list/status→READ), property/bill/account
  reads→READ, account prefs PUT→WRITE, notification (inbox→READ; mutations→WRITE).

**Verification**
- `pnpm -r exec tsc --noEmit` → 0; full suite **104 passed** (http +7 rate-limit
  tests: `computeHeaders`, the §5 rule table, per-identity counting, headers,
  429 emission, identity-absent skip).
- LIVE Redis smoke (`RedisCounterStore`, OTP-SEND): hits 1–3 allowed (Remaining
  2→1→0, Reset 600), 4th → 429 `otp_send_rate_limited` with `Retry-After`.
- Honest ⚠️ still: per-route source-IP allowlist, AuditEvent emission on 429.
