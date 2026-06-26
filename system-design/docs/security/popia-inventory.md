# EasyRates — POPIA Field Inventory

**Status:** Decided  
**Date:** 2026-06-20  
**Source models:** `docs/data-model/user-auth.md`, `property-account.md`, `bill.md`,
`objection.md`, `notification.md`, `ai-calculation.md`, `docs/security/sessions.md`
(RefreshToken)

---

## POPIA classification framework

Under POPIA (Protection of Personal Information Act, 2013):

**Personal information** — any information relating to an identifiable, living natural
person. Includes name, phone number, email address, physical address, account number,
IP address, and any information specific to that person's identity, financial status,
or behaviour.

**Special personal information (POPIA §26/27)** — a stricter category: racial or ethnic
origin, political persuasion, health, sex life, biometric information, criminal record,
and religious or philosophical beliefs. Responsible parties may not process this category
without explicit consent or one of the narrow statutory exceptions. Breach of this
category is the highest-priority notification obligation.

**Responsible party obligation (POPIA §19):** "A responsible party must secure the
integrity and confidentiality of personal information in its possession by taking
appropriate, reasonable technical and organisational measures."

**Breach notification (POPIA §22):** Any breach must be reported to the Information
Regulator "as soon as reasonably possible" — typically within 72 hours.
Maximum penalty: R10 million or 10 years imprisonment (§109).

---

## Classification key

| Symbol | Meaning |
|---|---|
| **SPI** | Special personal information (POPIA §26) — strictest obligations |
| **PII** | Personal information — standard protection obligations |
| **FIN** | Financial data — protected under POPIA + SA financial regulations |
| **OPS** | Operational — internal identifiers, status fields, timestamps |
| **NS** | Non-sensitive — public information or internally scoped |

---

## Highest-risk field: kycDocumentKey

`EvidenceFile.kycDocumentKey` / `User.kycDocumentKey` — Azure Blob Storage key pointing
to an SA ID document copy or proof-of-address document uploaded by the ratepayer during
KYC verification. The document itself typically contains the 13-digit SA ID number.

**Classification: SPI** — the blob contains biometric-adjacent information (SA ID
document), and the 13-digit ID number within it enables:
1. SIM swap — attacker contacts SARS/SASSA or network operator → replaces SIM → receives OTP
2. Bank account takeover — bank's USSD IVR uses ID number as identity confirmation
3. Credit fraud — SA identity number is the root credential for most financial services

This is the highest-priority field in the data model. A breach of this blob store
requires immediate §22 notification to the Information Regulator and affected data
subjects. **Column-level encryption on `kycDocumentKey` + private blob container with
proxy-only access is the mandatory go-live gate.** See `owasp.md` M6.

---

## Field inventory

### Model: User

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | CUID non-sequential (no enumeration) | decisions.md DECISION-D |
| `phone` | String | **PII** | Unique index; rate-limited OTP endpoint; **CLE required (go-live gate)**; not logged in plaintext; 30-day OTPAttempt purge | sessions.md, rate-limits.md |
| `email` | String? | **PII** | Not returned in public responses; **CLE required (go-live gate)** | owasp.md M6 |
| `displayName` | String? | **PII** | Not returned in search results; **CLE required (go-live gate)** | owasp.md M6 |
| `idNumberHash` | String? | **SPI** (pseudonymised SA ID) | ADR-003: HMAC-SHA256(KMS pepper, SA ID); plaintext never stored; never returned in any response; nulled on erasure | ADR-003 |
| `deviceToken` | String? | **PII** (device linkage) | Used only for FCM push dispatch; never returned in profile responses | notification-service |
| `kycStatus` | KycStatus | OPS | Status enum; no PII | — |
| `kycDocumentKey` | String? | **SPI** (access key to SA ID document) | Private Azure Blob container; proxy-only download; AuditEvent `KYC_DOCUMENT_UPLOADED` on every access; blob deleted on POPIA erasure; **CLE required (go-live gate)** | upload-validation.md, owasp.md M6 |
| `deletedAt` | DateTime? | OPS | Erasure marker; JWT middleware checks this, giving 0-second revocation | sessions.md Decision D |
| `createdAt` | DateTime | OPS | — | — |
| `updatedAt` | DateTime | OPS | — | — |

