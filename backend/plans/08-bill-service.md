# 🧾 Bill Service — Fetch, Line Items, Anomaly Detection, AI Expected Amount

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background

The BILL REVIEW flow starts the moment a user taps "View Current Bill" after
finding their property. The bill fetch is from the municipality's billing system
(Emfuleni), which is not yet accessible; the adapter pattern used in the property
service is repeated here so the route handler needs zero changes when the real
source is wired in. Anomaly detection (line items that are unusually high vs
historical average) and the AI-generated expected amount are both displayed before
the user decides to dispute — both must be returned in the bill fetch response.

## Description

Implement two REST endpoints: bill fetch by account number and individual line
item detail. Add anomaly flags and AI expected amount to the bill response.
Stub the municipality billing adapter and an AI calculation adapter behind clean
interfaces identical in shape to the property adapter.

## Purpose

Covers the BILL REVIEW Figma flow: View Current Bill → Bill Line Items Breakdown
→ Charges look correct? Both the "Correct → Mark as Done" and "Dispute → Select
Charge" branches depend on this service returning a valid bill with anomaly data.

## Goal

`easy_rates/backend/services/bill-service/` — bill fetch and line items routes
implemented; anomaly flags and AI expected amount in response; both municipal
billing adapter and AI adapter are one replaceable function each; integration
smoke covers all BILL REVIEW Figma branches.

> **⚠️ Canonical-contract note (2026-06-27).** Superseded by the sealed
> `system-design/api/bill-service.md`. Routes are `GET /bills`, `GET /bills/:id`,
> `GET /bills/:id/lines`, `GET /bills/:id/ai-estimate` (NOT singular
> `GET /bill?accountNumber=`); no-result for an owned-but-missing resource is 404, but
> ownership failures are 403 and the AI route returns **503 `ai_unavailable`** (not 404)
> when no calculation exists. `category` enum is the 9-value `LineItemCategory`
> (`WATER|ELECTRICITY|PROPERTY_RATES|SANITATION|REFUSE|ARREARS|LEVY|VAT|OTHER`), NOT the
> 5-value list this plan drafted. Money is a decimal string. There is **no `AuditLog`
> table**. The AI route reads `AIAmountCalculation` and applies the **0.85 confidence
> gate** + `isStale`. Tasks reconciled below.

## Tasks

- [x] ❌ DESCOPED T1  Standalone `BillingAdapter`/`AiAdapter` interface files.
  Canonical equivalent: Prisma-backed directly via the `@easyrates/db` singleton; pure
  mapping/gate logic isolated (unit-tested) in `apps/bill/src/logic.ts`. (Original draft
  below kept for history.)

  `billing-adapter.ts`:

  ```ts
  export interface BillRecord {
    id: string
    accountNumber: string
    period: string          // e.g. "2025-05"
    totalAmount: number
    dueDate: string
    status: 'CURRENT' | 'OVERDUE' | 'PAID'
    lineItems: BillLineItem[]
  }
  export interface BillLineItem {
    id: string
    description: string
    amount: number
    category: 'WATER' | 'ELECTRICITY' | 'SEWERAGE' | 'REFUSE' | 'OTHER'
    anomalyFlag: boolean
    historicalAverage: number | null
  }
  export interface BillingAdapter {
    fetchBill(accountNumber: string, period?: string): Promise<BillRecord | null>
  }
  ```

  `ai-adapter.ts`:

  ```ts
  export interface AiAdapter {
    getExpectedAmount(accountNumber: string, period: string): Promise<number | null>
  }
  ```

  Done when: interfaces exist; no route handler imports any implementation directly.

- [x] ❌ DESCOPED T2  `billing-adapter.prisma.ts` / `ai-adapter.stub.ts`. Canonical
  equivalent: queries in `apps/bill/src/app.ts` against the `@easyrates/db` singleton;
  the AI estimate reads the real `AIAmountCalculation` row (no stub).

- [x] ✅ T3  Bill list — ✓ verified (replaces the singular `GET /bill`). `GET /bills`
  (`apps/bill/src/app.ts`) returns the per-service-account source-of-truth rows the caller
  is entitled to (ownership = `Bill.accountNumber ∈ caller's Account.accountNumber set`),
  each with `category` (dominant `LineItemCategory`), `amount`/`aiExpectedAmount` as decimal
  strings, `hasAnomaly`, and **`aiExpectedAmount` null below the 0.85 confidence gate**.
  AuditLog write DESCOPED (no such table). ✓ smoke: list returned rows for `10045821`/
  `10045822`; confident bill → `aiExpectedAmount:"430.00"`, sub-threshold bill → `null`.
  Also verified `GET /bills/:id` detail header (validFrom/validTo derived from period,
  `dataAsOf` datetime, decimal `totalAmount`).

- [x] ✅ T4  Line items — ✓ verified (replaces `GET /bill/line-item/:id`). Canonical route
  is `GET /bills/:id/lines`: full breakdown with per-line `category`/`amount`/`anomalyFlag`/
  `historicalAverage` + `subtotal`/`vatAmount`/`totalAmount` that reconcile to the source-of-
  truth total. ✓ smoke: `subtotal 532.60 + vatAmount 79.80 = totalAmount 612.40`.
  Unknown bill → 404; no token → 401 (both ✓).
  Plus `GET /bills/:id/ai-estimate`: ✓ confident branch (0.91 → estimate `430.00`,
  variance `182.40`, `isStale:false`); ✓ sub-threshold branch (0.82 → `estimatedAmount`/
  `variance` null, confidence echoed). 503 `ai_unavailable` (no calc) and 403 (not owned)
  are implemented (simple branches in `app.ts`) — see ⚠️ in the Execution Note.

