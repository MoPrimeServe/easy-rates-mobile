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

- [x] ✅ — ✓ verified (2026-06-27 adapters) T1  Env + real **FCM** push adapter.
  `REDIS_URL` already present; FCM env added to `packages/config` Zod +
  `.env.example` (placeholders): `GOOGLE_APPLICATION_CREDENTIALS`, `FCM_PROJECT_ID`,
  `PUSH_DRIVER`. `packages/queue/src/push-provider.ts` implements `FcmPushProvider`
  (firebase-admin `messaging().send`) + `MockPushProvider`, selected by
  `PUSH_DRIVER` (fcm when a credential is present, else mock; default-safe with a
  mock fallback if init fails). Wired into the notification worker
  (`processNotificationJob` dispatches PUSH-channel rows with a device token via
  the selected provider; push failure is logged and never fails the job). LIVE
  SMOKE: firebase-admin initialised for project `easyrates-10809`; a **dry-run**
  send (`send(msg, true)`) with a dummy token round-tripped (FCM returned
  `messaging/invalid-argument` — a token-level rejection that proves auth/project
  authenticated; no delivery). APNs / `TWILIO_NOTIFY_SERVICE_SID` remain ⚠️ TODO.

- [x] ❌ DESCOPED (2026-06-27) T2  `POST /notify` HTTP route. The canonical
  notification-service contract has **no inbound `/notify` route** — outbound
  dispatch is event-driven via BullMQ, and the persisted `Notification` row is the
  source of truth. Implemented instead: the `notification` queue + worker in
  `packages/queue` (`enqueueNotification` / `processNotificationJob`), which
  mock-sends the push and flips `Notification.status → SENT`. The Flutter-facing
  routes are the 4 below. `SUBMISSION_CONFIRMATION`/`MOCKED` etc. are not in the
  canonical enums (`NotificationType` / `NotificationStatus`).

- [x] ✅ — ✓ verified (2026-06-27) T2b  `GET /notifications` (paginated inbox,
  `unreadOnly` filter); `POST /notifications/:id/read` (idempotent, 403/404 guards);
  `POST /notifications/read-all` → `{ updatedCount }`; `POST /notifications/device-token`
  → writes `User.deviceToken`. All auth-required, Prisma-backed, server-composed
  title/preview per type. Verified via smoke (unreadOnly list of 4, read-all
  updatedCount=4, device-token registered) + unit tests (`inboxWhere`, `countUnread`,
  `isRead`, `toInboxItem`).

- [x] ✅ — ✓ verified (2026-06-27) T3  Objection submission triggers a
  notification — but via the **BullMQ queue**, not `POST /notify`. The
  `objection-submit` worker persists an `OBJECTION_RECEIVED` Notification row and
  enqueues it; the municipality webhook persists `OBJECTION_STATUS` /
  `MORE_INFO_REQUESTED`. Verified via smoke: submitting ELM-2026-000002 produced
  the OBJECTION_RECEIVED row (psql); the webhook produced OBJECTION_STATUS — both
  dispatched to SENT.

- [x] ✅ — ✓ verified (2026-06-27) T4  Notification history is `GET /notifications`
  (canonical), NOT `GET /notify/log?userId=` — it is auth-scoped to the caller
  (never a query-param userId), paginated, newest-first, with the `unreadOnly`
  filter. Verified via smoke. (The `/notify/log` shape is DESCOPED.)

- [x] ✅ — ✓ verified (2026-06-27) T5  The seed already provides an
  `OBJECTION_RECEIVED` notification; the smoke generates more live
  (OBJECTION_RECEIVED + OBJECTION_STATUS). No `MOCKED`/`FAILED` seed rows needed —
  those statuses are not canonical (`NotificationStatus` = SENT/DELIVERED/FAILED/
  PENDING; the worker uses PENDING → SENT).

- [x] ✅ — ✓ verified (2026-06-27) T6  Unit tests (vitest, 11 passing): `inboxWhere`
  unreadOnly filter, `countUnread` read-all updatedCount semantics, `isRead`
  derivation, `toInboxItem` title/preview/objectionRef. (SMS/PUSH/BOTH + 404
  cases DESCOPED — no `/notify` route.)

- [x] ✅ — ✓ verified (2026-06-27) T7  Integration smoke vs live DB + Redis:
  submission and webhook persisted Notification rows; `GET /notifications?unreadOnly=true`
  returned 4 unread; `read-all` flipped them (updatedCount=4); `device-token`
  registered. psql confirmed the rows + their SENT status + readAt set after read-all.

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

---

## Execution Note — 2026-06-27

Built the notification-service to the **canonical** `system-design/api/notification-service.md`
contract. The plan above predated it and described an internal `POST /notify` route, a
`NotificationLog` table, and `MOCKED`/`SUBMISSION_CONFIRMATION` enum values — all superseded.

Canonical model: **the persisted `Notification` row is the source of truth**; PUSH/SMS/EMAIL
are async wake-hints. Implemented the 4 Flutter-facing routes (`GET /notifications` with
`unreadOnly`, `POST /:id/read`, `POST /read-all` → `updatedCount`, `POST /device-token`),
plus the BullMQ `notification` queue + worker (`packages/queue`) that mock-sends push and
flips `status → SENT`. Resolved data-model gap #2 — the `readAt` column already exists in the
migrated schema, so `read = (readAt != null)` is derived directly.

Verified: `pnpm -r exec tsc --noEmit` → 0; 11 unit tests green; live-DB+Redis smoke
(transcript + psql). Honest ⚠️: real FCM/APNs/Twilio adapters and the full rate-limit infra.

---

## Execution Note — 2026-06-27 (adapters)

Wired the **real FCM** push adapter and the **rate-limiter**.
- `packages/queue/src/push-provider.ts` — `PushProvider` interface with
  `FcmPushProvider` (firebase-admin `applicationDefault`/cert from
  `GOOGLE_APPLICATION_CREDENTIALS`, `messaging().send(message, dryRun?)`) and
  `MockPushProvider`. `selectPushProvider()` picks by `PUSH_DRIVER` (fcm iff a
  credential resolves, else mock; mock fallback on init failure). The notification
  worker now dispatches PUSH-channel rows with a device token through it (push is
  a wake-hint — failures are logged, the row still flips to SENT).
- Env added to `packages/config` + `.env.example` (placeholders):
  `GOOGLE_APPLICATION_CREDENTIALS`, `FCM_PROJECT_ID`, `PUSH_DRIVER`.
- READ/WRITE rate-limits wired on the notification routes (inbox → READ;
  read/read-all/device-token → WRITE).

**Verification**
- `pnpm -r exec tsc --noEmit` → 0; full suite **104 passed** (queue +5 push-provider
  tests: FCM message-shape + dryRun forwarding, error propagation, mock no-op,
  credential-path resolution).
- LIVE SMOKE: firebase-admin init for project `easyrates-10809`; **dry-run** send
  with a dummy token round-tripped (`messaging/invalid-argument` = auth OK,
  no delivery). Honest ⚠️ remaining: APNs, Twilio SMS/EMAIL channels.