**POPIA erasure procedure:** Set `deletedAt = NOW()`; null `phone`, `email`, `displayName`,
`idNumberHash`, `deviceToken`, `kycDocumentKey`; delete the blob at `kycDocumentKey`;
cascade-delete Account (soft), OTPAttempts, Notifications. User row is NOT hard-deleted
(FK anchor for Objection). JWT middleware returns 401 immediately on `deletedAt` check.

---

### Model: OTPAttempt

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID; no enumeration | — |
| `code` | String | OPS (credential hash) | bcrypt hash — never stored or compared in plaintext; the raw OTP is single-use and discarded | — |
| `purpose` | OtpPurpose | OPS | — | — |
| `attempts` | Int | OPS | — | — |
| `maxAttempts` | Int | OPS | — | — |
| `expiresAt` | DateTime | OPS | — | — |
| `verifiedAt` | DateTime? | OPS | — | — |
| `createdAt` | DateTime | OPS | — | — |

**Retention:** 30-day BullMQ purge job. Rolling ~33,000 active rows at production.
OTPAttempt does not store the phone number directly (joins via userId → User.phone).

---

### Model: AuditEvent

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String? FK | NS | CUID reference; not the user's PII | — |
| `event` | AuditEventType | OPS | — | — |
| `entityId` | String? | NS | CUID; no enumeration | — |
| `entityType` | String? | NS | — | — |
| `metadata` | Json? | **PII** (IP address, userAgent) | IP address and userAgent string are personal information under POPIA. The field may contain both. **Control:** (a) never log `metadata` content to application logs; (b) IP address should be masked/removed from `metadata` after 90 days if retained for analytics. Pending decision: add 90-day IP masking job. | Flagged gap — no current control |
| `createdAt` | DateTime | OPS | — | — |

**Note:** AuditEvent is append-only. Rows are never deleted or soft-deleted.
`metadata.ipAddress` is the only PII field in this model. The IP masking gap is
low-priority for pilot (small user base, no analytics use case) but must be addressed
before production analytics pipeline is built.

---

### Model: RefreshToken (from sessions.md)

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID | — |
| `tokenHash` | String | OPS (security credential) | SHA-256 hash; plaintext token never persisted; `@unique` constraint; revoked on use | sessions.md Decision C |
| `familyId` | String | OPS | Internal chain identifier for reuse detection | sessions.md Decision C |
| `expiresAt` | DateTime | OPS | — | — |
| `revokedAt` | DateTime? | OPS | null = active | — |
| `createdAt` | DateTime | OPS | — | — |

**Note:** RefreshToken model is not yet in `data-model/user-auth.md` (gap flagged in
`sessions.md`). Schema is defined in `sessions.md` under "RefreshToken table."

---

### Model: Municipality

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `name` | String | NS | Public entity — "Emfuleni Local Municipality" | — |
| `code` | String | NS | Public entity — "EMFULENI" | — |

No PII. Municipality is a seed record for a public entity.

---

### Model: Property

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `municipalityId` | String FK | NS | CUID | — |
| `accountNumber` | String | **PII** (account identifier) | SEARCH rate limit 10/min/userId prevents enumeration; `@unique` prevents bulk extraction; **CLE required (go-live gate)** | rate-limits.md Category 4b, owasp.md M6 |
| `address` | String | **PII** (physical address) | Returned only to authenticated account holder; **CLE required (go-live gate)** | owasp.md M6 |
| `erfNumber` | String? | OPS (cadastral number — public record) | Public property register datum; no protection required | — |
| `ownerName` | String? | **PII** (property owner name) | Returned only to authenticated account holder; **CLE required (go-live gate)** | owasp.md M6 |
| `city` | String | NS | Static "Emfuleni" | — |
| `metadata` | Json? | **PII (unknown)** | Untyped JSON from municipality billing system sync. May contain unknown PII sub-fields. **Control:** treat entire column as PII until audited against actual municipality export format. **Go-live gate:** audit before production launch; extract PII sub-fields to typed columns or encrypt the column. | owasp.md M6 open item |

---

### Model: Account

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID | — |
| `municipalityId` | String FK | NS | CUID | — |
| `accountNumber` | String | **PII** (links person to service account) | `@unique` index; returned only to authenticated account holder; **CLE required (go-live gate)** | owasp.md M6 |
| `status` | AccountStatus | OPS | — | — |
| `deletedAt` | DateTime? | OPS | Soft-delete cascades from User.deletedAt | — |
| `createdAt` | DateTime | OPS | — | — |

