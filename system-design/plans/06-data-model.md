# 🗄️ Database Design

## Background
⛔ BLOCKED[Gate] — requires plans/01-service-boundaries.md VERIFY task (service and
Node.js module names finalised in service-map.md).
⛔ BLOCKED[Gate] — requires plans/02-envelope.md VERIFY task (row-count estimates
available to justify index decisions).

The data model is the load-bearing structure of the backend. API response shapes,
TypeScript interfaces, and every database query in the codebase are derived from it.
Designing API contracts before the data model means building the house after hanging
the curtains. This plan must complete before plan/09 (API contracts) starts.

## Description
Design the Prisma schema for all services: entity-relationship diagram, field types,
relation types (`@relation`, one-to-one, one-to-many, many-to-many), index strategy
(`@index`, `@@index`), soft-delete policy, audit log approach, multi-tenancy decision,
PK type, and migration plan. Ground all sizing and index decisions in the row-count
estimates from envelope.md.

## Purpose
To answer: "which query will run 10 million times a year — and is our schema designed
to serve it without a full table scan?" Every index must be justified by a named query.
Every field that is absent is a conscious decision.

## Goal
`easy_rates/system-design/docs/data-model.md` — ERD (ASCII), model table (model →
fields → types → constraints → indexes), four explicit design decisions, migration
strategy, and the five heaviest queries with their expected access pattern.

## Tasks

- [x] ✅ THINK `/socratic "Which query will run 10 million times a year on this
  system — and what does the schema need to look like for that query to return in
  under 50ms at peak load without a full table scan? What are the top five heaviest
  queries by frequency × row-scan cost?"`
  Done when: the top-5 heaviest queries are named with their access pattern; the
  fields they filter/sort on are identified as index candidates.
  Downstream: the top-5 heaviest queries and their access patterns become the
  "Query Patterns" section of data-model.md — write it before filling any `@index`
  in the FIELDS task. An index not tied to a named query in this section is rejected.

- [x] ✅ LEARN `/unpack "Prisma schema — @relation one-to-one vs one-to-many vs
  many-to-many, @index vs @@index vs @unique, onDelete Cascade vs Restrict vs SetNull,
  Prisma include vs select for query optimisation, and prisma migrate dev vs
  prisma migrate deploy for production"`
  Done when: you can choose the right relation type and index directive for each
  relationship in this schema without looking up the docs.

- [x] ✅ ERD Draw the entity-relationship diagram (ASCII is fine). Include all
  entities across all services:
  User | Property | Account | Bill | BillLineItem | Objection |
  EvidenceFile | OTPAttempt | ObjectionDraft | Notification |
  MunicipalityResponse | AIAmountCalculation
  For each relationship: FK direction, `onDelete` policy (Cascade vs Restrict vs
  SetNull), optional (`?`) or required.
  Done when: every entity from service-map.md is in the ERD; no entity is owned
  by two services; every relation has an `onDelete` policy.

- [x] ✅ FIELDS For each model, produce a Prisma schema block and a field table:
  Field name | Prisma type | optional? | @unique | @index | @default |
  Justification for index (query that uses it)
  Use envelope.md row counts to drive index decisions: add `@index` only if the
  field appears in a WHERE or ORDER BY clause on a table projected to exceed 10k rows.
  Done when: every model has a complete schema block and field table; every `@index`
  has a one-line query justification; no speculative indexes.
  Downstream: the Prisma model blocks produced here are the schema source of truth
  copied verbatim into backend plans/02 (Prisma schema file). Any field renamed or
  added after that point requires a migration; record the reason in the MIGRATIONS task.

- [x] ✅ DECISIONS Make and document four design decisions explicitly:
  a. Soft-delete policy: `is_deleted` + `deleted_at` flag vs hard delete — decide
     per model; Objection and EvidenceFile almost certainly need soft-delete for
     audit reasons.
  b. Audit log: Prisma middleware, `prisma-audit-trail` package, or a manual
     `AuditEvent` model? Which models need it (Objection status changes, billing
     data access)?
  c. Multi-tenancy: is municipality-level data isolation needed? (If EasyRates
     serves multiple municipalities eventually, does that require a `municipality`
     FK on every model, or separate database schemas?)
  d. PK type: UUID (`UUIDField(primary_key=True, default=uuid4)`) vs auto-integer.
     UUID is harder to enumerate in API attacks; integer is simpler to debug.
  Done when: all four decisions are written with rationale; "we'll decide later"
  is not an acceptable answer for any of them.
  Downstream: the four decisions feed three downstream plans:
  - Audit log decision → plan/07 (security) — which events are audited and by what mechanism
  - Multi-tenancy decision → plan/08 (container topology) — whether a per-municipality
    schema or FK flag changes the container configuration
  - PK type decision → plan/09 (API contracts) — all ID fields in request/response schemas
    must use the type chosen here (UUID string vs integer)
  Record each decision as a named entry so downstream plans can reference by name.

