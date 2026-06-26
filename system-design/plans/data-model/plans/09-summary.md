# 📄 Data Model Summary Document

## Background

⛔ BLOCKED[Gate] — requires plans/00-08 complete (all entity schema blocks,
index strategy, and design decisions must exist before the summary can link and
distil them).

The summary document is the artifact that plan/06-data-model.md in the parent
scope links to. It does not replace the 9 sub-documents; it provides a single
navigation entry point and captures the 5 most important facts about the schema
that a new developer must know before writing any Prisma query.

## Description

Write the top-level `docs/data-model.md` that links all 9 data-model sub-documents,
summarises the key schema decision in each, and provides the definitive entity
count and Prisma enum list. This document is an input to ADR-001.

## Purpose

To produce a single document that answers: "is the EasyRates data model design
complete — and what are the five most important schema facts that a new backend
developer must know before writing a Prisma query?"

## Goal

`easy_rates/system-design/docs/data-model.md` — navigation entry point for the
complete data model design; one section per sub-document; entity count; enum list;
five-point orientation for new developers.

## Tasks

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model.md`:

  Structure:
  # EasyRates Data Model

  ## Schema summary
  One paragraph: Prisma ORM on Azure SQL. 12 entities. 2 locked enums:
  DisputeCategory (4 values) and ObjectionStatus (4 values). UUID PKs (or chosen PK
  type). Soft-delete on [list]. Audit log via [chosen strategy]. State the overall
  schema size in one sentence (12 models, N indexes, M enums).

  ## Entities
  Table: Entity | Service module | Primary key type | Soft-delete | Key index

  ## Locked enums
  DisputeCategory: WRONG_METER_READING | INCORRECT_TARIFF | PROPERTY_NOT_OCCUPIED |
  DUPLICATE_OTHER
  ObjectionStatus: UNDER_REVIEW | UPHELD | REJECTED | MORE_INFO_REQUESTED
  NotificationChannel: PUSH | SMS | EMAIL

  ## Sub-documents
  - [ERD](docs/data-model/erd.md) — [one-line key finding: most FK-connected entity
    and its onDelete policy]
  - [User & OTP](docs/data-model/user-auth.md) — [one-line key decision: idNumber
    POPIA control + OTP code storage]
  - [Property & Account](docs/data-model/property-account.md) — [one-line key
    decision: FK direction; accountNumber index]
  - [Bill & Line Items](docs/data-model/bill.md) — [one-line key decision: composite
    index on accountId + billingPeriodStart; DisputeCategory enum]
  - [Objection, Evidence & Draft](docs/data-model/objection.md) — [one-line key
    decision: soft-delete policy; ObjectionStatus enum]
  - [Notification & Municipality Response](docs/data-model/notification.md) —
    [one-line key decision: 3-channel enum; rawPayload POPIA note]
  - [AI Calculation](docs/data-model/ai-calculation.md) — [one-line key decision:
    uniqueness policy; staleness indicator]
  - [Index Strategy](docs/data-model/indexes.md) — [one-line key finding: top
    query and its index]
  - [Design Decisions](docs/data-model/decisions.md) — [one-line key decision:
    PK type; audit strategy; tenancy decision]

  ## Five things a new developer must know
  1. [Most important schema fact — e.g. "UUID PKs are exposed in URLs; referenceNumber
     on Objection is the human-readable identifier, not the PK"]
  2. [Second most important — e.g. "Soft-delete on Objection and EvidenceFile — always
     filter with `where: { deletedAt: null }` or records appear deleted"]
  3. [Third — e.g. "DisputeCategory and ObjectionStatus enums are locked — do not add
     values without a formal design decision"]
  4. [Fourth — e.g. "idNumber on User is special personal information under POPIA —
     do not return in any API response without explicit justification"]
  5. [Fifth — e.g. "AIAmountCalculation.isStale is the staleness indicator — if true,
     the expected amount should be recalculated before displaying to the user"]

  Done when: all 9 sub-documents linked with one-line key findings; schema summary
  paragraph written; entity table with 12 rows; enum list present; five-point
  orientation section is specific and actionable.

- [x] ✅ VERIFY Confirm: entity table has exactly 12 rows. Confirm: locked enums
  section lists all 3 enums with their exact values. Confirm: all 9 sub-document
  links resolve to existing files.
  Confirm: five-point section contains actionable facts (not topic headings).
  Done when: 12 entities, 3 enums, 9 links confirmed; five-point section reviewed.

## Recommended skill

— custom; no skill fits (assembly and synthesis, not research or analysis).

## Engagement Instructions

Pass condition: entity table has exactly 12 rows with all columns filled.
Pass condition: 3 locked enums documented with exact values.
Pass condition: all 9 sub-document links resolve to existing files.
Pass condition: schema summary paragraph states the schema size (12 models, N indexes,
M enums) in one sentence.
Pass condition: five-point orientation section contains specific, actionable facts
that a developer would act on — not topic headings.
Pass condition: no new schema decisions are introduced in this summary document.
