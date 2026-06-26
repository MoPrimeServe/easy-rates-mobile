# 🔔 Notification Service — SMS, Push, Delivery Log

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background

Notifications appear at three points in the Figma flows: (1) OTP dispatch during
Onboarding — already handled by otp-service, (2) submission confirmation
(Reference Number Issued → Confirmation + Email/SMS) in the SUBMISSION flow, and
(3) status change alerts (Objection Upheld/Rejected/More Info Requested) in the
TRACKING & RESOLUTION flow sent via email, SMS, and push notification. This
service owns the dispatch and delivery tracking for points 2 and 3. OTP delivery
tracking stays in otp-service. `NOTIFICATION_MOCK=true` disables real dispatch
for CI and local dev.

## Description

Implement a notification dispatch service that handles SMS (Twilio) and push
notifications (FCM or APNs — from ADR). All dispatched notifications are logged
to a `NotificationLog` table. The service exposes a `POST /notify` internal
endpoint consumed by objection-service (on submit) and status-service (on status
change).

## Purpose

Covers the notification touchpoints in SUBMISSION (confirmation SMS) and
TRACKING & RESOLUTION (status alert SMS/push) Figma flows. Without this service,
the "Notification Sent to User" terminal states in both flows are unverifiable.

## Goal

`easy_rates/backend/services/notification-service/` — dispatch routes
implemented; `NotificationLog` written for every dispatch; `NOTIFICATION_MOCK=true`
skips real send; integration smoke confirms delivery log rows after submission
and status change events.

## Tasks

- [ ] ⚠️ T1  Add `NOTIFICATION_MOCK`, `FCM_SERVER_KEY` (or APNs creds from ADR),
  `TWILIO_NOTIFY_SERVICE_SID` to `shared/env.ts` Zod schema and `.env.example`.
  Done when: missing vars cause startup to fail with a clear message.

- [ ] ⚠️ T2  `POST /notify` (internal, not exposed to Flutter directly):
  - Accept `{ userId, type, channel, payload }` where:
    - `type`: `SUBMISSION_CONFIRMATION | STATUS_CHANGE | GENERAL`
    - `channel`: `SMS | PUSH | BOTH`
    - `payload`: `{ title, body, refNumber? }`
  - If `NOTIFICATION_MOCK=true`: log only, skip real dispatch
  - If SMS: call Twilio Notify or Programmable Messaging (from ADR)
  - If PUSH: call FCM/APNs with device token from User record
  - Write `NotificationLog` via Prisma: userId, type, channel, status
    (`SENT | FAILED | MOCKED`), sentAt
  - Return 202 on dispatch; 500 with reason on failure
  Done when: curl POST /notify → NotificationLog row in psql with correct status.

- [ ] ⚠️ T3  Wire objection-service to call `POST /notify` after successful
  submission: `{ type: "SUBMISSION_CONFIRMATION", channel: "SMS", payload: { title: "Objection Received", body: "Ref: {refNumber}" } }`
  Done when: submitting an objection (plan/09 T6) triggers a NotificationLog
  row with type `SUBMISSION_CONFIRMATION`.

- [ ] ⚠️ T4  `GET /notify/log?userId=<id>` — return notification history for
  a user, ordered by sentAt desc. Return 200 + array.
  Done when: curl returns log entries after T3 is exercised.

- [ ] ⚠️ T5  Seed data for notification Figma branches (add to `prisma/seed.ts`):
  - Sent notification (status SENT)
  - Failed notification (status FAILED)
  - Mocked notification (status MOCKED)
  Done when: `pnpm db:seed` runs; psql confirms NotificationLog rows.

- [ ] ⚠️ T6  Unit tests with `NOTIFICATION_MOCK=true`: dispatch SMS (mocked),
  dispatch PUSH (mocked), dispatch BOTH, delivery log written, unknown userId → 404.
  Done when: `pnpm test` passes in notification-service directory.

- [ ] ⚠️ T7  Integration smoke:
  1. Submit objection (plan/09) → POST /notify called → NotificationLog MOCKED row
  2. GET /notify/log?userId=... → row visible
  Done when: NotificationLog row with type `SUBMISSION_CONFIRMATION` confirmed
  in psql after an objection submission.

## Recommended skill

▶ `/build-to-contract` ✅ — builds notification routes from the API contract in
   `system-design/api/notification.md`.

## Engagement Instructions

```bash
# 1. Notification env vars registered in Zod schema
grep -E "NOTIFICATION_MOCK|FCM_SERVER_KEY|TWILIO_NOTIFY" \
  easy_rates/backend/shared/env.ts | wc -l
# Expected: ≥ 2 vars present in Zod schema

# 2. Unit tests green (NOTIFICATION_MOCK=true)
cd easy_rates/backend/services/notification-service && \
  NOTIFICATION_MOCK=true pnpm test
# Expected: all tests pass

# 3. POST /notify with MOCK=true: NotificationLog row with status MOCKED
SEED_USER=$(psql "$DATABASE_URL" -t -c \
  "SELECT id FROM \"User\" LIMIT 1;" | tr -d ' ')
curl -s -X POST http://localhost:${NOTIFY_PORT:-3007}/notify \
  -H "Content-Type: application/json" \
  -d "{\"userId\":\"$SEED_USER\",\"type\":\"SUBMISSION_CONFIRMATION\",\"channel\":\"SMS\",\"payload\":{\"title\":\"Test\",\"body\":\"Test body\"}}" \
  | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT type, channel, status FROM \"NotificationLog\" ORDER BY \"sentAt\" DESC LIMIT 3;"
# Expected: row with status=MOCKED

# 4. GET /notify/log returns history for user
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${NOTIFY_PORT:-3007}/notify/log?userId=$SEED_USER")
echo "notify log: HTTP $CODE"   # Expected: 200 + array with ≥ 1 entry

# 5. Integration: objection submit triggers SUBMISSION_CONFIRMATION log row
# (run after plan/09 T6 completes — do not call POST /notify directly here)
psql "$DATABASE_URL" -t -c \
  "SELECT type, status FROM \"NotificationLog\" WHERE type='SUBMISSION_CONFIRMATION' ORDER BY \"sentAt\" DESC LIMIT 1;"
# Expected: ≥ 1 row triggered by the objection submission flow
```

Gate: check 3 must produce a psql row before T3 starts. Check 5 must be
triggered by the objection submission flow — not a direct POST /notify call.
The integration between objection-service and notification-service must be
exercised end-to-end.
