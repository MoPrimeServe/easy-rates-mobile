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

## Tasks

- [ ] ⚠️ T1  Write adapters at `easy_rates/backend/shared/adapters/`:

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

- [ ] ⚠️ T2  Write Prisma-backed stub implementations:
  - `billing-adapter.prisma.ts` — queries `Bill` and `BillLineItem` models
  - `ai-adapter.stub.ts` — returns a fixed expected amount from seed data

  Done when: stubs compile; `grep -r "new PrismaClient"` in
  `services/bill-service/` returns zero results.

- [ ] ⚠️ T3  `GET /bill?accountNumber=<n>&period=<ym>`
  - Validate params with Zod
  - Call `billingAdapter.fetchBill(accountNumber, period)`
  - Call `aiAdapter.getExpectedAmount(accountNumber, period)`
  - Return 200 with `BillRecord` + `expectedAmount` field, or 404
  - On 200: write `AuditLog` event `BILL_ACCESSED` (userId from JWT,
    accountNumber + period queried) — POPIA requires logging access to financial
    personal information
  Done when: curl with seed ACC001 returns bill with line items, anomaly flags,
  and expectedAmount field; psql confirms `AuditLog` row with event `BILL_ACCESSED`.

- [ ] ⚠️ T4  `GET /bill/line-item/:id`
  - Return single `BillLineItem` with full detail
  - Return 404 if not found
  Done when: curl returns correct line item; unknown id returns 404.

- [ ] ⚠️ T5  Seed data for BILL REVIEW Figma branches (add to `prisma/seed.ts`):
  - Bill available (ACC001, current period, 3+ line items, at least one anomaly)
  - Bill not available (no Bill record for NOBILL001)
  - All charges correct (no anomaly flags)
  - Mixed: some anomaly, some clean
  Done when: `pnpm db:seed` runs; psql confirms Bill + BillLineItem rows.

- [ ] ⚠️ T6  Unit tests: bill found, bill not found, expected amount present,
  expected amount null (AI stub returns null). Line item: found, not found.
  Done when: `pnpm test` passes in bill-service directory.

- [ ] ⚠️ T7  Integration smoke: curl GET /bill?accountNumber=ACC001 → 200 +
  line items + expectedAmount; psql confirms Bill row; anomaly flag true on
  at least one line item.
  Done when: all Figma BILL REVIEW branches reachable via curl.

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
