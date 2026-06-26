# notification-service API contract

**Service:** notification-service
**Base path:** `/notifications` (relative to the `/api/v1` prefix — see `api/conventions.md` §1)
**Auth:** every route requires `Authorization: Bearer <accessToken>`. No `[public]` routes.

Conforms to `api/conventions.md`: `{ data, error }` envelope (§2), standard error codes (§3,
not re-documented here), ISO 8601 dates/datetimes (§9), camelCase JSON / PascalCase TS (§10),
pagination (§7). This contract states only its routes, payloads, per-route error codes, and
its own enums.

---

## ⚠ Cross-document gaps (orphan audit — do not silently resolve)

Two real discrepancies between this contract and upstream source-of-truth documents. Both are
flagged here for the orphan audit and require an upstream edit before this contract is built.

1. **Rate-limit categories are PROPOSED, not yet in `docs/security/rate-limits.md`.**
   `docs/security/rate-limits.md` has **no entries for any `/notifications/*` route**. The
   `READ` and `WRITE` categories assigned in the **Rate limits** section below are *proposed*
   mappings to the existing convention categories (`conventions.md` §5). They MUST be added to
   `docs/security/rate-limits.md` before this contract is considered hardened. Until then, the
   limiter behaviour for these routes is undefined in the source of truth.

2. **`read` / `readAt` does not exist in the data model — a schema change is REQUIRED.**
   `docs/data-model/notification.md` defines the `Notification` model with **no `readAt` and no
   `read` field**. The `GET /notifications` `read` boolean and the entire
   `POST /notifications/:id/read` endpoint depend on read-tracking state that the model does not
   yet carry. **Required data-model change:** add a nullable `readAt DateTime?` column to the
   `Notification` model. The API then derives `read = (readAt != null)`. This change must land in
   `docs/data-model/notification.md` (and the Prisma schema) before this contract is built.
   It does not alter the 90-day hard-delete retention rule.

---

## Push vs in-app: what this service does

- **PUSH / SMS / EMAIL are delivery channels** — server → provider, dispatched asynchronously
  via BullMQ (PUSH → FCM, SMS → Twilio, EMAIL → Postmark/SendGrid). They are *outbound* and are
  not driven by the routes in this contract; they are driven by domain events (e.g.
  `objection.status_changed`). See `docs/data-model/notification.md`.
- **`GET /notifications` is the in-app inbox** — the persisted history of those notifications,
  read by the Flutter app. It is the only read surface.
- **`POST /notifications/device-token` is what makes PUSH possible** — it registers/refreshes the
  FCM token on `User.deviceToken`, filling the previously-missing FCM registration endpoint.
  Without it, the PUSH channel has no token to dispatch to.

---

## Enums

Mirrored verbatim from `docs/data-model/notification.md`. Do not extend without a design decision.

```ts
type NotificationType =
  | "BILL_ISSUED"          // new bill available for the account
  | "PAYMENT_DUE"          // payment deadline approaching
  | "OBJECTION_STATUS"     // municipality changed ObjectionStatus
  | "OBJECTION_RECEIVED"   // confirmation: objection logged
  | "MORE_INFO_REQUESTED"; // municipality requests additional documents

type NotificationChannel = "PUSH" | "SMS" | "EMAIL";

type NotificationStatus =
  | "SENT"       // dispatched to channel provider
  | "DELIVERED"  // provider confirmed delivery (FCM ack, SMS DLR)
  | "FAILED"     // provider returned delivery failure
  | "PENDING";   // queued in BullMQ, not yet dispatched

type DevicePlatform = "ANDROID" | "IOS";
```

---

## Route: `GET /notifications`

Paginated in-app inbox. Returns the authenticated user's notification history, newest first
(served by the `@@index([userId, sentAt])` composite — `WHERE userId = ? ORDER BY sentAt DESC`).

**Auth:** required. Scoped to the caller's `userId` (a user only ever sees their own rows).

**Query parameters** (pagination per `conventions.md` §7):

