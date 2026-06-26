# EasyRates — User & Auth Models

**Service ownership:** auth-service (User, AuditEvent) · otp-service (OTPAttempt)  
**Patches applied:** DECISION-A (deletedAt on User) · DECISION-B (AuditEvent model) · DECISION-D (cuid PKs) · ADR-002 (passwordless OTP-first: `passwordHash` removed, `OtpPurpose.PASSWORD_RESET` dropped)

---

## Enums

```prisma
enum KycStatus {
  PENDING       // no document submitted yet
  SUBMITTED     // document uploaded, awaiting verification
  VERIFIED      // identity confirmed by municipality or third-party KYC
  REJECTED      // document invalid or not accepted
}

enum OtpPurpose {
  LOGIN         // OTP-only login (ADR-002 passwordless) — verify issues the session token pair
  REGISTRATION  // confirm phone during account creation — verify issues a single-use registrationToken
}

enum AuditEventType {
  // POPIA-mandatory events
  BILL_ACCESSED
  OBJECTION_SUBMITTED
  OBJECTION_STATUS_CHANGED
  EVIDENCE_UPLOADED
  KYC_DOCUMENT_UPLOADED
  KYC_STATUS_CHANGED
  USER_PII_ANONYMISED
  // Security events
  OTP_FAILED
  LOGIN_FAILED
  // Operational (log at discretion)
  LOGIN_SUCCESS
  MUNICIPALITY_RESPONSE_RECEIVED
  PROPERTY_SEARCHED
}
```

---

## Model: User

```prisma
model User {
  id             String    @id @default(cuid())
  phone          String    @unique
  email          String?   @unique
  displayName    String?
  idNumberHash   String?   // HMAC-SHA256(KMS pepper, SA ID); plaintext never stored — ADR-003
  deviceToken    String?   // FCM device token for push notifications
  kycStatus      KycStatus @default(PENDING)
  kycDocumentKey String?   // Azure Blob Storage key; POPIA: never the raw document
  deletedAt      DateTime? // DECISION-A: soft-delete; PII anonymised on erasure
  createdAt      DateTime  @default(now())
  updatedAt      DateTime  @updatedAt

  otpAttempts     OTPAttempt[]
  accounts        Account[]
  objectionDrafts ObjectionDraft[]
  objections      Objection[]
  notifications   Notification[]
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | DECISION-D |
| phone | String | No | Yes | — | — | Login and OTP verification hot path |
| email | String | Yes | Yes | — | — | Optional; unique if present |
| displayName | String | Yes | — | — | — | |
| idNumberHash | String | Yes | — | — | — | ADR-003: keyed hash of SA ID for the property identity gate; plaintext never stored |
| deviceToken | String | Yes | — | — | — | FCM push; updated on app relaunch |
| kycStatus | KycStatus | No | — | — | PENDING | |
| kycDocumentKey | String | Yes | — | — | — | POPIA: blob key, not document content |
| deletedAt | DateTime | Yes | — | — | — | DECISION-A soft-delete marker |
| createdAt | DateTime | No | — | — | now() | |
| updatedAt | DateTime | No | — | — | @updatedAt | |

No `@@index` on User: `phone` and `email` each have `@unique` (which creates a unique index). All other fields are not queried by WHERE.

### POPIA note

`kycDocumentKey` stores an Azure Blob Storage key pointing to a proof-of-address or SA ID photo. The document itself is never stored in the database. Accessing the blob from a service handler MUST emit a `KYC_DOCUMENT_UPLOADED` or `KYC_STATUS_CHANGED` AuditEvent.

On a POPIA erasure request: null out `phone`, `email`, `displayName`, `idNumberHash`, `deviceToken`, `kycDocumentKey`; set `deletedAt = now()`. Delete the blob at `kycDocumentKey`. The User row is NOT hard-deleted — it remains as the FK anchor for Objection (`onDelete: Restrict`). See DECISION-A.

---

## Model: OTPAttempt

```prisma
model OTPAttempt {
  id          String     @id @default(cuid())
  userId      String
  code        String     // bcrypt hash — never stored or compared in plaintext
  purpose     OtpPurpose
  attempts    Int        @default(0)
  maxAttempts Int        @default(3)
  expiresAt   DateTime
  verifiedAt  DateTime?
  createdAt   DateTime   @default(now())

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([userId, expiresAt])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | No | — | included | — | |
| code | String | No | — | — | — | bcrypt hash of the OTP code |
| purpose | OtpPurpose | No | — | — | — | |
| attempts | Int | No | — | — | 0 | |
| maxAttempts | Int | No | — | — | 3 | Configurable per-purpose |
| expiresAt | DateTime | No | — | included | — | |
| verifiedAt | DateTime | Yes | — | — | — | null = not yet verified |
| createdAt | DateTime | No | — | — | now() | |

**`@@index([userId, expiresAt])`** — primary query is `WHERE userId = ? AND expiresAt > NOW() AND verifiedAt IS NULL`. Composite index serves equality on userId (left) and range filter on expiresAt (right). Correct column ordering for this query pattern.

Projected 33,000 active rows at 12 months (30-day TTL purge). A 30-day BullMQ purge job deletes rows where `expiresAt < NOW() - 30 days`.

---

## Model: AuditEvent

```prisma
model AuditEvent {
  id         String         @id @default(cuid())
  userId     String?        // nullable: pre-auth events (OTP_FAILED) have no userId
  event      AuditEventType
  entityId   String?        // e.g. objectionId, billId — the record being accessed
  entityType String?        // e.g. "Objection", "Bill"
  metadata   Json?          // IP address, userAgent, old/new status, affected fields
  createdAt  DateTime       @default(now())

  @@index([userId, createdAt])
  @@index([entityId, entityType])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | Yes | — | included | — | Nullable: pre-auth events |
| event | AuditEventType | No | — | — | — | |
| entityId | String | Yes | — | included | — | Per-record audit trail |
| entityType | String | Yes | — | included | — | Composite with entityId |
| metadata | Json | Yes | — | — | — | IP, userAgent, deltas |
| createdAt | DateTime | No | — | — | now() | |

`userId` is NOT a Prisma `@relation` to User. On User anonymisation, the service handler manually sets `userId = null` rather than relying on `onDelete: SetNull` — this avoids a FK cycle and keeps the audit record semantically meaningful ("this event happened, the user was later anonymised").

**`@@index([userId, createdAt])`** — serves `GET /admin/audit?userId=X&from=Y&to=Z`. Projected 300,000+ rows/year.

**`@@index([entityId, entityType])`** — serves `GET /admin/audit?entityType=Objection&entityId=<id>`. Per-record audit history for compliance review.

AuditEvent is **append-only**. No `deletedAt`. No service may delete or soft-delete an AuditEvent row. The soft-delete middleware in `shared/db.ts` explicitly excludes AuditEvent.
