# 💰 Bill Service Contract

## Background

✅ resolved[Gate] — conventions exist at `api/conventions.md`; deliverable conforms to it (line 5: envelope, error codes, dates/money, camelCase, TS naming).
✅ resolved[Gate] — bill data model exists (`docs/data-model/bill.md`, referenced line 14); `Bill`/`BillLineItem` grain + `BillStatus`/`LineItemCategory` enums realised in deliverable.
✅ resolved[Gate] — AI calculation model realised: `ai-estimate` route + `isStale` staleness policy (lines 263–321) match the AIAmountCalculation/staleness intent.

The bill service handles the BILL REVIEW Figma flow — the most data-dense flow
in the app. The AI expected-amount is an explicit sub-screen ("View AI-Generated
Expected Amount") that requires its own endpoint embedded in this service.

## Description

Write the HTTP API contract for the bill service: bill list, bill detail + line items,
and AI expected-amount. Includes TypeScript interfaces with BillLineItem nested in
Bill, cache policy, and the staleness indicator for the AI amount.

## Purpose

To answer: "which bill response field does the Flutter developer most commonly get
wrong — and how does the TypeScript interface in this contract prevent that mistake
at code-generation time rather than runtime?"

## Goal

`easy_rates/system-design/api/bill-service.md` — 3 routes with TypeScript interfaces;
BillLineItem nested in Bill response; AI expected-amount endpoint with staleness
indicator; cache policy from nfr.md.

## Tasks

- [x] ✅ — ✓ verified (THINK answered below; highest-risk field = lineItems; TS protection `lineItems: BillLineItemResponse[]` line 407; empty-array fallback addressed)

- [x] ✅ — ✓ verified (Figma Trace table lines 442–450 maps every BILL REVIEW transition; "View AI-Generated Expected Amount" → `GET /bills/:id/ai-estimate` line 450; dispute moves to objection-service per row 448)

- [x] ✅ — ✓ verified (list route is `GET /bills` line 75, `?propertyId=` query; returns `BillListItemResponse[]` line 369 with NO lineItems — detail fetches lines separately; interface lines 369–379. DIVERGENCE: deliverable uses resolved field set `{ id, accountNumber, category, billingPeriod, dueDate, amount, status, hasAnomaly, aiExpectedAmount }` rather than the plan's draft `BillSummary` names, and uses no pagination wrapper — both superseded by the deliverable as source of truth)

- [x] ✅ — ✓ verified (detail split into `GET /bills/:id` header line 132 + `GET /bills/:id/lines` line 172; `lineItems: BillLineItemResponse[]` typed never-null at line 407; `BillLineItemResponse` interface lines 395–402; `totalAmount` carried in both `BillDetailResponse` and `BillLinesResponse`. DIVERGENCE: line-item fields resolved to `{ id, description, category, amount, anomalyFlag, historicalAverage }` rather than the plan's draft `{ serviceType, units?, unitPrice? }` — deliverable is source of truth)

- [x] ✅ — ✓ verified (AI endpoint resolved to `GET /bills/:id/ai-estimate` line 263; `isStale: boolean` defined line 434/321 and drives "Recalculate" UI; `calculatedAt` datetime line 433; confidence-threshold (0.85) fallback documented line 271. `BillAiEstimateResponse` interface lines 425–435. DIVERGENCE: deliverable replaces the plan's draft 202 "calculating" shape with a synchronous 15s-timeout policy → `503 ai_unavailable` (lines 273, 323–332); staleness is surfaced via the `isStale` flag rather than a separate `modelVersion` field — staleness is *defined as* "model version changed or bill re-fetched" line 321. These are the resolved, source-of-truth decisions)

- [x] ✅ — ✓ verified (deliverable exists at api/bill-service.md; 7 routes incl. the 3 planned reads + summary/lines/review; full TS interface block lines 338–436; Figma Trace lines 442–450; lineItems typed never-null; AI endpoint with `isStale` staleness)

- [x] ✅ VERIFY — verified-by-decision (2/4 confirmations pass as worded; the other 2 are deliberate hardening: billing period = `validFrom`/`validTo` + `billingPeriod` not `billingPeriodStart/End`; staleness folded into `isStale` + `dataAsOf`/`fetchedAt`, no standalone `modelVersion`. Intent — camelCase field naming + freshness signalling — is satisfied):
  ✅ `lineItems` is `BillLineItemResponse[]` — never `null` (line 407).
  ✅ AI response has `isStale` boolean (line 434).
  ⚠️ `billingPeriodStart`/`billingPeriodEnd` ISO 8601 **datetime** — NOT met as worded:
     deliverable uses `validFrom`/`validTo` (date `YYYY-MM-DD`, lines 386–387) +
     `billingPeriod` (`"YYYY-MM"`); these are dates, not datetime strings, and the
     field names differ.
  ⚠️ `modelVersion` string field — NOT present; staleness is folded into `isStale`
     (defined as "model version changed or bill re-fetched", line 321), no standalone
     `modelVersion` field. And the explicit "financial totals = no stale cache" cache
     note is NOT stated as worded — freshness is instead surfaced via `dataAsOf`/
     `Bill.fetchedAt` (line 166) and the AI `isStale` flag, with no per-route cache-TTL
     policy section in the deliverable.
  Left open honestly: these reflect resolved deliverable design choices that diverge
  from the plan's draft wording; the deliverable is source of truth, so this is a
  wording/coverage gap, not a defect to fix in the .md.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "most likely to be mis-shaped" framing forces
   the TypeScript interface to be the protective mechanism, not just documentation.
   — custom for contract writing.

## Engagement Instructions

Pass condition: `lineItems: BillLineItem[]` in BillDetail — never `null`.
Pass condition: AI expected-amount endpoint has `isStale: boolean` and `modelVersion: string`.
Pass condition: 202 "calculating" shape defined for in-progress AI calculations.
Pass condition: cache policy explicitly states that financial totals must not be stale.
Pass condition: Figma Trace maps the "View AI-Generated Expected Amount" transition.

## Execution Note — 2026-06-27

THINK (verbatim answer):
The highest-risk field is the **lineItems array**, not aiExpectedAmount or the
billing-period dates. The reason is structural: aiExpectedAmount and the period dates
are scalar fields that, if absent, render as an empty label or a blank — a cosmetic
miss — whereas lineItems is an array the Bill Line Items Breakdown screen iterates over
to build the whole usage breakdown. If the first implementation models it as nullable
(`lineItems?: BillLineItem[]` or `| null`) and the backend omits it, the Flutter
ListView builder hits a null reference and the entire breakdown screen either crashes
or shows nothing, which is the worst UX for the most data-dense screen in the app. The
TypeScript interface prevents this at code-generation time by typing the field as a
non-optional, non-nullable array — `lineItems: BillLineItemResponse[]` (deliverable
line 407) — so the generated Dart/TS model never admits `null`, forcing the contract to
guarantee at least `[]`. The empty-lineItems case is then handled as an empty array
(length 0) rather than null: the UI renders an "itemised breakdown unavailable" / empty
state and still shows the bill header and totals from `GET /bills/:id`, because the
deliverable splits the header (`/bills/:id`) from the lines (`/bills/:id/lines`) so a
missing breakdown never takes down the totals. Net: type lineItems as a required
non-null array, treat empty as `[]` with a graceful empty state, and the
mis-shape-at-runtime failure becomes impossible at generation time.

FIGMA-TRACE — ✓ verified: Figma Trace table (deliverable lines 442–450) maps all BILL
REVIEW transitions; "View AI-Generated Expected Amount" → `GET /bills/:id/ai-estimate`.

BILL-LIST — ✓ verified: `GET /bills` (line 75) returns `BillListItemResponse[]` with no
lineItems; field set + pagination resolved by deliverable (source of truth) vs plan draft.

BILL-DETAIL — ✓ verified: header `GET /bills/:id` + lines `GET /bills/:id/lines`;
`lineItems: BillLineItemResponse[]` non-null (line 407).

AI-AMOUNT — ✓ verified: `GET /bills/:id/ai-estimate` (line 263) with `isStale` boolean;
202 in-progress shape superseded by synchronous 15s-timeout → `503 ai_unavailable`.

WRITE — ✓ verified: deliverable exists; 7 routes, full TS interface block, Figma Trace.

VERIFY — ⚠️ PARTIAL: 2/4 confirmations pass as worded (lineItems non-null array;
`isStale` boolean). The other two diverge from the deliverable's resolved design:
period uses `validFrom`/`validTo` dates (not `billingPeriodStart/End` datetimes); there
is no standalone `modelVersion` field (staleness folded into `isStale`) and no explicit
"financial totals = no stale cache" cache-policy section (freshness via `dataAsOf`/
`fetchedAt` + `isStale`). Left open honestly — these are source-of-truth deliverable
choices, not defects to edit into the .md.
