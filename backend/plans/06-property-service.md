# 🏘️ Property Service — Account Lookup, Manual Search, Adapter Interface

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background
The FIND PROPERTY flow has four terminal branches visible in the Figma PDF:
(1) account found via account number, (2) account not found → manual search →
address/ERF match, (3) account not found → manual search → no match →
Contact Support, (4) account not found → Try Again (re-enter number). The
property service must cover all four. The real municipal data source (Emfuleni
live DB) is not yet available; the adapter pattern ensures the route handlers
need no changes when the real source is wired in.

## Description
Implement two REST endpoints for property lookup: direct account-number query
and fuzzy address/ERF search. The data access layer is behind a typed adapter
interface; the Prisma-backed implementation is the default. Seed data from
plan/02 covers all four Figma branches.

## Purpose
Covers the FIND PROPERTY Figma flow completely. Unblocks the property-related
sections of the flow walkthrough in plan/07.

## Goal
`easy_rates/backend/services/property-service/` — two routes implemented; seed
data covers all four Figma FIND PROPERTY branches; adapter interface confirmed
swappable without route handler changes; integration smoke passes.

## Tasks

- [ ] ⚠️ T1  Write the property adapter interface at
  `easy_rates/backend/shared/adapters/property-adapter.ts`:
  ```ts
  export interface PropertyRecord {
    id: string
    accountNumber: string
    address: string
    erfNumber: string
    ownerName: string
    city: string
    metadata: Record<string, unknown>
  }

  export interface PropertyAdapter {
    findByAccountNumber(accountNumber: string): Promise<PropertyRecord | null>
    search(query: string): Promise<PropertyRecord[]>
  }
  ```
  Route handlers import only this interface — never the Prisma client directly.
  Done when: interface file exists; no route handler imports PrismaClient.

- [ ] ⚠️ T2  Write the Prisma-backed implementation at
  `easy_rates/backend/shared/adapters/property-adapter.prisma.ts`:
  - `findByAccountNumber`: `prisma.property.findUnique({ where: { accountNumber } })`
  - `search`: `prisma.property.findMany({ where: { OR: [
      { address: { contains: query, mode: 'insensitive' } },
      { erfNumber: { contains: query, mode: 'insensitive' } }
    ]}})`
  Wire this implementation into the property-service via dependency injection
  or a factory function — one file to change to swap in the real source.
  Done when: implementation compiles; grep for "new PrismaClient" in
  `services/property-service/` returns zero results.

- [ ] ⚠️ T3  `GET /property?accountNumber=<n>`
  - Validate param with Zod — return 400 if missing
  - Call `adapter.findByAccountNumber(n)` — return 200 + PropertyRecord, or 404
  - On 200: write `AuditLog` event `PROPERTY_ACCESSED` (userId from JWT,
    accountNumber queried) — POPIA requires logging access to personal information
  Done when: curl with seed ACC001 → 200; curl with NOTFOUND001 → 404;
  psql confirms `AuditLog` row with event `PROPERTY_ACCESSED` after a successful lookup.

- [ ] ⚠️ T4  `GET /property/search?q=<query>`
  - Validate param with Zod — return 400 if missing or blank
  - Call `adapter.search(query)` — return 200 + array (empty array for no match,
    never 404)
  Done when: curl with "123 Main Street" → 200 + non-empty array;
  curl with "ERF4567" → 200 + non-empty array;
  curl with "zzznomatch" → 200 + empty array `[]`.

- [ ] ⚠️ T5  Unit tests using seed data (from plan/02):
  - findByAccountNumber: account found (ACC001), account not found (NOTFOUND001)
  - search: match by address, match by ERF number, no match
  Done when: `pnpm test` passes in the property-service directory; all five
  cases covered.

- [ ] ⚠️ T6  Integration smoke against local stack (all four Figma FIND PROPERTY branches):
  ```
  ▶ Account Found
    curl GET /property?accountNumber=ACC001 → assert 200
    psql: SELECT * FROM "Property" WHERE "accountNumber"='ACC001'

  ▶ Account Not Found
    curl GET /property?accountNumber=NOTFOUND001 → assert 404

  ▶ Manual Search → Match (address)
    curl GET /property/search?q=123+Main+Street → assert 200 + non-empty array
    psql: SELECT address, "erfNumber" FROM "Property" WHERE address ILIKE '%Main%'

  ▶ Manual Search → No Match
    curl GET /property/search?q=zzznomatch → assert 200 + empty array []
  ```
  Done when: all four curl calls return expected status codes and psql confirms
  the Property rows behind the found cases.

## Recommended skill
▶ `/build-to-contract` ✅ — builds the property routes from the API contract in
   `system-design/api/property.md`.
   alt: `/architect-contract` ✅ — for designing the adapter interface before T1
   if the interface shape is unclear.

## Engagement Instructions

```bash
# 1. Adapter interface exists; no route handler imports PrismaClient directly
ls easy_rates/backend/shared/adapters/property-adapter.ts
grep -r "PrismaClient\|from.*@prisma" \
  easy_rates/backend/services/property-service/ 2>/dev/null
# Expected: adapter file present; grep returns 0 results

# 2. Unit tests green
cd easy_rates/backend/services/property-service && pnpm test
# Expected: all tests pass (5 cases: found, not found, address match, ERF match, no match)

# 3. Account Found branch: 200 + Property row in psql
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${PROPERTY_PORT:-3003}/property?accountNumber=ACC001")
echo "account found: HTTP $CODE"   # Expected: 200
psql "$DATABASE_URL" -t -c \
  "SELECT id, \"accountNumber\", address FROM \"Property\" WHERE \"accountNumber\"='ACC001';"
# Expected: 1 row

# 4. Account Not Found branch: 404
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${PROPERTY_PORT:-3003}/property?accountNumber=NOTFOUND001")
echo "account not found: HTTP $CODE"   # Expected: 404

# 5. Manual Search → Match by address: 200 + non-empty array
RESULTS=$(curl -s \
  "http://localhost:${PROPERTY_PORT:-3003}/property/search?q=123+Main+Street")
echo "$RESULTS" | jq 'length'   # Expected: ≥ 1
psql "$DATABASE_URL" -t -c \
  "SELECT address, \"erfNumber\" FROM \"Property\" WHERE address ILIKE '%Main%' LIMIT 3;"
# Expected: ≥ 1 row

# 6. Manual Search → Match by ERF: 200 + non-empty array
RESULTS=$(curl -s \
  "http://localhost:${PROPERTY_PORT:-3003}/property/search?q=ERF4567")
echo "$RESULTS" | jq 'length'   # Expected: ≥ 1

# 7. Manual Search → No Match: 200 + empty array (never 404)
RESULTS=$(curl -s \
  "http://localhost:${PROPERTY_PORT:-3003}/property/search?q=zzznomatch")
echo "$RESULTS" | jq 'length'   # Expected: 0 (empty array [], not 404)

# 8. Swappability: implementation wired only in factory/DI, not in route handlers
grep -r "property-adapter.prisma" \
  easy_rates/backend/services/property-service/ 2>/dev/null
# Expected: 0 results (swap the factory import to change data source; zero route
# handler files need editing)
```

Gate: check 1 must pass before T3/T4. Checks 3–7 cover all four Figma FIND
PROPERTY branches — all must pass before plan/07. Check 8 is the adapter
contract: zero route handler changes needed to swap the data source.
