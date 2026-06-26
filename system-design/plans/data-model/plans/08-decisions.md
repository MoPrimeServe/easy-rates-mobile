# 🎯 Design Decisions & Migration Strategy

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (entity list known — decisions
apply to specific models, which must exist before the policy can name them).

Individual entity plans (01-06) include local decisions on soft-delete and audit.
This plan consolidates and formalises them into four durable design decisions, plus
a zero-downtime migration checklist. These decisions are the input to ADR-001.

## Description

Make and document four schema-level design decisions: soft-delete policy per model,
audit log strategy, multi-tenancy approach, and primary key type. Write the
zero-downtime migration checklist using Prisma's `--create-only` review flow.

## Purpose

To answer: "which design decision — soft-delete, audit log, multi-tenancy, or PK
type — will be most expensive to change after the first 10,000 rows are in
production?"

## Goal

`easy_rates/system-design/docs/data-model/decisions.md` — all four decisions
documented with rationale; zero-downtime migration checklist with ≥ 4 steps; no
"TBD" remaining.

## Tasks

- [x] ✅ THINK `/socratic "Which of the four schema design decisions — soft-delete
  policy, audit log strategy, multi-tenancy, or primary key type — would be most
  expensive to reverse after 10,000 rows are in production? If you choose UUID PKs
  and later want to switch to integer auto-increment, what does that migration look
  like across all 12 tables? If you skip the audit log now and need to add it after
  go-live, what data will you have lost?"`
  Done when: the costliest-to-reverse decision is identified; the migration cost is
  described for that decision; the data loss scenario for audit log deferral is stated.

- [x] ✅ DECIDE-SOFT-DELETE Soft-delete policy per model:
  For each of the 12 models, state: Yes (use `deletedAt` timestamp) / No (hard
  delete) / N/A (records are never deleted).
  At minimum, Objection and EvidenceFile almost certainly need soft-delete for
  POPIA audit trail reasons. Other models:
  - User: soft-delete (POPIA right to be forgotten vs audit obligation — which wins?)
  - OTPAttempt: hard delete after TTL (transient records; no audit need)
  - Property, Account: soft-delete vs cascade from User?
  - Bill, BillLineItem: never deleted (financial record retention)
  - Notification, MunicipalityResponse: hard delete or soft-delete?
  - AIAmountCalculation, ObjectionDraft: hard delete (transient/derived)
  For every Yes: add `deletedAt DateTime?` to the schema block (in the entity plan)
  and document the Prisma query filter pattern (`where: { deletedAt: null }`).
  Done when: all 12 models have a stated policy; every soft-delete model has the
  filter pattern documented.

- [x] ✅ DECIDE-AUDIT Audit log strategy:
  Option A: Prisma middleware — `$use` hook that captures every `create`, `update`,
  `delete` and writes to an `AuditLog` model. Full control; no extra package.
  Option B: `prisma-audit-trail` package — wraps Prisma client and logs operations.
  Option C: Database-level triggers — writes to an audit table in PostgreSQL/Azure SQL.
  Option D: Application-level manual logging — explicit audit writes in service code.
  Choose one. Justify against: implementation complexity, query overhead, ability to
  capture "who made this change" (userId from request context).
  State which models require audit logging (at minimum: Objection status changes;
  every access to User.idNumber under POPIA).
  Done when: strategy chosen; models requiring audit stated; "who" capture mechanism
  described.

- [x] ✅ DECIDE-TENANCY Multi-tenancy:
  EasyRates is initially deployed for Emfuleni Local Municipality only. But the
  business model may expand to other municipalities.
  Option A: No multi-tenancy now — single municipality, no tenant isolation.
    Risk: Adding it later requires adding `municipalityId` FK to every entity — very
    expensive.
  Option B: Add `municipalityId` to anchor entities now (Property, Account) — tenant
    isolation at the data layer; row-level filtering in every query.
  Option C: Multi-schema tenancy — one PostgreSQL schema per municipality.
  State the decision. Justify.
  Done when: decision documented; if Option A chosen, the trigger for revisiting is
  stated (e.g. "first multi-municipality contract signed").

- [x] ✅ DECIDE-PK Primary key type:
  Option A: UUID (String @default(uuid())) — globally unique; safe to expose in
    URLs; no sequential prediction possible; slightly larger storage and index.
  Option B: CUID (String @default(cuid())) — Prisma default; shorter; URL-safe;
    roughly time-ordered.
  Option C: Auto-increment Int — simple; expose to client reveals record count;
    sequential IDs are predictable in URLs (security risk for objection IDs).
  Choose one. Apply consistently to all 12 models. Justify.
  For security: objection referenceNumber is a separate human-readable field (not
  the PK) — the PK is not returned to the Flutter client directly.
  Done when: PK type chosen; all 12 models will use this type; justification written.

- [x] ✅ MIGRATION Write the zero-downtime migration checklist:
  Step 1: Author migration with `prisma migrate dev --create-only` — generates SQL
    without applying it; review the SQL diff manually.
  Step 2: Test the migration against a copy of production data (Azure SQL dev
    instance or a local snapshot).
  Step 3: Apply with `prisma migrate deploy` (not `dev`) in production — applies
    pending migrations without re-generating.
  Step 4: Verify: run `prisma migrate status` to confirm all migrations are applied;
    run smoke tests against the production-equivalent environment.
  Add at least one zero-downtime pattern for each of: adding a nullable column (safe),
  adding a non-null column with a default (safe), dropping a column (unsafe — requires
  two-phase deploy), renaming a column (unsafe — requires two-phase deploy).
  Done when: checklist has ≥ 4 steps; safe vs unsafe operation patterns are documented.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/decisions.md`:
  One section per decision (soft-delete, audit, tenancy, PK type); migration
  checklist section.
  Done when: file exists; all four decisions documented; no "TBD."

- [x] ✅ VERIFY Confirm: all four decisions are documented with rationale.
  Confirm: migration checklist has ≥ 4 steps including safe/unsafe patterns.
  Cross-reference with ADR-001 (once written): all four decisions must appear there.
  Done when: four decisions confirmed; checklist complete; ADR cross-reference noted.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "costliest to reverse" framing forces each
   decision to be made explicitly rather than deferred.
   — custom for decision documentation.

## Engagement Instructions

Pass condition: all 12 models have a stated soft-delete policy (Yes/No/N/A).
Pass condition: audit log strategy chosen from one of the 4 options with justification.
Pass condition: multi-tenancy decision documented with trigger for revisiting if deferred.
Pass condition: PK type chosen and applied consistently to all 12 models.
Pass condition: migration checklist has ≥ 4 steps; safe vs unsafe patterns documented.
Pass condition: no decision says "TBD" or "to be confirmed later."
