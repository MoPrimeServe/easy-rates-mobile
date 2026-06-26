# EasyRates — Objection, Evidence & Draft Models

**Service ownership:** objection-service  
**Patches applied:** DECISION-A (deletedAt on Objection, EvidenceFile) · DECISION-C (municipalityId on Objection) · DECISION-D (cuid PKs)

---

## Enums

```prisma
// Four values locked from the Figma EVIDENCE & CHALLENGE flow.
// Do NOT add or rename values without a formal design decision and migration plan.
enum ObjectionCategory {
  WRONG_METER_READING
  INCORRECT_TARIFF
  PROPERTY_NOT_OCCUPIED
  DUPLICATE_OTHER
}

// Four values locked from the Figma TRACKING & RESOLUTION flow.
// These are the four states the municipality can set on a submitted objection.
// Do NOT add values without a formal design decision.
enum ObjectionStatus {
  UNDER_REVIEW         // initial state on submission; municipality is reviewing
  MORE_INFO_REQUESTED  // municipality requests additional documentation
  UPHELD               // municipality accepted the dispute; adjustment will be issued
  REJECTED             // municipality rejected the dispute
}
```

### ObjectionStatus note

The four values above are the Figma-canonical states for an objection **after submission**. There is no `DRAFT` value — the draft phase is represented by the separate `ObjectionDraft` model. When a draft is submitted, an `Objection` record is created with `status = UNDER_REVIEW`. There is no intermediate `SUBMITTED` state: the act of creating an `Objection` row is the submission.

This differs from `plans/09-objection-service.md` which includes a `DRAFT` status on `Objection`. In this design, `ObjectionDraft` is a separate entity (not a status value on `Objection`) to keep the two lifecycle stages cleanly separated and to avoid nullable fields on the submitted record.

---

## Model: ObjectionDraft