| Param | Type | Required | Default | Notes |
|---|---|---|---|---|
| page | int | No | 1 | 1-indexed |
| pageSize | int | No | 20 | max 100 |
| unreadOnly | bool | No | false | when `true`, returns only unread rows (`readAt == null` — see gap #2) |

**Success — `200`** (envelope wraps the `Paginated<NotificationInboxItem>` shape of §7):

```json
{
  "data": {
    "items": [
      {
        "id": "clx9a1b2c3d4e5f6g7h8",
        "type": "OBJECTION_STATUS",
        "channel": "PUSH",
        "status": "DELIVERED",
        "objectionRef": "ELM-2026-004217",
        "title": "Your objection was upheld",
        "preview": "The municipality has upheld your objection on account 80045512.",
        "sentAt": "2026-06-15T10:30:00.000Z",
        "read": false
      }
    ],
    "page": 1,
    "pageSize": 20,
    "total": 42,
    "totalPages": 3
  },
  "error": null
}
```

Item field notes:
- `objectionRef` is **nullable** — null for `BILL_ISSUED` / `PAYMENT_DUE` (no linked objection;
  maps to the model's nullable `objectionId`). It is the human reference (ELM-2026-NNNNNN), not
  the raw `objectionId`.
- `read` is **derived** `readAt != null` — see gap #2 above (requires the `readAt` column).
- `title` / `preview` are render-ready inbox strings composed server-side per `type`.

**Errors:**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | `page`/`pageSize` invalid (non-int, < 1, or `pageSize` > 100) |
| 401 | `unauthenticated` | missing/expired token |

---

## Route: `POST /notifications/:id/read`

Marks one notification as read. Idempotent: marking an already-read notification returns `200`.

**Auth:** required. The notification must belong to the caller (`403` otherwise).

**Path parameter:** `id` — the `Notification.id` (cuid).

**Request body:** none.

**Success — `200`:**

```json
{ "data": { "id": "clx9a1b2c3d4e5f6g7h8", "read": true }, "error": null }
```

Sets `Notification.readAt = now()` (see gap #2 — column must be added).

**Errors:**

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | missing/expired token |
| 403 | `forbidden` | notification exists but is owned by another user |
| 404 | `not_found` | no notification with that `id` |

---

## Route: `POST /notifications/read-all`

Bulk marks every unread notification for the authenticated user as read. Idempotent: if the
caller has no unread notifications, returns `200` with `updatedCount: 0`.

**Auth:** required. Scoped to the caller's `userId` (only ever flips the caller's own rows).

**Request body:** none.

**Success — `200`:**

```json
{ "data": { "updatedCount": 7 }, "error": null }
```

Sets `Notification.readAt = now()` for all the caller's rows where `readAt IS NULL` (see gap #2 —
column must be added). `updatedCount` is the number of rows flipped (rows already read are not
re-counted).

**Errors:**

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | missing/expired token |

---

## Route: `POST /notifications/device-token`

Registers or refreshes the caller's FCM device token, enabling the PUSH channel. Writes
`User.deviceToken` (see `docs/data-model/user-auth.md` — `deviceToken String?`, "updated on app
relaunch"). Upserts: the latest token replaces the previous one.

**Auth:** required. Always writes the caller's own `User` row.

**Request body:**

| Field | Type | Required | Notes |
|---|---|---|---|
| deviceToken | string | Yes | FCM registration token |
| platform | `"ANDROID"` \| `"IOS"` | Yes | originating platform |

```json
{ "deviceToken": "fcm-eXample-Token-123…", "platform": "ANDROID" }
```

**Success — `200`:**

```json
{ "data": { "registered": true }, "error": null }
```

**Errors:**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | `deviceToken` empty/missing or `platform` not in the enum |
| 401 | `unauthenticated` | missing/expired token |

---

## TypeScript interfaces

```ts
// ---- Enums ----
type NotificationType =
  | "BILL_ISSUED"
  | "PAYMENT_DUE"
  | "OBJECTION_STATUS"
  | "OBJECTION_RECEIVED"
  | "MORE_INFO_REQUESTED";

type NotificationChannel = "PUSH" | "SMS" | "EMAIL";

type NotificationStatus = "SENT" | "DELIVERED" | "FAILED" | "PENDING";

type DevicePlatform = "ANDROID" | "IOS";

// ---- GET /notifications ----
interface NotificationInboxItem {
  id: string;
  type: NotificationType;
  channel: NotificationChannel;
  status: NotificationStatus;
  objectionRef: string | null; // null for BILL_ISSUED / PAYMENT_DUE
  title: string;
  preview: string;
  sentAt: string;              // ISO 8601 datetime, UTC
  read: boolean;               // derived: readAt != null
}

// Response is Paginated<NotificationInboxItem> per conventions §7:
// interface Paginated<T> { items: T[]; page; pageSize; total; totalPages; }

// ---- POST /notifications/:id/read ----
interface NotificationReadResponse {
  id: string;
  read: true;
}

// ---- POST /notifications/read-all ----
interface MarkAllReadResponse {
  updatedCount: number; // rows flipped to read for the caller
}

// ---- POST /notifications/device-token ----
interface DeviceTokenRegisterRequest {
  deviceToken: string;
  platform: DevicePlatform;
}

interface DeviceTokenRegisterResponse {
  registered: true;
}
```

---

## Figma Trace

notification-service owns two screens in `docs/screen-inventory.md` (SUBMISSION
"Confirmation + Email / SMS" and TRACKING & RESOLUTION "Notification Sent to User") and the
notification **deep-link map**. Note: **ACCOUNT & SETTINGS has no dedicated
notification-history screen** — there is no "inbox" screen in the inventory. The `GET
/notifications` inbox surfaces *via push deep-links* (and as the backing history a future inbox
screen would read); each delivered notification deep-links to the destination below.

| Screen / event | Route | Notes |
|---|---|---|
| SUBMISSION → Confirmation + Email / SMS | (outbound) `draft → submitted` → EMAIL + SMS dispatch | Async via BullMQ; not a request route. Deep-link → Track Objection Status. |
| TRACKING → Notification Sent to User | (outbound) status-change dispatch | Confirms PUSH/EMAIL/SMS sent; async, not a request route. |
| Any delivered PUSH notification | `GET /notifications` | Inbox is the in-app history backing the deep-links; no dedicated inventory screen. |
| Inbox row tapped / item displayed | `POST /notifications/:id/read` | Marks the tapped notification read. |
| Inbox "mark all read" action | `POST /notifications/read-all` | Flips every unread row for the caller; returns `updatedCount`. |
| App launch / relaunch | `POST /notifications/device-token` | Registers/refreshes FCM token so PUSH can be delivered at all. |

### Notification deep-link map (from `docs/screen-inventory.md`)

The outbound channels (the async PUSH/SMS/EMAIL dispatch this service performs) carry these
deep-links; the resulting rows appear in `GET /notifications`.

| Status transition | Channels | Deep-link destination | Inbox `type` |
|---|---|---|---|
| `kyc_pending → kyc_approved` | Push | Home Dashboard | — (auth-service KYC, not a Notification type) |
| `kyc_pending → kyc_rejected` | Push | KYC Rejected | — (auth-service KYC) |
| `draft → submitted` (confirmation) | Email + SMS | Confirmation + Email/SMS | `OBJECTION_RECEIVED` |
| `pending → more_info_requested` | Email + SMS + Push | 🔁 More Info Requested | `MORE_INFO_REQUESTED` |
| `pending → rejected` | Email + SMS + Push | ❌ Objection Rejected | `OBJECTION_STATUS` |
| `pending → upheld` | Email + SMS + Push | ✅ Objection Upheld | `OBJECTION_STATUS` |
| Probe auto-escalation (3rd probe) | Push | Track Objection Status | `OBJECTION_STATUS` |

(`BILL_ISSUED` / `PAYMENT_DUE` are bill-lifecycle notifications with `objectionRef = null`; they
have no objection-status deep-link row above.)

---

## Rate limits

Categories from `conventions.md` §5. **See gap #1 above** — these are **proposed** mappings;
`docs/security/rate-limits.md` currently has **no `/notifications/*` entries** and must be
amended to add them.

| Route | Category (proposed) | Scope | Window | Limit |
|---|---|---|---|---|
| `GET /notifications` | READ | userId | 1 min | 60 |
| `POST /notifications/:id/read` | WRITE | userId | 1 hour | 20 |
| `POST /notifications/read-all` | WRITE | userId | 1 hour | 20 |
| `POST /notifications/device-token` | WRITE | userId | 1 hour | 20 |

On `429` the body is the standard `rate_limit_exceeded` envelope with
`details.retryAfterSeconds` and `RateLimit-*` / `Retry-After` headers (`conventions.md` §5).