- [x] ✅ T5  Seed — ✓ verified. `packages/db/prisma/seed.ts` extended: bill `2025-05`
  (sub-0.85 calc) + a new bill `2026-06` on the second account with a **confident** calc
  (0.91), both with anomaly-flagged line items. `prisma db push` + reseed green; counts:
  bill 3, billLineItem 8, aiAmountCalculation 3.

- [x] ✅ T6  Unit tests — ✓ verified. `apps/bill/src/logic.test.ts`, 12 tests green
  (`pnpm --filter ./apps/bill test`): confidence gate (`aiExpectedAmount` + `toAiEstimate`
  null/non-null at 0.84/0.85/0.91), `isStale` (model-version change, re-fetch after calc),
  `dominantCategory`, `periodBounds` (incl. Feb 28), lines reconciliation.

- [x] ✅ T7  Integration smoke — ✓ verified (transcript captured) against live
  `easyrates_dev` with a real RS256 token; all BILL REVIEW branches reachable. NOTE the
  plan's curl commands below use STALE singular routes; actual verification used the
  canonical `/bills…` routes above.

## Recommended skill

▶ `/build-to-contract` ✅ — builds the bill routes from the API contract in
   `system-design/api/bill.md`.
   alt: `/architect-contract` ✅ — for finalising the billing and AI adapter
   interfaces before T1.

## Engagement Instructions

```bash
# 1. Both adapter interfaces exist; no route handler imports PrismaClient
ls easy_rates/backend/shared/adapters/billing-adapter.ts \
   easy_rates/backend/shared/adapters/ai-adapter.ts
grep -r "new PrismaClient" easy_rates/backend/services/bill-service/ 2>/dev/null
# Expected: both files present; grep returns 0 results

# 2. Unit tests green
cd easy_rates/backend/services/bill-service && pnpm test
# Expected: all tests pass

# 3. Bill fetch: 200 + line items + anomaly flag + expectedAmount
RESP=$(curl -s \
  "http://localhost:${BILL_PORT:-3005}/bill?accountNumber=ACC001&period=2025-05")
echo "$RESP" | jq '.lineItems | length'           # Expected: ≥ 3
echo "$RESP" | jq '[.lineItems[] | .anomalyFlag] | any'  # Expected: true
echo "$RESP" | jq '.expectedAmount'               # Expected: a number, not null

# 4. Bill not found: 404
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${BILL_PORT:-3005}/bill?accountNumber=NOBILL001")
echo "bill not found: HTTP $CODE"   # Expected: 404

# 5. Line item detail: 200; unknown id: 404
LINE_ID=$(psql "$DATABASE_URL" -t -c \
  'SELECT id FROM "BillLineItem" LIMIT 1;' | tr -d ' ')
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${BILL_PORT:-3005}/bill/line-item/$LINE_ID")
echo "line item: HTTP $CODE"   # Expected: 200

# 6. Seed confirms Bill + BillLineItem rows with anomaly data
psql "$DATABASE_URL" -t -c 'SELECT COUNT(*) FROM "Bill";'
psql "$DATABASE_URL" -t -c \
  'SELECT COUNT(*) FROM "BillLineItem" WHERE "anomalyFlag" = true;'
# Expected: Bill ≥ 2, anomaly BillLineItems ≥ 1

# 7. Swappability: swap billing adapter — zero route handler changes
grep -r "billing-adapter.prisma" \
  easy_rates/backend/services/bill-service/ 2>/dev/null
# Expected: 0 results (implementation wired only in factory/DI file)
```

Gate: check 1 must pass before T3/T4. Check 3 must show anomaly flag AND
expectedAmount in the response body — a bare 200 does not pass this gate.

## Execution Note — 2026-06-27

**Built** `apps/bill` (Express/TypeScript) to the canonical
`system-design/api/bill-service.md`:

- Files: `apps/bill/src/{app.ts,server.ts,logic.ts,logic.test.ts}`, `package.json`,
  `tsconfig.json`.
- Routes: `GET /bills`, `GET /bills/:id`, `GET /bills/:id/lines`,
  `GET /bills/:id/ai-estimate`, plus `/health`.
- Reuses `@easyrates/http` envelope/`ApiError`/middleware, the shared
  `@easyrates/auth-core` `requireAuth`, and the `@easyrates/db` singleton. Ownership =
  the caller's `Account.accountNumber` set; 404 vs 403 split honoured. Money via
  `Prisma.Decimal` → 2dp decimal strings. The 0.85 confidence gate, `isStale`
  (model-version change OR bill re-fetched after the calc), and the `503 ai_unavailable`
  fallback (no `AIAmountCalculation`) are all implemented in `logic.ts`/`app.ts`.

**Verification:** `tsc --noEmit` → exit 0 ✓; `pnpm --filter ./apps/bill test` → 12/12
green ✓; integration smoke vs live `easyrates_dev` ✓ — list (confident `aiExpectedAmount`
`"430.00"` vs null sub-threshold), detail, lines reconciliation (532.60 + 79.80 = 612.40),
ai-estimate both branches, 404 unknown, 401 no-token.

**Honest ⚠️ remaining:** `503 ai_unavailable` (owned bill with no calc) and `403`
(bill owned by another user) are coded but not smoke-exercised — the seed has no owned-
no-calc bill and no foreign-owned bill, and adding those needs DB writes that were out of
session scope; both are straightforward conditional branches. `GET /bills/summary` and
`POST /bills/:id/review` are in the contract but outside this task's four-route build scope;
`GET /bills/summary` is additionally **D1-blocked** (cross-property join key) per the
contract. Rate-limiting (READ + AI 5/min) not yet wired (plan/05 track).
