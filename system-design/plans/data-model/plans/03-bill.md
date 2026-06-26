# 💰 Bill & Line Item Models

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK from
Bill to Account is set; FK from BillLineItem to Bill is set).

The Bill entity is central to EasyRates — the BILL REVIEW Figma flow is built
entirely on it. The `DisputeCategory` enum has exactly 4 values from the Figma
process flow diagram; they must not be extended without a formal decision.
`BillLineItem` is the per-charge breakdown shown on the bill detail screen.

## Description

Write the complete Prisma schema blocks for `Bill`, `BillLineItem`, and the
`DisputeCategory` enum. Locks in the exact 4 enum values from the Figma flows.

## Purpose

To answer: "which bill query runs on every page load in the BILL REVIEW flow —
and is the index designed to serve it without a full table scan?"

## Goal

`easy_rates/system-design/docs/data-model/bill.md` — complete Prisma schema
blocks for `Bill` and `BillLineItem`; `DisputeCategory` enum with exactly 4 values;
index justifications against the BILL REVIEW queries.

## Tasks

- [x] ✅ THINK `/socratic "The BILL REVIEW flow loads bill history for a user.
  Which query runs first — 'get all bills for this account' or 'get the most recent
  bill for this account'? What does the index need to look like to serve whichever
  runs most frequently in under 50ms at peak load? And what happens to the
  BillLineItem records if a Bill is deleted — should they cascade-delete or be
  retained?"`
  Done when: the primary bill query is identified; the index direction is stated;
  the `onDelete` policy for BillLineItem is decided.

- [x] ✅ FIELDS Write the Prisma schema block for `Bill`:
  Fields to consider:
  - `id` (UUID)
  - `accountId` (FK to Account)
  - `billingPeriodStart`, `billingPeriodEnd` (DateTime — the billing cycle)
  - `issueDate` (DateTime — when the bill was generated)
  - `dueDate` (DateTime — payment deadline)
  - `totalAmount` (Decimal)
  - `amountDue` (Decimal — may differ from totalAmount if partial payments exist)
  - `isPaid` (Boolean — simplest status; or use an enum?)
  - `createdAt`, `updatedAt`
  - Relations: `account Account`, `lineItems BillLineItem[]`,
    `objections Objection[]`, `aiCalculation AIAmountCalculation?`
  Decide: is `isPaid` a boolean or a `BillStatus` enum (UNPAID / PAID / OVERDUE /
  DISPUTED)? Justify.
  Done when: every field has a Prisma type; payment status decision documented.

- [x] ✅ LINE-ITEM-FIELDS Write the Prisma schema block for `BillLineItem`:
  Fields to consider:
  - `id` (UUID)
  - `billId` (FK to Bill; onDelete: Cascade)
  - `serviceType` (e.g. Water, Electricity, Sewage, Refuse, Rates — string or enum?)
  - `description` (String — human-readable line description from the utility)
  - `units` (Decimal? — units consumed, e.g. kWh for electricity)
  - `unitPrice` (Decimal? — price per unit)
  - `amount` (Decimal — total for this line item)
  - `createdAt` (DateTime)
  - Relation: `bill Bill`
  Decide: `serviceType` as enum vs free string — enum enforces known services;
  free string accommodates unknown future service types. Justify.
  Done when: every field has a Prisma type; `onDelete: Cascade` confirmed;
  `serviceType` decision documented.

- [x] ✅ ENUM Lock in the `DisputeCategory` enum. These 4 values are from the
  Figma process flow and must not be changed without a formal design decision:
  ```prisma
  enum DisputeCategory {
    WRONG_METER_READING
    INCORRECT_TARIFF
    PROPERTY_NOT_OCCUPIED
    DUPLICATE_OTHER
  }
  ```
  Note: this enum is used on the `Objection` model (not on `Bill` directly).
  Document it here because it is derived from the Bill Review flow and the
  "Dispute a Charge" step begins in the BILL REVIEW screen.
  Done when: enum is written as a Prisma enum block; all 4 values match the
  Figma flow exactly; any alternative phrasings are noted but rejected.

- [x] ✅ INDEXES Justify indexes:
  `@@index([accountId, billingPeriodStart(sort: Desc)])` on Bill — the primary
  bill list query sorts by billing period descending for a given account.
  `@@index([billId])` on BillLineItem — the line item query fetches all line
  items for a bill by `billId`.
  Confirm the Bill index serves both:
  a. "Get the most recent bill for this account" (most common)
  b. "Get all bills for this account" (bill history screen)
  Done when: both Bill indexes justified against named Figma screen queries.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/bill.md`:
  Full Prisma schema blocks for Bill and BillLineItem; DisputeCategory enum;
  index justification table; payment status and serviceType decisions.
  Done when: file exists; all 4 DisputeCategory values documented; all decisions
  present.

- [x] ✅ VERIFY Check: exactly 4 values in DisputeCategory; no UNKNOWN or OTHER
  catch-all value (DUPLICATE_OTHER is one named value from the Figma flow, not
  a catch-all). Confirm `onDelete: Cascade` on `BillLineItem.billId`.
  Confirm `AIAmountCalculation` is a 1:1 optional relation on Bill (one AI
  calculation per bill, or none).
  Done when: 4 values confirmed; Cascade confirmed; 1:1 AI relation confirmed.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "which query runs first" framing forces index
   design to match actual query patterns from the Figma flows.
   — custom for schema writing.

## Engagement Instructions

Pass condition: `DisputeCategory` enum has exactly 4 values matching the Figma flow.
Pass condition: BillLineItem has `onDelete: Cascade` on the `billId` FK.
Pass condition: Bill has a composite index on `accountId` + `billingPeriodStart`.
Pass condition: payment status decision (boolean `isPaid` vs enum) is documented.
Pass condition: `serviceType` decision (enum vs string) is documented.
