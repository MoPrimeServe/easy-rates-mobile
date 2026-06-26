# 🔔 Notification Service Contract

## Background

✅ resolved[Gate] — `api/conventions.md` exists (pagination §7 L185-204, envelope §2).
✅ resolved[Gate] — `docs/data-model/notification.md` exists with the Notification schema
block, `NotificationChannel` enum (PUSH | SMS | EMAIL, L12-15), and the
`@@index([userId, sentAt])` composite the GET route relies on.

The notification service handles the in-app notification fetch in the TRACKING &
RESOLUTION Figma flow. Push notifications are delivered async via a separate channel
(FCM/APNs) — they are NOT REST endpoints. This contract covers only the in-app
REST fetch and mark-read endpoint.

## Description

Write the HTTP API contract for the notification service: GET list (paginated),
PATCH mark-read. Documents the push vs in-app split so Flutter developers don't
expect push delivery to go through the REST API.

## Purpose

To answer: "does the Flutter app get new notifications by polling the REST API,
listening for push, or both — and how do push notifications and in-app notifications
stay in sync?"

## Goal

`easy_rates/system-design/api/notification-service.md` — 2 routes with TypeScript
interfaces; push vs in-app split documented; 3 channel types noted; pagination.

## Tasks

- [x] ✅ — ✓ verified (deliverable "Push vs in-app: what this service does" + data-model
  note: PUSH/SMS/EMAIL are outbound async channels via BullMQ; `GET /notifications` is the
  in-app inbox / REST fallback; data-model L88 states Flutter polls or uses FCM push, does
  not read the Notification table directly — covers the push-disabled / foreground fallback) THINK `/socratic "The Flutter TRACKING & RESOLUTION flow shows the user
  a notification when their objection status changes. Does the Flutter app discover
  this change by polling the notification list endpoint, by receiving a push
  notification, or by both — and if both, what happens when they disagree? And if
  the user has push disabled, how do they see the notification?"`
  Done when: the push vs in-app sync model is described; the "push disabled" fallback
  is stated; the Flutter polling or push-receipt flow is documented.

- [x] ✅ — ✓ verified (deliverable "Figma Trace" table + deep-link map: bell/inbox push →
  `GET /notifications`, inbox row tapped → `POST /notifications/:id/read`, app launch →
  `POST /notifications/device-token`; deep-link map routes each status transition to its
  destination screen and inbox `type`) FIGMA-TRACE Map every TRACKING & RESOLUTION notification-related transition:
  Notification bell icon tapped → GET /api/v1/notification (unread list)
  Notification item tapped → navigate to objection detail (objection-service, not here)
  "Mark as read" → PATCH /api/v1/notification/:id/read (or bulk mark-read)
  Push received → Flutter push handler calls GET /api/v1/notification to refresh
  For each: Flutter widget; which response field updates which UI element.
  Done when: all notification-related TRACKING transitions mapped.

- [x] ✅ — ✓ verified (deliverable `GET /notifications` query-param table now includes
  `unreadOnly` (bool, default false) — the read-state filter the task asked for; when true,
  returns only unread rows `readAt == null`. Named `unreadOnly` rather than `isRead` for a clear
  boolean default, satisfying "filter to unread only".) GET-LIST Define `GET /api/v1/notification`:
  Query params: `page?`, `pageSize?`, `isRead?` (filter to unread only)
  Response 200: pagination shape wrapping `NotificationItem[]`
  `NotificationItem`:
  ```typescript
  interface NotificationItem {
    id: string;
    title: string;
    body: string;
    channel: "PUSH" | "SMS" | "EMAIL";
    isRead: boolean;
    sentAt: string;   // ISO 8601
    readAt: string | null;
    objectionId: string | null;  // null if not objection-related
  }
  ```
  Note: `channel` is the delivery channel the notification was sent via, not a
  filter parameter. The REST endpoint returns ALL notification records regardless
  of channel (they are stored after dispatch, not before).
  Done when: pagination applied; `isRead` filter param documented.

- [x] ✅ — ✓ verified (both defined: single `POST /notifications/:id/read`
  (`NotificationReadResponse`) and bulk `POST /notifications/read-all` returning
  `MarkAllReadResponse { updatedCount: number }` — the count of rows flipped to read for the
  caller; route + interface + Figma Trace row + rate-limit entry all present. Deliverable uses
  `POST` not `PATCH` — an intentional contract choice, not the gap.) MARK-READ Define `PATCH /api/v1/notification/:id/read`:
  Response 200: `{ data: { id: string, isRead: true, readAt: string }, error: null }`
  Also define bulk: `PATCH /api/v1/notification/read-all`:
  Response 200: `{ data: { updatedCount: number }, error: null }`
  TypeScript interface: `MarkReadResponse`, `MarkAllReadResponse`
  Done when: both single and bulk mark-read defined.

- [x] ✅ — ✓ verified (deliverable "Push vs in-app" section: PUSH async via FCM dispatched by
  BullMQ worker after a Notification record is created; REST `/notifications` reflects stored
  records as the fallback when push is disabled/foreground; `channel: "PUSH"` means push sent
  AND record in inbox. FCM device-token registration defined as `POST /notifications/device-token`
  writing `User.deviceToken` — decision made: it lives on this service, not account-service) PUSH-MODEL Document the push delivery model (not an API endpoint):
  Push notifications are delivered async via FCM (Android) and APNs (iOS).
  The Flutter app registers a device token at login; the notification-service
  dispatches push via the queue worker after a Notification record is created.
  The REST API `/notification` endpoint reflects the stored Notification records
  — polling this endpoint is the fallback when push is disabled or the app is
  in the foreground.
  Push and in-app are the same Notification record — `channel: "PUSH"` means
  both a push was sent AND the record is in the in-app list.
  FCM/APNs device token registration: PATCH /api/v1/account/device-token
  (or is this its own endpoint? Decide and document.)
  Done when: push delivery model described; FCM/APNs device token registration
  endpoint defined or referenced.

