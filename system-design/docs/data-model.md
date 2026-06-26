# EasyRates — Data Model

**Status:** Complete  
**Date:** 2026-06-20  
**Downstream:** [backend/plans/02-database.md](../../backend/plans/02-database.md) — copy Prisma schema blocks verbatim from sub-documents below  
**Produced by:** System Design session (ERD · FIELDS · DECISIONS · MIGRATIONS tasks)

This document is the entry point for the EasyRates data layer. It links to the nine sub-documents that together define the complete Prisma schema, index strategy, design decisions, and migration approach. A TypeScript developer can implement model-by-model starting from these documents without ambiguity.

---

## Sub-documents

| Document | Contents |
| --- | --- |
| [erd.md](data-model/erd.md) | ASCII ERD: all 14 models, FK directions, onDelete policies, service ownership |
| [user-auth.md](data-model/user-auth.md) | User, OTPAttempt, AuditEvent; KycStatus, OtpPurpose, AuditEventType enums; POPIA notes |
| [property-account.md](data-model/property-account.md) | Property, Account, Municipality; AccountStatus enum; soft-reference rationale |
| [bill.md](data-model/bill.md) | Bill, BillLineItem; BillStatus, LineItemCategory, DisputeCategory enums; retention policy |
| [objection.md](data-model/objection.md) | ObjectionDraft, Objection, EvidenceFile; ObjectionCategory, ObjectionStatus enums; soft-delete rationale |
| [notification.md](data-model/notification.md) | Notification, MunicipalityResponse; NotificationChannel, NotificationType, NotificationStatus enums; write sequence |
| [ai-calculation.md](data-model/ai-calculation.md) | AIAmountCalculation; billId uniqueness; staleness policy |
| [indexes.md](data-model/indexes.md) | Top-5 queries by frequency × row-scan; consolidated index table; sequential scan risks |
| [decisions.md](data-model/decisions.md) | DECISION-A (soft-delete) · B (audit log) · C (multi-tenancy) · D (PK type); schema patches |
| [migrations.md](data-model/migrations.md) | Migration strategy; zero-downtime checklist (4 steps); expand-contract pattern; Azure SQL lock escalation |

---

## Definition of done — verification

| # | Criterion | Status |
| --- | --- | --- |
| 1 | ERD covers all 14 models; every relation has an explicit onDelete policy | ✓ erd.md |
| 2 | Every model has a complete Prisma schema block and field table | ✓ six model docs |
| 3 | DisputeCategory enum: exactly 4 values matching the Figma EVIDENCE & CHALLENGE flow | ✓ bill.md |
| 4 | ObjectionStatus enum: exactly 4 values matching the Figma TRACKING & RESOLUTION flow | ✓ objection.md |
| 5 | ObjectionDraft, AIAmountCalculation, MunicipalityResponse all defined with schema blocks | ✓ objection.md, ai-calculation.md, notification.md |
| 6 | Four design decisions documented with rationale | ✓ decisions.md |
| 7 | Top-5 heaviest queries: no sequential scan on tables > 10k rows | ✓ indexes.md |
| 8 | Zero-downtime migration checklist: ≥4 steps, Prisma-specific, Azure SQL lock-escalation-aware | ✓ migrations.md |
| 9 | data-model.md written and links to all sub-documents | ✓ this file |

---

## Quick reference: models at a glance

| Model | Service | PKs/UKs | Rows (12mo) | Soft-delete? |
| --- | --- | --- | --- | --- |
| Municipality | shared/seed | id, name, code | 1 | No — seed data |
| User | auth | id, phone, email? | 25,000 | Yes — POPIA erasure |
| OTPAttempt | otp | id | 33,000 active | No — 30d TTL purge |
| AuditEvent | auth (all write) | id | 300,000+/year | No — append-only |
| Property | property | id, accountNumber | 30,000 | No — hard delete on resync |
| Account | account | id, accountNumber | 90,000 | Yes — follows User lifecycle |
| Bill | bill | id | 1,080,000 | No — 5-year retention |
| BillLineItem | bill | id | 5,400,000 | No — retained with Bill |
| AIAmountCalculation | bill | id, billId | ≤1,080,000 | No — cascade from Bill |
| ObjectionDraft | objection | id | < 1,000 | No — 30d purge on abandon |
| Objection | objection | id, refNumber? | 2,500 | Yes — legal record |
| EvidenceFile | objection | id, storageKey | 7,500 | Yes — metadata retained after blob deletion |
| MunicipalityResponse | status | id | < 2,500 | Yes — legal record |
| Notification | notification | id | 225,000 active | No — 90d retention |

