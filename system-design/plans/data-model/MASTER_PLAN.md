# EasyRates Data Model

## Mission

Design the complete Prisma schema for all services that serve the Flutter mobile
app — producing schema blocks, index decisions, and relationship decisions for
every entity, grounded in the row-count estimates in envelope.md and the exact
enums revealed by the Figma process flows. This scope must be complete before the
api-contracts sub-scope begins.

## Objectives

1. Draw the ERD covering all 12 entities: User, OTPAttempt, Property, Account,
   Bill, BillLineItem, Objection, EvidenceFile, ObjectionDraft, Notification,
   MunicipalityResponse, and AIAmountCalculation.
2. Produce a Prisma schema block for every entity with field types, optional (`?`),
   `@unique`, `@index`, and `@@index` decisions justified by envelope.md row-count
   estimates.
3. Lock the four exact DisputeCategory values and four exact Objection status values
   from the Figma flows as Prisma enums — no other values are valid.
4. Make and document four explicit design decisions: soft-delete policy, audit log
   approach, multi-tenancy strategy, PK type (`@default(uuid())` vs auto-increment).
5. Justify every index by naming the specific query it serves — no speculative indexes.
6. Verify the five heaviest queries have no sequential scan on tables projected
   to exceed 10k rows.

## Goals

- G0 `docs/data-model/erd.md` — all 12 entities; relationship diagram; FK directions;
  `onDelete` policies (Cascade / Restrict / SetNull); relationship types
  (one-to-one / one-to-many / many-to-many).
- G1 `docs/data-model/user-auth.md` — User, OTPAttempt; `idNumber` field with POPIA
  cross-reference note; `phoneNumber` index for OTP lookup.
- G2 `docs/data-model/property-account.md` — Property, Account; address fields;
  `accountNumber` and `erfNumber` indexes for search.
- G3 `docs/data-model/bill.md` — Bill, BillLineItem; `DisputeCategory` enum with
  exactly four values from the Figma flow:
  `WRONG_METER_READING | INCORRECT_TARIFF | PROPERTY_NOT_OCCUPIED | DUPLICATE_OTHER`.
- G4 `docs/data-model/objection.md` — Objection with `status` enum exactly four values:
  `UNDER_REVIEW | UPHELD | REJECTED | MORE_INFO_REQUESTED`; `referenceNumber`;
  `aiExpectedAmount` field. EvidenceFile. ObjectionDraft.
- G5 `docs/data-model/notification.md` — Notification with `channel` enum:
  `PUSH | SMS | EMAIL`; MunicipalityResponse model for CRM ingestion payload
  (feeds the Tracking & Resolution flow).
- G6 `docs/data-model/ai-calculation.md` — AIAmountCalculation (AI service result
  per bill, backing the Bill Review "View AI-Generated Expected Amount" screen).
- G7 `docs/data-model/indexes.md` — top-5 heaviest queries identified; EXPLAIN ANALYZE
  or analytical access-pattern justification for each; consolidated index table across
  all Prisma models.
- G8 `docs/data-model/decisions.md` — soft-delete policy per model; audit log approach
  (Prisma middleware / custom audit table / `prisma-audit-trail`); multi-tenancy
  strategy; PK type with rationale; migration strategy; zero-downtime schema-change
  checklist (Prisma `--create-only` migration review flow).
- G9 `docs/data-model.md` — top-level summary linking all sub-documents; the document
  that plan/06 in the parent scope links to.

## Expected Outcome

A complete, query-justified Prisma schema that a TypeScript developer can implement
model by model, index by index, without ambiguity. Every field in every API contract
traces to a Prisma model field defined here. Every `@index` exists because a named
query needs it.

## Definition of Done

1. ✅ ERD covers all 12 entities; every relation has an explicit `onDelete` policy.
2. ✅ Every entity has a complete Prisma schema block; every `@index` / `@@index` has
   a one-line query justification referencing the specific query that needs it.
3. ✅ `DisputeCategory` enum: exactly 4 values matching the Figma flow.
4. ✅ Objection `status` enum: exactly 4 values matching the Figma flow.
5. ✅ ObjectionDraft, AIAmountCalculation, MunicipalityResponse all defined with
   schema blocks.
6. ✅ Four design decisions documented with rationale (soft-delete, audit, multi-tenancy,
   PK type).
7. ✅ Top-5 heaviest queries: no sequential scan on tables projected > 10k rows —
   either EXPLAIN ANALYZE output or analytical access-pattern justification.
8. ✅ Zero-downtime migration checklist: ≥ 4 steps, specific to Prisma's `--create-only`
   review flow and post-launch schema changes.
9. ✅ `data-model.md` written and links to all sub-documents.

## Sub-Scopes

(none)

## Plans

- ✅ [plans/00-erd.md](plans/00-erd.md) — full ERD: 12 entities, FK directions, onDelete policies, service ownership
- ✅ [plans/01-user-auth.md](plans/01-user-auth.md) — User and OTPAttempt schema blocks; idNumber POPIA note
- ✅ [plans/02-property-account.md](plans/02-property-account.md) — Property and Account schema blocks; accountNumber/erfNumber indexes
- ✅ [plans/03-bill.md](plans/03-bill.md) — Bill, BillLineItem, DisputeCategory enum (4 locked values)
- ✅ [plans/04-objection.md](plans/04-objection.md) — Objection, EvidenceFile, ObjectionDraft; ObjectionStatus enum (4 locked values)
- ✅ [plans/05-notification.md](plans/05-notification.md) — Notification (3-channel enum), MunicipalityResponse; state-transition note
- ✅ [plans/06-ai-calculation.md](plans/06-ai-calculation.md) — AIAmountCalculation; billId uniqueness; staleness policy
- ✅ [plans/07-indexes.md](plans/07-indexes.md) — top-5 queries; consolidated index table; sequential-scan risks
- ✅ [plans/08-decisions.md](plans/08-decisions.md) — soft-delete, audit, tenancy, PK type; zero-downtime migration checklist
- ✅ [plans/09-summary.md](plans/09-summary.md) — docs/data-model.md top-level summary linking all 9 sub-documents
