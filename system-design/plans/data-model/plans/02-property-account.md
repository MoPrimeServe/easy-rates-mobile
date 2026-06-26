# 🏠 Property & Account Models

## Background

⛔ BLOCKED[Gate] — requires plan/00-erd.md WRITE task (ERD complete — FK
directions for Property→Account and Account→User are set).

Property and Account are the anchor entities for the FIND PROPERTY and ACCOUNT &
SETTINGS Figma flows. `accountNumber` and `erfNumber` are the two search keys used
in the FIND PROPERTY flow; they must be indexed. The relationship between User,
Property, and Account is the most ambiguous in the schema — a ratepayer may have
multiple properties, each with its own account number.

## Description

Write the complete Prisma schema blocks for `Property` and `Account`. Includes:
address fields, GIS/geographic fields if any, `accountNumber` (indexed), `erfNumber`
(indexed), FK from Account to Property and to User.

## Purpose

To answer: "a ratepayer has multiple properties — does the schema represent that as
User → Property → Account, or User → Account → Property — and which direction makes
it easier to answer 'show me all bills for this user'?"

## Goal

`easy_rates/system-design/docs/data-model/property-account.md` — complete Prisma
schema blocks for `Property` and `Account`; `accountNumber` and `erfNumber` indexes
justified against the FIND PROPERTY search endpoints.

## Tasks

- [x] ✅ THINK `/socratic "A ratepayer has multiple properties, each with its own
  municipal account number. How should the schema model this — User owns Accounts
  which own Properties, or User owns Properties which have Accounts? Which direction
  makes the 'find all bills for this user' query simpler? And if a property is
  transferred to a new owner, what happens to the Account and its Bills?"`
  Done when: the FK direction between User, Property, and Account is decided with
  written rationale; the property-transfer scenario is addressed.

- [x] ✅ FIELDS Write the Prisma schema block for `Property`:
  Fields to consider:
  - `id` (UUID)
  - `erfNumber` (unique? — one ERF per property; indexed for search)
  - `streetAddress`, `suburb`, `city`, `postalCode`
  - `latitude`, `longitude` (Decimal? — for GIS if needed)
  - `propertyType` (residential / commercial / agricultural — enum or string?)
  - `createdAt`, `updatedAt`
  - Relations: `accounts Account[]`
  Decide: does Property have a FK to User (owner), or is ownership via Account?
  Done when: every field has a Prisma type; `erfNumber` uniqueness and index stated.

- [x] ✅ ACCOUNT-FIELDS Write the Prisma schema block for `Account`:
  Fields to consider:
  - `id` (UUID)
  - `accountNumber` (unique — the municipal account number; indexed for lookup)
  - `userId` (FK to User — this is whose account it is)
  - `propertyId` (FK to Property — which property the account is for)
  - `balance` (Decimal — current balance, can be negative for arrears)
  - `arrears` (Decimal — amount overdue)
  - `lastBillDate` (DateTime?)
  - `status` (ACTIVE / SUSPENDED / CLOSED — enum)
  - `createdAt`, `updatedAt`
  - Relations: `user User`, `property Property`, `bills Bill[]`
  Decide: are `balance` and `arrears` denormalised onto Account (updated by a
  background job or webhook) or always computed from Bills at query time?
  Done when: every field has a Prisma type; `accountNumber` uniqueness and index
  stated; `balance`/`arrears` decision documented.

- [x] ✅ INDEXES Justify indexes:
  `accountNumber`: used in GET /api/v1/property?accountNumber=... (FIND PROPERTY
  flow); must be `@unique` — one account per account number.
  `erfNumber`: used in GET /api/v1/property?erfNumber=... (FIND PROPERTY flow);
  must be `@unique` or `@@unique` — one ERF per property.
  `Account.userId`: used in "show all accounts for this user" queries.
  `Account.propertyId`: used in "show all accounts for this property" queries.
  Done when: every index has a justification referencing a Figma flow or an
  API endpoint.

- [x] ✅ WRITE Write `easy_rates/system-design/docs/data-model/property-account.md`:
  Full Prisma schema blocks for Property and Account; index justification table;
  FK direction decision; `balance`/`arrears` decision.
  Done when: file exists; both schema blocks complete; all decisions documented.

- [x] ✅ VERIFY Cross-reference with api/property-service.md (once written): confirm
  `accountNumber` and `erfNumber` indexes justify the search endpoints in the
  property service contract. Confirm: the field names in the schema match the
  camelCase field names in the API contract.
  Done when: field names match; indexes justify the API endpoints.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the ownership-direction question forces the FK design
   to be grounded in the query patterns that matter.
   — custom for schema writing.

## Engagement Instructions

Pass condition: Property schema block has `erfNumber` with `@unique` and `@@index`.
Pass condition: Account schema block has `accountNumber` with `@unique` and `@@index`.
Pass condition: FK direction between User, Property, and Account is stated and justified.
Pass condition: `balance`/`arrears` denormalisation decision is documented.
Pass condition: every index has a justification referencing a Figma flow or API endpoint.