- [x] ✅ MIGRATIONS Write the migration strategy:
  One initial `prisma migrate dev` per service at project creation.
  Zero-downtime migration checklist for schema changes post-launch using
  `prisma migrate --create-only` to review SQL before applying:
  add nullable column → backfill → add constraint → drop old column (never the
  reverse order).
  Done when: strategy is one paragraph; zero-downtime checklist has at least four
  steps; the checklist is specific to Prisma migration behaviour and Azure SQL
  lock escalation on large tables.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model.md`
      → decomposed: see `plans/data-model/MASTER_PLAN.md`
  Done when: all sub-documents in plans/data-model/ are complete and data-model.md
  links to them.

- [x] ✅ VERIFY Run EXPLAIN ANALYZE on the five heaviest queries against a locally
  seeded database, or model the access pattern analytically:
  "This query does a point lookup on Property.account_number with an index →
  no table scan; expected cost: O(log n)."
  Flag any query that would result in a sequential scan on a table projected
  > 10k rows as a design defect requiring an index or query rewrite.
  Done when: all five queries have an access-pattern analysis; no unexplained
  Seq Scan on a large table; any Seq Scan is either accepted with a justification
  or resolved with an index.

## Recommended skill
▶ `/socratic` ✅ — THINK task; the "10 million queries" framing forces index decisions
   to be grounded in actual query patterns rather than intuition.
   alt: `/unpack` ✅ — Prisma schema directives and relation types if any are not
   already fluent.

## Engagement Instructions

```bash
# 1. File exists
ls -lh easy_rates/system-design/docs/data-model.md
# Expected: present, size > 3 KB

# 2. All entities from service-map.md have a model block
for entity in "User" "Property" "Account" "Bill" "BillLineItem" \
              "Objection" "EvidenceFile" "OTPAttempt" "Notification" \
              "MunicipalityResponse" "AuditLog"; do
  printf "%-25s %s mentions\n" "$entity:" \
    "$(grep -c "$entity" easy_rates/system-design/docs/data-model.md)"
done
# Expected: each ≥ 1

# 3. Every @index has a one-line query justification
INDEX_COUNT=$(grep -c "@index\|@@index" easy_rates/system-design/docs/data-model.md)
JUST_COUNT=$(grep -cE "@index.*#|@@index.*#|#.*query|#.*lookup|#.*filter" \
  easy_rates/system-design/docs/data-model.md)
echo "Index directives: $INDEX_COUNT | With justification comments: $JUST_COUNT"
# Expected: JUST_COUNT >= INDEX_COUNT

# 4. All four design decisions documented
for decision in "soft.delete\|soft delete" "audit.log\|audit log" \
               "multi.tenan\|tenancy" "UUID\|uuid\|primary key\|PK type"; do
  printf "%-30s %s lines\n" "$decision:" \
    "$(grep -icE "$decision" easy_rates/system-design/docs/data-model.md)"
done
# Expected: each ≥ 1 (decision + rationale)

# 5. Zero-downtime migration checklist ≥ 4 steps
grep -iE "zero.downtime|create.only|backfill|nullable.*column|drop.*column|lock escalation" \
  easy_rates/system-design/docs/data-model.md | wc -l
# Expected: ≥ 4 lines (one per checklist step)

# 6. No TBD / deferred decisions
grep -iE "TBD|decide later|to be determined" \
  easy_rates/system-design/docs/data-model.md
# Expected: 0 results

# 7. Query-pattern analysis covers the 5 heaviest queries
grep -iE "EXPLAIN|seq scan|index scan|point lookup|O\(log|full scan|access pattern" \
  easy_rates/system-design/docs/data-model.md | wc -l
# Expected: ≥ 5 lines (one access-pattern note per heavy query)

# 8. ASCII ERD present
grep -cE "\+[-]+\+|[|].*--|-->|<--|has many|belongs to" \
  easy_rates/system-design/docs/data-model.md
# Expected: ≥ 5 lines (ERD diagram or relation annotations)
```

Gate: checks 1–7 must pass before plan/09 (API contracts) may start.
Check 8 confirms the ERD exists — a purely prose data model is not acceptable.
The four decisions from check 4 must be cited by name in plans/07, 08, and 09
before those plans may close.