```prisma
model ObjectionDraft {
  id         String            @id @default(cuid())
  userId     String
  lineItemId String?
  category   ObjectionCategory
  notes      String?
  savedAt    DateTime          @default(now())

  user     User          @relation(fields: [userId], references: [id], onDelete: Cascade)
  lineItem BillLineItem? @relation(fields: [lineItemId], references: [id], onDelete: SetNull)
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | No | — | — | — | FK; no @@index — lookup is always by userId + id |
| lineItemId | String | Yes | — | — | — | Optional: user may not have selected a line item yet |
| category | ObjectionCategory | No | — | — | — | |
| notes | String | Yes | — | — | — | Draft notes |
| savedAt | DateTime | No | — | — | now() | |

No `@@index` on ObjectionDraft: projected < 1,000 rows at any time (transient; purged after 30 days of inactivity or on submit). A full table scan on < 1,000 rows is irrelevant. Any query filters by `userId`, and with < 1,000 rows the scan cost is negligible.

### Lifecycle

ObjectionDraft is **hard-deleted** on two events:
1. **Submit**: objection-service creates an `Objection` record, then hard-deletes the draft. There is no FK link from Objection back to ObjectionDraft.
2. **30-day abandonment purge**: a BullMQ job deletes drafts where `savedAt < NOW() - 30 days`.

No soft-delete on ObjectionDraft — DECISION-A explicitly excludes it ("transient; no audit obligation on pre-submission drafts").

---

## Model: Objection

```prisma
model Objection {
  id             String            @id @default(cuid())
  userId         String
  municipalityId String
  lineItemId     String
  category       ObjectionCategory
  status         ObjectionStatus   @default(UNDER_REVIEW)
  refNumber      String?           @unique // "ELM-2026-NNNNNN" — assigned by municipality adapter (api orphan audit D-1)
  notes          String?
  submittedAt    DateTime?
  deletedAt      DateTime?         // DECISION-A: soft-delete; legal record — never hard-deleted
  createdAt      DateTime          @default(now())
  updatedAt      DateTime          @updatedAt

  user                  User                   @relation(fields: [userId], references: [id], onDelete: Restrict)
  municipality          Municipality           @relation(fields: [municipalityId], references: [id], onDelete: Restrict)
  lineItem              BillLineItem           @relation(fields: [lineItemId], references: [id], onDelete: Restrict)
  evidenceFiles         EvidenceFile[]
  municipalityResponses MunicipalityResponse[]
  notifications         Notification[]
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| userId | String | No | — | — | — | FK onDelete: Restrict |
| municipalityId | String | No | — | — | — | DECISION-C FK |
| lineItemId | String | No | — | — | — | FK onDelete: Restrict |
| category | ObjectionCategory | No | — | — | — | |
| status | ObjectionStatus | No | — | — | UNDER_REVIEW | |
| refNumber | String | Yes | Yes | — | — | Human-readable case ID; @unique creates index |
| notes | String | Yes | — | — | — | |
| submittedAt | DateTime | Yes | — | — | — | null until submission confirmed by municipality |
| deletedAt | DateTime | Yes | — | — | — | DECISION-A soft-delete marker |
| createdAt | DateTime | No | — | — | now() | |
| updatedAt | DateTime | No | — | — | @updatedAt | |

No `@@index` beyond the `@unique` on `refNumber`. At 2,500 projected rows, full table scan cost is negligible. `refNumber` is the lookup key for the TRACKING screen (`WHERE refNumber = 'ELM-2026-000142'`).

### onDelete: Restrict rationale (all three FKs)

| FK | Why Restrict |
| --- | --- |
| userId → User | Objection is a legal record. User.onDelete: Restrict enforces that a user cannot be hard-deleted while objections exist. Under POPIA erasure, User is soft-deleted and PII anonymised; the Objection row survives with userId intact for FK integrity. |
| municipalityId → Municipality | Municipality records are seeded and never deleted in Phase 1. Restrict is a safety net against accidental seed deletion. |
| lineItemId → BillLineItem | An Objection without a disputed line item is semantically invalid. The FK prevents the line item from being deleted while a formal dispute references it. |

### Soft-delete rationale

Objection is soft-deleted (not hard-deleted) because it is a formal legal submission. Even if a user requests account deletion, the dispute record must be retained for:
1. The municipality's own records (they have a copy; our record must be consistent).
2. POPIA compliance — the right to erasure does not override legal obligation to retain formal dispute records.

When `deletedAt` is set, the objection-service's soft-delete middleware hides the record from client-facing API responses. It remains visible to internal admin endpoints.

---

## Model: EvidenceFile

```prisma
model EvidenceFile {
  id          String    @id @default(cuid())
  objectionId String
  storageKey  String    @unique // Azure Blob Storage key; null blob = file deleted from storage
  filename    String
  mimeType    String
  deletedAt   DateTime? // DECISION-A: metadata row retained after blob deletion
  uploadedAt  DateTime  @default(now())

  objection Objection @relation(fields: [objectionId], references: [id], onDelete: Cascade)
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| objectionId | String | No | — | — | — | FK onDelete: Cascade |
| storageKey | String | No | Yes | — | — | Azure Blob key; @unique prevents duplicate uploads |
| filename | String | No | — | — | — | Original filename shown in UI |
| mimeType | String | No | — | — | — | image/jpeg, application/pdf |
| deletedAt | DateTime | Yes | — | — | — | DECISION-A soft-delete marker |
| uploadedAt | DateTime | No | — | — | now() | |

No `@@index` on `objectionId` — at 7,500 projected rows and an implicit index on `storageKey`, a lookup by `objectionId` scans at most a few rows per objection. Add `@@index([objectionId])` if row count grows beyond 100k.

**`onDelete: Cascade`** — if an Objection is cascade-deleted (dev teardown), all EvidenceFiles cascade-delete. In production, Objection is soft-deleted and EvidenceFiles are soft-deleted separately (the blob may be purged for storage cost, but the metadata row is kept for audit). See DECISION-A.

### Soft-delete semantics for EvidenceFile

When a user or admin request results in evidence file deletion:
1. Delete the blob at `storageKey` from Azure Blob Storage.
2. Set `deletedAt = now()` on the EvidenceFile row — do NOT hard-delete the row.
3. Emit `EVIDENCE_UPLOADED` (or a future `EVIDENCE_DELETED`) AuditEvent.

The metadata row (filename, mimeType, uploadedAt) remains for audit. The `storageKey` still exists in the database but the blob is gone — this is intentional and expected.
