# EasyRates — Entity Relationship Diagram

**Source of truth for:** FK directions · onDelete policies · service ownership  
**Patches applied:** DECISION-A (soft-delete) · DECISION-C (municipalityId) · DECISION-D (cuid PKs)  
**Total models:** 14 (12 original + Municipality + AuditEvent added by DECISIONS session)

---

## ERD

```
Notation:  → FK direction (child holds the FK column)
           [C] CASCADE   [R] RESTRICT   [N] SET NULL
           ?  = nullable FK   ~  = soft reference (no DB FK)

━━━ IDENTITY ────────────────────────────────────────────────────────

 ┌──────────────────────────────┐        ┌──────────────────────────────┐
 │  User                [auth]  │  1   N │  OTPAttempt          [otp]  │
 │──────────────────────────────│────────│──────────────────────────────│
 │ PK  id                       │        │ PK  id                       │
 │ UK  phone                    │        │ FK  userId → User.id    [C]  │
 │ UK  email?                   │        │     code  (bcrypt hash)      │
 │     displayName?             │        │     purpose                  │
 │                              │        │     attempts                 │
 │     deviceToken?             │        │     maxAttempts              │
 │     kycStatus                │        │     expiresAt                │
 │     kycDocumentKey?          │        │     verifiedAt?              │
 │     deletedAt?         [A]   │        │     createdAt                │
 │     createdAt                │        └──────────────────────────────┘
 │     updatedAt                │         @@index([userId, expiresAt])
 └──────────────┬───────────────┘
                │
       ┌────────┴────────────────────────────────────────────┐
       │ 1:N [C]   │ 1:N [C]   │ 1:N [C]   │ 1:N [R]       │
       ▼           ▼           ▼           ▼               ▼
  Account    ObjDraft  Notification  Objection    OTPAttempt
  (below)    (below)   (below)      (below)      (above)

━━━ MUNICIPALITY ────────────────────────────────────────────────────

 ┌────────────────────────────────────────────────────────────────┐
 │  Municipality                                   [shared]       │
 │────────────────────────────────────────────────────────────────│
 │ PK  id                                                         │
 │ UK  name                                                       │
 │ UK  code   ("EMFULENI")                                        │
 └────────────────────────────────────────────────────────────────┘
 Seed: { name: "Emfuleni Local Municipality", code: "EMFULENI" }
 FK children: Property · Account · Bill · Objection — all [R]

━━━ PROPERTY & ACCOUNT ─────────────────────────────────────────────

 ┌──────────────────────────────────┐   ┌──────────────────────────────┐
 │  Property           [property]   │   │  Account         [account]   │
 │──────────────────────────────────│   │──────────────────────────────│
 │ PK  id                           │   │ PK  id                       │
 │ UK  accountNumber                │   │ FK  userId → User.id    [C]  │
 │ FK  municipalityId          [R]  │   │ FK  municipalityId      [R]  │
 │ IX  erfNumber?                   │   │ UK  accountNumber            │
 │     address                      │   │     status                   │
 │     ownerName?                   │   │     deletedAt?         [A]   │
 │     city                         │   │     createdAt                │
 │     metadata?                    │   └──────────────────────────────┘
 └──────────────────────────────────┘    @@index([userId])
 ⚠ No FK children. Account.accountNumber and Bill.accountNumber
   are soft (~) references — municipality sync would break a hard FK.

━━━ BILL ────────────────────────────────────────────────────────────

 ┌─────────────────────────────────┐
 │  Bill                  [bill]   │
 │─────────────────────────────────│
 │ PK  id                          │
 │ FK  municipalityId         [R]  │
 │ IX  accountNumber  (soft ~)     │  matches Account.accountNumber
 │     period   ("2025-05")        │
 │     totalAmount                 │
 │     dueDate                     │
 │     status                      │
 │     fetchedAt                   │
 └──────────────┬──────────────────┘
  @@index([accountNumber, period])
                │ 1:N [C]
                ▼
 ┌────────────────────────────────────┐     ┌──────────────────────────────┐
 │  BillLineItem            [bill]    │ 1:1 │  AIAmountCalculation [bill]  │
 │────────────────────────────────────│─────│──────────────────────────────│
 │ PK  id                             │     │ PK  id                       │
 │ FK  billId → Bill.id          [C]  │     │ UK  billId → Bill.id    [C]  │
 │     description                    │     │     estimatedAmount          │
 │     amount                         │     │     confidence               │
 │     category                       │     │     reasoning?               │
 │     anomalyFlag                    │     │     modelVersion?            │
 │     historicalAverage?             │     │     calculatedAt             │
 └────────────────────────────────────┘     └──────────────────────────────┘
 @@index([billId])

━━━ OBJECTION ───────────────────────────────────────────────────────

 ┌──────────────────────────────────────────────────────────────────┐
 │  ObjectionDraft                                       [obj]      │
 │──────────────────────────────────────────────────────────────────│
 │ PK  id                                                           │
 │ FK  userId → User.id                                       [C]  │
 │ FK? lineItemId → BillLineItem.id                           [N]  │
 │     category                                                     │
 │     notes?                                                       │
 │     savedAt                                                      │
 └──────────────────────────────────────────────────────────────────┘
 On submit → Objection created, ObjectionDraft deleted. No FK link after submit.

 ┌──────────────────────────────────────────────────────────────────┐
 │  Objection                                            [obj]      │
 │──────────────────────────────────────────────────────────────────│
 │ PK  id                                                           │
 │ FK  userId → User.id                                       [R]  │
 │ FK  municipalityId → Municipality.id                       [R]  │
 │ FK  lineItemId → BillLineItem.id                           [R]  │
 │     category                                                     │
 │     status  UNDER_REVIEW|MORE_INFO_REQUESTED|UPHELD|REJECTED    │
 │ UK  refNumber?                                                   │
 │     notes?                                                       │
 │     submittedAt?                                                 │
 │     deletedAt?                                             [A]  │
 │     createdAt / updatedAt                                        │
 └──────────────────┬───────────────────────────────────────────────┘
                    │
          ┌─────────┴──────────────────────────┐
          │ 1:N [C]                            │ 1:N [R]
          ▼                                     ▼
 ┌────────────────────────┐   ┌──────────────────────────────────────┐
 │  EvidenceFile  [obj]   │   │  MunicipalityResponse    [status]   │
 │────────────────────────│   │──────────────────────────────────────│
 │ PK  id                 │   │ PK  id                               │
 │ FK  objectionId   [C]  │   │ FK  objectionId → Objection.id [R]  │
 │ UK  storageKey         │   │     status (ObjectionStatus)         │
 │     filename           │   │     note?                           │
 │     mimeType           │   │     adjustedAmount?                 │
 │     deletedAt?   [A]   │   │     deletedAt?               [A]   │
 │     uploadedAt         │   │     respondedAt                     │
 └────────────────────────┘   └──────────────────────────────────────┘

━━━ NOTIFICATION ────────────────────────────────────────────────────

 ┌──────────────────────────────────────────────────────────────────┐
 │  Notification                                       [notif]      │
 │──────────────────────────────────────────────────────────────────│
 │ PK  id                                                           │
 │ FK  userId → User.id                                       [C]  │
 │ FK? objectionId → Objection.id                             [N]  │
 │     type / channel / status                                      │
 │     sentAt                                                       │
 └──────────────────────────────────────────────────────────────────┘
 @@index([userId, sentAt])

━━━ AUDIT ───────────────────────────────────────────────────────────

 ┌──────────────────────────────────────────────────────────────────┐
 │  AuditEvent                                          [auth]      │
 │──────────────────────────────────────────────────────────────────│
 │ PK  id                                                           │
 │     userId?  (SetNull on User delete — log survives)            │
 │     event  (AuditEventType enum)                                 │
 │     entityId? / entityType?                                      │
 │     metadata?  (IP, userAgent, old/new status)                  │
 │     createdAt                                                    │
 └──────────────────────────────────────────────────────────────────┘
 @@index([userId, createdAt])
 @@index([entityId, entityType])
 Append-only. Never soft-deleted. userId is NOT a Prisma relation
 (SetNull is handled manually on User anonymisation to avoid FK cycles).
```

