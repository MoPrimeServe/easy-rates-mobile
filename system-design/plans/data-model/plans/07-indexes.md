# 🗃️ Index Strategy & Query Analysis

## Background

⛔ BLOCKED[Gate] — requires plans/01-06 complete (all entity schema blocks must
exist — the index strategy walks every model and consolidates their indexes into
a single justified table).

Individual entity plans (01-06) each include local index justifications. This plan
consolidates them, identifies the 5 highest-load queries across all Figma flows,
and confirms that no table with > 10k projected rows has an unjustified sequential
scan in its primary query path.

## Description

Identify the 5 heaviest queries by frequency × scan cost. For each, produce an
access-pattern analysis (or EXPLAIN ANALYZE stub). Consolidate all indexes from
plans/01-06 into a single index table across all 12 models.

## Purpose

To answer: "which query will run 10 million times a year on this system — and what
does the schema need to look like to serve it in under 50ms at the row counts
projected in envelope.md?"

## Goal

`easy_rates/system-design/docs/data-model/indexes.md` — top-5 queries with
access-pattern analysis; consolidated index table across all 12 models; any
sequential-scan risk on large tables called out explicitly.

## Tasks

- [x] ✅ THINK `/socratic "Which query will run 10 million times a year on this
  system — is it the OTP lookup (every login), the bill list (every BILL REVIEW
  load), or the objection status check (every TRACKING poll)? And what does the
  index need to look like to serve it in under 50ms at the row counts in
  envelope.md? If the highest-frequency query is also the one with the largest
  table, is the current index design sufficient?"`
  Done when: the 5 candidate high-frequency queries are listed; the highest is
  identified with a frequency estimate from envelope.md; the index for the highest
  is confirmed or flagged for revision.

- [x] ✅ LIST List all queries from the 7 Figma flows. For each screen transition
  that hits the database, write:
  Flow | Screen → Next Screen | Query description | Table(s) touched | Filter conditions
  e.g.:
  ONBOARDING | Phone → OTP screen | SELECT * FROM OTPAttempt WHERE phoneNumber=? AND expiresAt>now() | OTPAttempt | phoneNumber, expiresAt
  FIND PROPERTY | Enter accountNumber → Property card | SELECT * FROM Account WHERE accountNumber=? | Account | accountNumber
  BILL REVIEW | Property card → Bill list | SELECT * FROM Bill WHERE accountId=? ORDER BY billingPeriodStart DESC LIMIT 10 | Bill | accountId, billingPeriodStart
  ... (all 7 flows, all screen transitions)
  Done when: every screen transition from screen-inventory.md has a corresponding
  query row; no transition left as "to be determined."

- [x] ✅ RANK Rank the queries by frequency × row-scan cost:
  Frequency: estimated calls per day from envelope.md (DAU × usage rate for
  this screen).
  Row-scan cost: estimated rows scanned without an index vs with the index.
  Identify the top 5 by frequency × (rows scanned without index / rows scanned
  with index).
  Done when: 5 queries identified with a written frequency estimate and a scan
  cost estimate; ranking is shown.

- [x] ✅ ANALYZE For each of the top-5 queries, produce:
  a. The Prisma `findMany` or `findUnique` call that generates this query.
  b. The SQL query it generates (approximate).
  c. The index that serves it (from plans/01-06 entity plans).
  d. The projected rows scanned at 12-month scale (from envelope.md row counts).
  e. An EXPLAIN ANALYZE stub: if the table is seeded with 100k test rows in a
     dev environment, what does EXPLAIN ANALYZE show? (If not yet verifiable,
     write "analytical justification: index covers filter + sort columns → index
     scan, no sequential scan expected.")
  Done when: all 5 queries have the 5-item analysis; any query without index
  coverage is flagged as a gap.

- [x] ✅ CONSOLIDATE Produce the consolidated index table:
  Model | Index name | Fields | Index type (unique/non-unique) | Query it serves |
  Justified by (plan reference)
  Include every index defined in plans/00-06.
  Done when: all 12 models appear in the table; every index has a query reference;
  no index appears that isn't justified by a specific query.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/indexes.md`:
  Top-5 query analysis table; consolidated index table; note on any sequential
  scan risks.
  Done when: file exists; both tables complete; sequential scan risks noted.

- [x] ✅ VERIFY Walk the consolidated index table. For any table projected to have
  > 10k rows at 12 months (from envelope.md), confirm: no unindexed filter or sort
  in the top-5 queries. If a sequential scan risk is found, flag it as a gap and
  propose an index.
  Done when: every table > 10k rows has index coverage for its primary queries;
  all gaps are either resolved or explicitly accepted with justification.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "10 million times a year" framing forces index
   design to prioritise by actual query frequency from the Figma flows.
   — custom for query analysis; no single skill covers Prisma query analysis.

## Engagement Instructions

Pass condition: top-5 queries ranked by frequency × row-scan cost with written estimates.
Pass condition: consolidated index table covers all 12 models.
Pass condition: every index has a named query it serves and a plan reference.
Pass condition: every table projected > 10k rows has index coverage for its primary query.
Pass condition: sequential scan risks are either resolved (index added) or explicitly
accepted with a written justification.