---

### Model: Bill

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `municipalityId` | String FK | NS | CUID | — |
| `accountNumber` | String | **PII/FIN** (links bill to account and person) | Returned only to authenticated account holder; AuditEvent `BILL_ACCESSED` on every read; **CLE required (go-live gate)** | owasp.md M6 |
| `period` | String | NS | Calendar period — "2025-05" | — |
| `totalAmount` | Decimal | **FIN** | Returned only to authenticated account holder; 5-year SA financial regulation retention; never deleted | bill.md retention policy |
| `dueDate` | DateTime | NS | Not PII | — |
| `status` | BillStatus | OPS | — | — |
| `fetchedAt` | DateTime | OPS | — | — |

**Retention:** Bills are NEVER deleted. SA financial regulations require 5-year minimum
retention. `DECISION-A` explicitly excludes Bill from soft-delete.

---

### Model: BillLineItem

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `billId` | String FK | NS | CUID | — |
| `description` | String | OPS (e.g., "Water consumption Apr 2026") | Generic category label; no person-identifying content | — |
| `amount` | Decimal | **FIN** | Returned only to authenticated account holder; covered by Bill.accountNumber access control | rate-limits.md Category 4 (READ) |
| `category` | LineItemCategory | NS | Enum (WATER, ELECTRICITY, etc.) | — |
| `anomalyFlag` | Boolean | OPS | — | — |
| `historicalAverage` | Decimal? | **FIN** | Historical consumption comparison; returned only to authenticated account holder; shown on BILL REVIEW screen | — |

---

### Model: ObjectionDraft

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID | — |
| `lineItemId` | String? FK | NS | CUID | — |
| `category` | ObjectionCategory | OPS | — | — |
| `notes` | String? | **PII** (free-text; may contain personal details, complaint narrative) | Returned only to authenticated user; hard-deleted after 30 days or on submission; never retained after Objection creation | objection.md lifecycle |
| `savedAt` | DateTime | OPS | — | — |

**Retention:** ObjectionDraft is hard-deleted on submission or after 30-day inactivity.
No legal obligation to retain pre-submission drafts (DECISION-A).

---

### Model: Objection

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID | — |
| `municipalityId` | String FK | NS | CUID | — |
| `lineItemId` | String FK | NS | CUID | — |
| `category` | ObjectionCategory | OPS | — | — |
| `status` | ObjectionStatus | OPS | — | — |
| `refNumber` | String? | OPS (case reference; not person-identifying alone) | Format "OBJ-YYYYMM-NNNNNN" — sequential but not linkable to a person without account context | — |
| `notes` | String? | **PII** (free-text complaint; may name people, reference account history) | Returned only to authenticated account holder; soft-deleted on POPIA erasure (retained for legal obligation — POPIA erasure vs legal obligation tension acknowledged) | objection.md soft-delete rationale |
| `submittedAt` | DateTime? | OPS | — | — |
| `deletedAt` | DateTime? | OPS | Legal record soft-delete marker | — |
| `createdAt` | DateTime | OPS | — | — |
| `updatedAt` | DateTime | OPS | — | — |

**Retention:** Soft-deleted, never hard-deleted. Objection is a formal legal submission.
POPIA right to erasure does not override legal obligation to retain formal dispute records.

---