---

## Relationship Summary

| Child | FK field | Parent | onDelete | Optional? |
| --- | --- | --- | --- | --- |
| OTPAttempt | userId | User | CASCADE | required |
| Account | userId | User | CASCADE | required |
| Account | municipalityId | Municipality | RESTRICT | required |
| ObjectionDraft | userId | User | CASCADE | required |
| ObjectionDraft | lineItemId | BillLineItem | SET NULL | optional |
| Objection | userId | User | RESTRICT | required |
| Objection | municipalityId | Municipality | RESTRICT | required |
| Objection | lineItemId | BillLineItem | RESTRICT | required |
| Notification | userId | User | CASCADE | required |
| Notification | objectionId | Objection | SET NULL | optional |
| Property | municipalityId | Municipality | RESTRICT | required |
| Bill | municipalityId | Municipality | RESTRICT | required |
| BillLineItem | billId | Bill | CASCADE | required |
| AIAmountCalculation | billId | Bill | CASCADE | required |
| EvidenceFile | objectionId | Objection | CASCADE | required |
| MunicipalityResponse | objectionId | Objection | RESTRICT | required |

Soft references (no DB FK):
- `Account.accountNumber` ≈ `Property.accountNumber`
- `Bill.accountNumber` ≈ `Property.accountNumber` / `Account.accountNumber`

---

## Service Ownership

| Model | Service | Rows (12-month production) |
| --- | --- | --- |
| User | auth-service | 25,000 |
| OTPAttempt | otp-service | 33,000 active (30-day TTL purge) |
| AuditEvent | auth-service (written by all) | 300,000+/year |
| Municipality | shared / seed | 1 (Phase 1) |
| Property | property-service | 30,000 |
| Account | account-service | 90,000 |
| Bill | bill-service | 1,080,000 |
| BillLineItem | bill-service | 5,400,000 |
| AIAmountCalculation | bill-service | up to 1,080,000 |
| ObjectionDraft | objection-service | < 1,000 (transient) |
| Objection | objection-service | 2,500 |
| EvidenceFile | objection-service | 7,500 |
| Notification | notification-service | 225,000 active (90-day retention) |
| MunicipalityResponse | status-service | < 2,500 |

**[A]** = soft-delete field added by DECISION-A  
**municipalityId** = FK added to Property, Account, Bill, Objection by DECISION-C
