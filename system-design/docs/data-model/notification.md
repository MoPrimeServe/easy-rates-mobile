# EasyRates — Notification & Municipality Response Models

**Service ownership:** notification-service (Notification) · status-service (MunicipalityResponse)  
**Patches applied:** DECISION-A (deletedAt on MunicipalityResponse) · DECISION-D (cuid PKs)

---

## Enums

```prisma
// Three channels locked from the Figma PDF — do not extend without design decision.
enum NotificationChannel {
  PUSH   // Firebase Cloud Messaging (FCM) via User.deviceToken
  SMS    // Twilio Programmable SMS
  EMAIL  // Postmark or SendGrid (configured in plan/07)
}

enum NotificationType {
  BILL_ISSUED           // new bill available for the account
  PAYMENT_DUE           // payment deadline approaching
  OBJECTION_STATUS      // municipality changed ObjectionStatus
  OBJECTION_RECEIVED    // confirmation to ratepayer: objection logged
  MORE_INFO_REQUESTED   // municipality requests additional documents
  KYC_STATUS            // KYC proof-of-address approved or rejected (push deep-link); api orphan audit F-2
}

enum NotificationStatus {
  SENT        // dispatched to channel provider
  DELIVERED   // provider confirmed delivery (FCM ack, SMS DLR)
  FAILED      // provider returned delivery failure
  PENDING     // queued in BullMQ, not yet dispatched
}
```

---

## Model: Notification

```prisma
model Notification {
  id          String              @id @default(cuid())
  userId      String
  objectionId String?
  type        NotificationType
  channel     NotificationChannel
  status      NotificationStatus  @default(PENDING)
  sentAt      DateTime            @default(now())
  readAt      DateTime?           // null = unread; set by POST /notifications/:id/read; api orphan audit D-3

  user      User       @relation(fields: [userId], references: [id], onDelete: Cascade)
  objection Objection? @relation(fields: [objectionId], references: [id], onDelete: SetNull)

  @@index([userId, sentAt])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | No | — | included | — | |
| objectionId | String | Yes | — | — | — | null for bill/payment notifications |
| type | NotificationType | No | — | — | — | |
| channel | NotificationChannel | No | — | — | — | |
| status | NotificationStatus | No | — | — | PENDING | |
| sentAt | DateTime | No | — | included | now() | |
| readAt | DateTime | Yes | — | — | — | null = unread; set on `POST /notifications/:id/read`. API derives `read = readAt != null` |

**`@@index([userId, sentAt])`** — serves the notification inbox query:
```
WHERE userId = ? ORDER BY sentAt DESC LIMIT 20
```
Rolling 225,000 active rows at 12 months (90-day retention purge). Without this index, the query would scan 225k rows on every notification screen load. The composite covers equality on `userId` (left) and descending sort on `sentAt` (right).

### Retention

Notification is **hard-deleted** after 90 days. A BullMQ scheduled job runs daily: `DELETE WHERE sentAt < NOW() - INTERVAL 90 days`. No soft-delete — DECISION-A explicitly excludes Notification ("operational log; no legal obligation"). The rolling active row count stays at ~225,000 in production.

### Write sequence for a municipality status update

When the status-service ingests a `MunicipalityResponse`:

1. `status-service`: INSERT MunicipalityResponse
2. `status-service`: UPDATE Objection SET status = <new status>
3. `notification-service` (via BullMQ `objection.status_changed` event): INSERT Notification

Steps 1 and 2 are in a single transaction. Step 3 is async via BullMQ — the notification-service consumes the queue event. This means a Notification row may not exist for a few seconds after the Objection status changes. The Flutter app polls or uses FCM push delivery; it does not read the Notification table directly to detect status changes.

### onDelete policies

- `userId → User`: `Cascade` — if a user is hard-deleted (dev teardown or test), all notifications cascade. In production, User is soft-deleted, so this cascade never fires against real data.
- `objectionId → Objection`: `SetNull` — if an Objection is deleted (dev teardown; Objections are soft-deleted in production), the notification row is retained but `objectionId` is set to null. This preserves the notification history even if the objection is later soft-deleted.

---

## Model: MunicipalityResponse

```prisma
model MunicipalityResponse {
  id             String          @id @default(cuid())
  objectionId    String
  status         ObjectionStatus // the new status the municipality is setting
  note           String?         // optional written justification from the municipality
  adjustedAmount Decimal?        // set when UPHELD with a proposed adjustment
  deletedAt      DateTime?       // DECISION-A: legal record of municipality's formal response
  respondedAt    DateTime        @default(now())

  objection Objection @relation(fields: [objectionId], references: [id], onDelete: Restrict)
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| objectionId | String | No | — | — | — | FK onDelete: Restrict |
| status | ObjectionStatus | No | — | — | — | The status being set |
| note | String | Yes | — | — | — | Municipality's written reason |
| adjustedAmount | Decimal | Yes | — | — | — | Present when UPHELD with amount change |
| deletedAt | DateTime | Yes | — | — | — | DECISION-A soft-delete marker |
| respondedAt | DateTime | No | — | — | now() | |

No `@@index` on `objectionId` — projected < 2,500 rows (one per objection, at most a handful of responses per objection). Full table scan is negligible at this volume.

### onDelete: Restrict rationale

`objectionId → Objection` uses Restrict — a MunicipalityResponse is a legal record of the municipality's formal response to a dispute. It must not be deleted or orphaned. If an Objection is soft-deleted, the MunicipalityResponse is soft-deleted separately (not cascade-deleted). If an Objection is hard-deleted (dev teardown only), the Restrict policy prevents the deletion unless all linked MunicipalityResponse rows are first removed.

### Duplicate status update handling

If a MunicipalityResponse is received for an Objection that is already `UPHELD` or `REJECTED`, the service handler should:
1. Insert the new MunicipalityResponse row (all responses are logged for audit).
2. Update `Objection.status` only if the new status is not a terminal-back-to-open transition (i.e., re-opening a closed case requires an explicit service-level guard).
3. The database has no constraint preventing multiple MunicipalityResponse rows per Objection — the service layer is responsible for terminal-state guards.