### Model: EvidenceFile

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `objectionId` | String FK | NS | CUID | — |
| `storageKey` | String | **SPI** (access key to evidence document — may be SA ID copy, utility bill, or other identity document) | Private Azure Blob container; proxy-only download via objection-service; `@unique` prevents duplicate uploads; AuditEvent `EVIDENCE_UPLOADED` on every upload; blob deleted on erasure request | upload-validation.md, owasp.md M6 |
| `filename` | String | **PII** (may contain user's name, e.g., "molefe-id-jan2026.jpg") | Display-only; not used in blob storage path (CUID key used instead); **CLE required (go-live gate)** | owasp.md M6 |
| `mimeType` | String | NS | Validated magic bytes; not PII | upload-validation.md |
| `deletedAt` | DateTime? | OPS | Soft-delete marker; blob is purged; metadata row retained for audit | objection.md soft-delete semantics |
| `uploadedAt` | DateTime | OPS | — | — |

---

### Model: Notification

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `userId` | String FK | NS | CUID | — |
| `objectionId` | String? FK | NS | CUID | — |
| `type` | NotificationType | OPS | — | — |
| `channel` | NotificationChannel | OPS | — | — |
| `status` | NotificationStatus | OPS | — | — |
| `sentAt` | DateTime | OPS | — | — |

No PII in the Notification model. The notification message content (SMS body, push text)
is not stored in the database — it is generated at dispatch time and sent directly to the
channel provider.

**Retention:** Hard-deleted after 90 days. No soft-delete. No legal obligation.

---

### Model: MunicipalityResponse

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `objectionId` | String FK | NS | CUID | — |
| `status` | ObjectionStatus | OPS | — | — |
| `note` | String? | OPS (municipality's written reason; authored by municipality, not the ratepayer) | Returned only to authenticated account holder; soft-deleted with parent objection | — |
| `adjustedAmount` | Decimal? | **FIN** (proposed financial settlement) | Returned only to authenticated account holder; retained as part of legal record | — |
| `deletedAt` | DateTime? | OPS | Legal record soft-delete marker | — |
| `respondedAt` | DateTime | OPS | — | — |

---

### Model: AIAmountCalculation

| Field | Type | Classification | Protection control | Reference |
|---|---|---|---|---|
| `id` | String CUID | NS | — | — |
| `billId` | String FK | NS | CUID | — |
| `estimatedAmount` | Decimal | **FIN** (AI estimate of correct bill total) | Returned only to authenticated account holder; rate-limited at 5/min/userId (AI-ESTIMATE category) | rate-limits.md AI-ESTIMATE sub-limit |
| `confidence` | Float | NS | Model confidence score; not PII | — |
| `reasoning` | String? | **PII-adjacent** (AI-generated explanation derived from user's account history; e.g., "Your meter reading appears incorrect based on 6-month average consumption") | Returned only to authenticated account holder; contains account-specific inferences | — |
| `modelVersion` | String? | NS | Internal ML model versioning | — |
| `calculatedAt` | DateTime | NS | — | — |

---

## Control gap summary

| Gap | Models affected | Severity | Gate |
|---|---|---|---|
| Column-level encryption (CLE) not implemented | User.phone, email, displayName, kycDocumentKey; Property.address, ownerName, accountNumber; Account.accountNumber; Bill.accountNumber; EvidenceFile.filename | **Critical** | Go-live gate — must be implemented before production |
| Property.metadata unaudited for PII | Property | **High** | Go-live gate — audit against municipality export format before production |
| AuditEvent.metadata IP masking | AuditEvent | **Low** | Pilot accepted; required before analytics pipeline |
| RefreshToken model missing from data-model/user-auth.md | RefreshToken | Medium | Before plan/03 implementation |
| ObjectionDraft.notes and Objection.notes POPIA erasure behaviour | ObjectionDraft, Objection | Medium | Objection.notes must be nulled on erasure (POPIA erasure vs legal obligation — notes field, not the record, can be erased) |

---

## Fields by classification summary

**Special Personal Information (3 fields):**
- `User.idNumberHash` — keyed HMAC of the SA ID (pseudonymised; plaintext never stored; pepper in KMS) — ADR-003
- `User.kycDocumentKey` — Azure Blob key to SA ID document
- `EvidenceFile.storageKey` — Azure Blob key to evidence document (may be SA ID copy)

**PII (13 fields):**
- `User.phone`, `User.email`, `User.displayName`, `User.deviceToken`
- `Property.address`, `Property.ownerName`, `Property.accountNumber`, `Property.metadata` (until audited)
- `Account.accountNumber`
- `Bill.accountNumber`
- `EvidenceFile.filename`
- `ObjectionDraft.notes`, `Objection.notes`

**Financial (7 fields):**
- `Bill.totalAmount`
- `BillLineItem.amount`, `BillLineItem.historicalAverage`
- `MunicipalityResponse.adjustedAmount`
- `AIAmountCalculation.estimatedAmount`
- `AuditEvent.metadata` (IP address — PII, not Financial, but listed here for control overlap)
- `AIAmountCalculation.reasoning` (PII-adjacent — derived from Financial data)

**All remaining fields:** Operational or Non-sensitive (no named control required beyond standard access authentication).
