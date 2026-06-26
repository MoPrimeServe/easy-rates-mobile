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

- [ ] ⚠️ T1  Add queue broker service to `podman-compose.yml` (image from ADR-001).
  Include:
  - Named volume for persistence
  - Health check (broker-specific ping)
  - Management UI port exposed (e.g. RabbitMQ :15672, BullMQ dashboard if
    applicable) for visual inspection
  - `QUEUE_URL` env var wired from `.env`
  Done when: `podman-compose up queue-broker` starts cleanly; health check passes.

- [ ] ⚠️ T2  Auth-service producer: publish OTP send jobs.
  Message schema (from `system-design/docs/queue-topology.md`):
  ```json
  { "userId": "<uuid>", "purpose": "REGISTER|FORGOT_PASSWORD", "timestamp": "<iso>" }
  ```
  Structured log on every publish:
  `[queue:publish] { queue, messageId, userId, purpose, timestamp }`
  Done when: registering a new user logs a `[queue:publish]` line and the
  message appears in the broker (CLI or management UI).

- [ ] ⚠️ T3  OTP-service consumer: subscribe to the OTP send queue.
  - On message: process (T1 in plan/04), then ack
  - On error after N retries (N from ADR): nack → routes to DLQ
  - Structured log on every ack: `[queue:ack] { messageId, userId, purpose }`
  - Structured log on every nack: `[queue:nack] { messageId, userId, error }`
  Done when: a successful OTP send logs `[queue:ack]`; a forced failure
  (invalid Twilio number with TWILIO_MOCK=false) logs `[queue:nack]` and
  the message appears in the DLQ.

- [ ] ⚠️ T4  DLQ consumer / inspector:
  - `GET /otp/dlq-count` returns `{ count: N }` by querying DLQ depth
  - On any DLQ entry: write `AuditLog` event `OTP_DLQ` with message metadata
  Done when: after a forced nack, `GET /otp/dlq-count` returns `{ count: 1 }`
  and `psql: SELECT event FROM "AuditLog" WHERE event='OTP_DLQ'` shows a row.

- [ ] ⚠️ T5  End-to-end queue smoke:
  1. `POST /auth/register` with a new phone number
  2. Observe producer log: `[queue:publish]` line in auth-service logs
  3. Inspect broker: message present (CLI `queue list` or management UI)
  4. Consumer processes: `[queue:ack]` line in otp-service logs
  5. OTPRecord created: `psql: SELECT * FROM "OTPRecord" ORDER BY "createdAt" DESC LIMIT 1`
  6. Message acked: broker shows 0 messages in queue
  Done when: all six steps complete in order; each is observable (log line or
  psql row — not inferred).

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