---

## Quick reference: all enums

| Enum | Values | Locked? | Source |
| --- | --- | --- | --- |
| KycStatus | PENDING · SUBMITTED · VERIFIED · REJECTED | No | auth-service |
| OtpPurpose | LOGIN · REGISTRATION | No | otp-service |
| AuditEventType | 12 values — see user-auth.md | POPIA minimum 9 required | decisions.md |
| AccountStatus | ACTIVE · INACTIVE · ARCHIVED | No | account-service |
| BillStatus | CURRENT · OVERDUE · PAID · DISPUTED | No | bill-service |
| LineItemCategory | WATER · ELECTRICITY · PROPERTY_RATES · SANITATION · REFUSE · ARREARS · LEVY · VAT · OTHER | No | bill-service |
| DisputeCategory | WRONG_METER_READING · INCORRECT_TARIFF · PROPERTY_NOT_OCCUPIED · DUPLICATE_OTHER | **Yes — 4 Figma values** | bill.md |
| ObjectionCategory | WRONG_METER_READING · INCORRECT_TARIFF · PROPERTY_NOT_OCCUPIED · DUPLICATE_OTHER | **Yes — 4 Figma values** | objection.md |
| ObjectionStatus | UNDER_REVIEW · MORE_INFO_REQUESTED · UPHELD · REJECTED | **Yes — 4 Figma values** | objection.md |
| NotificationChannel | PUSH · SMS · EMAIL | **Yes — 3 Figma values** | notification.md |
| NotificationType | BILL_ISSUED · PAYMENT_DUE · OBJECTION_STATUS · OBJECTION_RECEIVED · MORE_INFO_REQUESTED | No | notification.md |
| NotificationStatus | SENT · DELIVERED · FAILED · PENDING | No | notification.md |

Locked enums may not be extended without a formal design decision recorded in an ADR.

---

## Quick reference: all indexes

| Model | Index | Serves |
| --- | --- | --- |
| User | `@unique phone` | Login lookup |
| User | `@unique email?` | Optional login |
| OTPAttempt | `@@index([userId, expiresAt])` | OTP verification |
| AuditEvent | `@@index([userId, createdAt])` | Per-user audit history |
| AuditEvent | `@@index([entityId, entityType])` | Per-record audit trail |
| Property | `@unique accountNumber` | Account number authority |
| Property | `@@index([erfNumber])` | Property search by ERF |
| Account | `@unique accountNumber` | Account lookup |
| Account | `@@index([userId])` | GET /account/me — added by VERIFY |
| Bill | `@@index([accountNumber, period])` | Balance check + bill history list |
| BillLineItem | `@@index([billId])` | Usage breakdown — critical |
| AIAmountCalculation | `@unique billId` | AI estimate lookup |
| Objection | `@unique refNumber?` | Tracking screen lookup |
| EvidenceFile | `@unique storageKey` | Duplicate upload prevention |
| Notification | `@@index([userId, sentAt])` | Notification inbox |
| Municipality | `@unique name`, `@unique code` | Seed lookups |

---

## Schema patches summary (applied in all sub-documents)

These patches were determined by DECISIONS session and applied to all schema blocks in the sub-documents above:

1. **DECISION-A** — `deletedAt DateTime?` added to: User, Account, Objection, EvidenceFile, MunicipalityResponse
2. **DECISION-B** — `AuditEvent` model added (14th model, not in original 12)
3. **DECISION-C** — `Municipality` model added (13th model); `municipalityId String` FK added to Property, Account, Bill, Objection
4. **DECISION-D** — `@id @default(cuid())` on all models (overrides plan/01's `@default(uuid())`)

---

## Downstream links

| Plan | What it takes from here |
| --- | --- |
| [backend/plans/02-database.md](../../backend/plans/02-database.md) | Copy Prisma schema blocks verbatim; implement `schema.prisma` |
| [system-design/plans/07-security.md](../plans/07-security.md) | AuditEvent model + AuditEventType enum from decisions.md |
| [system-design/plans/08-container-topology.md](../plans/08-container-topology.md) | Single-database architecture (ADR-001); no per-municipality DBs in Phase 1 |
| [system-design/plans/09-api-contracts.md](../plans/09-api-contracts.md) | All id fields typed as `string` (CUID); no integer IDs in any contract |
