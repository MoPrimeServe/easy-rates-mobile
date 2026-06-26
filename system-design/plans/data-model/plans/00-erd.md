# 🗂️ Entity-Relationship Diagram

## Background

⛔ BLOCKED[Gate] — requires parent plan/01-service-boundaries.md VERIFY task
(service module names finalised — entity ownership by module must be confirmed
before FK directions are drawn).

The ERD is the foundation of the entire data-model sub-scope. Every subsequent plan
(01-08) uses the entity list and FK relationships established here. Writing entity
plans before the ERD exists means writing in the dark — FK decisions and `onDelete`
policies change which fields belong where.

## Description

Draw the full entity-relationship diagram for all 12 Prisma entities. Show every
FK relationship, FK direction, and `onDelete` policy. Produce the canonical entity
list that all downstream data-model plans use.

## Purpose

To answer: "which entity has the most incoming FK relationships — and is that
entity's `onDelete` policy the one most likely to cascade a destructive delete
through the whole schema?"

## Goal

`easy_rates/system-design/docs/data-model/erd.md` — ASCII ERD covering all 12
entities; every relationship labelled with FK direction and `onDelete` policy;
entity ownership by Node.js service module noted.

## Tasks

- [x] ✅ THINK `/socratic "Which entity in EasyRates has the most incoming FK
  relationships — and what happens if it is deleted? Is the correct onDelete policy
  Cascade (delete children), Restrict (prevent delete if children exist), or SetNull
  (orphan the children)? And which of these three policies is most dangerous to
  get wrong in a production municipal system?"`
  Done when: the most FK-connected entity is identified; the cascade risk is
  described; the preferred `onDelete` policy reasoning is written.

- [x] ✅ LEARN `/unpack "Prisma referential actions — Cascade, Restrict, NoAction,
  SetNull, SetDefault — what each means for the parent and child rows, when each
  is appropriate, and what Prisma does at the database level vs the application
  level for each action"`
  Done when: you can explain the difference between `onDelete: Restrict` and
  `onDelete: NoAction` in Prisma; you know when `onDelete: SetNull` requires the
  FK field to be optional.

- [x] ✅ DRAW Draw the ASCII ERD for all 12 entities:
  User | OTPAttempt | Property | Account | Bill | BillLineItem | Objection |
  EvidenceFile | ObjectionDraft | Notification | MunicipalityResponse |
  AIAmountCalculation
  Show: entity boxes, FK arrows with direction (→ = FK is on the left entity),
  cardinality (1:1, 1:N, M:N — no M:N are expected here), relationship labels.
  Do not include field detail — only entity name and FK arrows. Field detail
  belongs in the entity-specific plans (01-06).
  Done when: all 12 entities appear; every relationship has a FK arrow and a
  cardinality label; no entity is isolated (every entity must be connected to
  at least one other).

- [x] ✅ ANNOTATE For every FK relationship, state the `onDelete` policy and
  justify it in one line:
  e.g. "OTPAttempt.userId → User: onDelete Cascade — if a user is deleted, their
  OTP attempts are deleted too; no orphan OTP records."
  Identify at least three relationships where the policy choice is non-obvious
  (e.g. should deleting an Account cascade-delete Bills? Should deleting a User
  cascade-delete Objections, or should Objections be retained for audit?)
  Done when: every FK relationship has an `onDelete` policy; every policy has a
  one-line justification; non-obvious choices are highlighted.

- [x] ✅ OWNERSHIP Map each entity to its owning Node.js service module:
  e.g. "User, OTPAttempt → auth-service"
  "Property, Account → property-service"
  "Bill, BillLineItem, AIAmountCalculation → bill-service"
  "Objection, EvidenceFile, ObjectionDraft → objection-service"
  "Notification → notification-service"
  "MunicipalityResponse → municipality-service (or objection-service?)"
  For any entity whose ownership is ambiguous, state the decision and justify it.
  Done when: every entity has a named owning service module; no entity is "shared"
  without a written justification.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/erd.md`:
  ASCII ERD block; FK/onDelete annotation table; entity ownership table.
  Done when: file exists; ERD, annotations, and ownership all in one document;
  a developer reading this can understand the full relationship structure without
  reading any other file.

- [x] ✅ VERIFY Count FK relationships. Confirm: every entity except User (which
  has no FK to another entity) has at least one outgoing FK. Confirm: no circular
  FK relationships. Confirm: the ownership table has exactly 12 entities, each
  owned by exactly one service module.
  Done when: counts match; no circular FKs; 12 entities, 12 owners.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the cascade-risk framing forces `onDelete` policy
   decisions to be grounded in actual data integrity consequences.
   alt: `/unpack` ✅ — Prisma referential actions if the difference between
   Restrict, NoAction, and Cascade is not already clear.

## Engagement Instructions

Pass condition: all 12 entities appear in the ASCII ERD.
Pass condition: every FK relationship has an `onDelete` policy stated in the
annotation table.
Pass condition: every `onDelete` policy has a one-line justification.
Pass condition: no entity has an `onDelete: Cascade` on a relationship that
could destroy audit-critical data (e.g. deleting a User must not cascade-delete
their Objections if Objections must be retained for audit).
Pass condition: every entity is mapped to exactly one owning service module.
