# 🤖 AI Amount Calculation Model

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK from
AIAmountCalculation to Bill is set).
⛔ BLOCKED[Gate] — requires plan/03-bill.md WRITE task (Bill model defined —
AIAmountCalculation is a 1:1 optional relation on Bill).

The `AIAmountCalculation` entity stores the AI service's expected-amount result for
a given bill. The BILL REVIEW Figma flow has an explicit "View AI-Generated Expected
Amount" screen — the Flutter app fetches the AI calculation via
`GET /api/v1/bill/:id/expected-amount`. This entity must answer: is the calculation
fresh, what did the model produce, and how confident was it?

## Description

Write the complete Prisma schema block for `AIAmountCalculation`. Decides: one
calculation per bill (unique on `billId`) vs a history of recalculations; staleness
policy; whether `calculatedAt` is indexed for cleanup.

## Purpose

To answer: "how does the Flutter Bill Review screen know if the AI expected amount
is stale — and should it trust a cached calculation or always request fresh?"

## Goal

`easy_rates/system-design/docs/data-model/ai-calculation.md` — complete Prisma
schema block for `AIAmountCalculation`; `billId` uniqueness decision; staleness
policy documented; index justification.

## Tasks

- [x] ✅ THINK `/socratic "The AI service produces an expected amount for a bill.
  Should we store one calculation per bill (unique on billId — replace on
  recalculation) or a history of calculations (multiple rows per bill — the latest
  is most recent)? If the model is retrained and we want to recalculate, do we need
  to preserve the history of prior calculations for audit? And how does the Flutter
  app decide whether to show 'calculating...' or a cached result — does it poll,
  or does the API return a staleness indicator?"`
  Done when: the uniqueness decision (one per bill vs history) is made with
  justification; the staleness API behaviour is stated.

- [x] ✅ FIELDS Write the Prisma schema block for `AIAmountCalculation`:
  Fields to consider:
  - `id` (UUID)
  - `billId` (FK to Bill; onDelete: Cascade — if bill is deleted, calculation goes too)
  - `expectedAmount` (Decimal — the AI model's expected amount)
  - `confidence` (Float? — model confidence score, 0.0 to 1.0; optional if not
    all models produce a confidence score)
  - `calculatedAt` (DateTime — when the calculation was produced)
  - `modelVersion` (String — which AI model version produced this; important for
    audit when model is retrained)
  - `isStale` (Boolean @default(false) — set to true when the bill's data changes
    after calculation, triggering a recalculation)
  - `createdAt` (DateTime @default(now()))
  - Relation: `bill Bill`
  Uniqueness decision: `@@unique([billId])` if one calculation per bill (replace
  on recalculation); remove `@@unique` if history is kept.
  Done when: every field has a Prisma type; uniqueness decision stated and implemented.

- [x] ✅ STALENESS Define the staleness policy:
  When is an AIAmountCalculation considered stale?
  Option A: time-based — stale after N hours (simple; recalculates on next fetch).
  Option B: event-based — stale when the Bill or BillLineItem is updated (more
  accurate; requires an update trigger or Prisma middleware to set `isStale = true`).
  Choose one. Justify.
  How does the Flutter app know a calculation is stale?
  The API should return a `{ expectedAmount, isStale, calculatedAt }` shape so the
  Flutter client can decide whether to show "calculating..." or the cached value.
  Done when: staleness policy chosen; API response shape for staleness noted.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/ai-calculation.md`:
  Full Prisma schema block for AIAmountCalculation; uniqueness decision;
  staleness policy; API response shape note for the Flutter client.
  Done when: file exists; uniqueness decision documented; staleness policy stated.

- [x] ✅ VERIFY Cross-reference with api/bill-service.md (once written): confirm
  the `GET /api/v1/bill/:id/expected-amount` response includes `isStale`,
  `calculatedAt`, and `modelVersion` fields matching this schema.
  Confirm: `billId` FK has `onDelete: Cascade` (calculation is deleted with the bill).
  Confirm: `modelVersion` is a non-nullable String (always known which model ran).
  Done when: API contract and schema are consistent; `onDelete` confirmed; `modelVersion`
  is non-nullable.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "one per bill vs history" uniqueness question
   forces the audit and recalculation requirements to be resolved before schema is
   written.
   — custom for schema writing.

## Engagement Instructions

Pass condition: `billId` uniqueness decision is stated (`@@unique` or not) with justification.
Pass condition: `modelVersion` is a non-nullable String field.
Pass condition: `isStale` Boolean field is present with a staleness policy description.
Pass condition: `calculatedAt` is indexed (for cleanup queries).
Pass condition: staleness API behaviour is described (what does the Flutter client receive
when the calculation is stale).