- [x] ✅ — ✓ verified (file `easy_rates/system-design/api/notification-service.md` exists;
  "Push vs in-app: what this service does" section makes the split explicit; 3 channels noted
  as `NotificationChannel = "PUSH" | "SMS" | "EMAIL"`; TypeScript interfaces + Figma Trace
  present. Deliverable actually ships 3 routes — adds `device-token` beyond the planned 2) WRITE Write `easy_rates/system-design/api/notification-service.md`:
  2 REST routes + push model documentation; TypeScript interfaces; Figma Trace.
  Done when: file exists; push vs in-app split explicit; 3 channels noted.

- [x] ✅ — ✓ verified (all three pass: (1) `NotificationChannel = "PUSH" | "SMS" | "EMAIL"`
  in deliverable matches `docs/data-model/notification.md` L12-15 enum verbatim; (2) pagination
  is `Paginated<NotificationInboxItem>` with items/page/pageSize/total/totalPages, matching
  conventions.md §7 L189-197; (3) FCM device-token registration defined as
  `POST /notifications/device-token`) VERIFY Confirm: `channel` field in NotificationItem uses the 3 enum values
  from data-model/notification.md (PUSH | SMS | EMAIL).
  Confirm: pagination shape matches conventions.md.
  Confirm: FCM/APNs device token registration endpoint is defined somewhere.
  Done when: all three confirmations pass.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "push vs in-app sync" question forces the
   delivery model to be explicit before the Flutter developer implements the
   notification screen.
   — custom for contract writing.

## Engagement Instructions

Pass condition: push vs in-app delivery model is documented — not an API endpoint,
but a prose explanation of the async delivery and REST fallback.
Pass condition: `channel` field uses exactly 3 values matching data-model enum.
Pass condition: bulk mark-all-read endpoint defined.
Pass condition: FCM/APNs device token registration is addressed (endpoint defined
or explicitly referenced).
Pass condition: Figma Trace maps push-received → notification list refresh flow.

## Execution Note — 2026-06-27

Verified the deliverable `easy_rates/system-design/api/notification-service.md` against each
task. ALL_DONE: **no** — two tasks remain honestly ⚠️ (the deliverable scoped them
differently than the plan asked).

### THINK answer (verbatim)

The Flutter app uses **both**, with a clear primary/fallback split rather than two competing
sources of truth. The single source of truth is the **persisted `Notification` record**: the
notification-service writes the row (inside the objection status-change flow) and then, async
via the BullMQ queue worker, dispatches a PUSH to FCM using the device token registered at
login. The push is a **delivery hint that wakes the app**, not the data itself — when the
Flutter push handler receives it, it calls `GET /notifications` to pull the authoritative
inbox. So push and in-app cannot meaningfully "disagree": the push only triggers a refresh of
the same record the inbox reads. When the app is in the foreground, FCM may be suppressed by
the OS, so the app **polls `GET /notifications`** instead; the data-model note (notification.md
L88) states explicitly that "the Flutter app polls or uses FCM push delivery; it does not read
the Notification table directly." If the user has **push disabled**, the in-app inbox poll is
the fallback — they still see every notification because every dispatched notification is a
stored row (`channel: "PUSH"` means a push was sent AND the record is in the in-app list), they
just see it on next open/poll rather than as a banner. There is a small race the model
acknowledges: a `Notification` row may not exist for a few seconds after the status changes
(step 3 is async), so a poll immediately after a transition can briefly miss it — resolved on
the next poll or by the push that follows dispatch.

### Per-task evidence

- THINK — ✅ deliverable "Push vs in-app" section + data-model L88 (poll-or-FCM, foreground
  fallback, push-disabled = inbox poll).
- FIGMA-TRACE — ✅ deliverable "Figma Trace" table + deep-link map (bell/push → `GET`, row
  tap → `:id/read`, launch → `device-token`).
- GET-LIST — ⚠️ pagination + `NotificationInboxItem` present, but the `isRead?` query filter
  param is NOT documented (query-param table is `page`/`pageSize` only). "Done when … isRead
  filter param documented" unmet.
- MARK-READ — ⚠️ single `POST /notifications/:id/read` defined, but bulk `read-all` /
  `MarkAllReadResponse` / `updatedCount` NOT defined. "Done when: both single and bulk … "
  unmet. (Deliverable uses `POST` not `PATCH` — a contract choice, not the gap.)
- PUSH-MODEL — ✅ async FCM via BullMQ; REST `/notifications` as fallback; FCM device-token
  registration defined as `POST /notifications/device-token` (decision: on this service).
- WRITE — ✅ file exists; push/in-app split explicit; 3 channels noted; TS + Figma Trace
  present (ships 3 routes — adds `device-token`).
- VERIFY — ✅ all three confirmations pass: channel enum matches data-model L12-15 verbatim;
  pagination matches conventions §7 L189-197; device-token endpoint defined.

### Gap-fill — 2026-06-27

Closed the two open gaps: added `unreadOnly` query param to `GET /notifications` and bulk
`POST /notifications/read-all` (`MarkAllReadResponse { updatedCount }`) with Figma Trace + rate-limit
rows; GET-LIST and MARK-READ now ✅. ALL_DONE: **yes**.
