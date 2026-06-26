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

> **⚠️ Canonical-contract note (2026-06-27).** This plan predates the sealed
> `system-design/api/property-service.md`. The contract supersedes it: routes are
> `POST /property/search/account`, `POST /property/search/address`, `GET /property/:id`
> (NOT a singular `GET /property?accountNumber=`); no-result is **200 + null/[]**, never
> 404 (ADR-004); an identity gate (`user.idNumberHash ∈ property.holderIdNumberHashes`,
> ADR-003) gates every result; there is **no `AuditLog` table** in the migrated schema.
> The adapter-interface tasks (T1/T2) were a pre-Prisma abstraction; the service is
> Prisma-backed directly via the `@easyrates/db` singleton (one shared client, no per-route
> `new PrismaClient`). Tasks below are reconciled to the contract.

## Tasks

- [x] ❌ DESCOPED T1  Standalone `PropertyAdapter` interface file. Canonical equivalent:
  the service is Prisma-backed directly through the shared `@easyrates/db` singleton
  (no service instantiates its own client). Route handlers in `apps/property/src/app.ts`
  use the singleton; pure mapping/gate logic is isolated in `apps/property/src/mappers.ts`
  (unit-tested) rather than behind an adapter facade.

- [x] ❌ DESCOPED T2  `property-adapter.prisma.ts`. Canonical equivalent: queries live in
  `apps/property/src/app.ts` against the `@easyrates/db` singleton
  (`prisma.property.findUnique/findMany`, `contains … mode:"insensitive"` for `q`,
  exact normalized `equals` for `erfNumber` per ADR-005).

- [x] ✅ T3  Account lookup — ✓ verified. `POST /property/search/account`
  (`apps/property/src/app.ts`): Zod 8-digit gate (`^\d{8}$`) → 400 `validation_error`;
  identity-gated `prisma.property.findUnique`; **200 + `{property:…}`** on a gate hit,
  **200 + `{property:null}`** on no-match OR gate miss (byte-identical, ADR-004) — never
  404. AuditLog write DESCOPED (no such table in the migrated schema).
  ✓ smoke: `10045821` → 200 + full summary (ward from metadata); `99999999` → `200 {property:null}`;
  `"123"` → 400 `validation_error`; no token → 401.

- [x] ✅ T4  Manual search — ✓ verified. `POST /property/search/address`: exactly one of
  `q | erfNumber` (≥3 chars) else 400; `q` = `LIKE %q%` across address; `erfNumber` = exact
  normalized match; identity-gate misses fold into `[]`; **200 + array**, never 404.
  ✓ smoke: `q:"Main Street"` → 1-element array; `erfNumber:"ERF/002/VBP"` → 1-element array;
  `q:"zzznomatch"` → `[]`; both fields → 400.
  Also verified beyond plan: `GET /property/:id` full detail (`extentSqm`, `municipalValue`
  decimal string `"1850000.00"`, `dataAsOf`); **Caching** (`Cache-Control: private, max-age=1800`
  + strong `ETag`, `If-None-Match` → **304**); unknown id → 404.

- [x] ✅ T5  Unit tests — ✓ verified. `apps/property/src/mappers.test.ts`, 9 tests green
  (`pnpm --filter ./apps/property test`): identity-gate pass/miss/null-hash/empty-set,
  summary projection incl. ward-from-metadata, null ownerName/erfNumber, detail money
  coercion to 2dp decimal string.

- [x] ✅ T6  Integration smoke — ✓ verified (transcript captured). All FIND PROPERTY
  branches exercised against the live seeded `easyrates_dev` with a real RS256 token. NOTE
  the plan's curl commands below use the STALE singular routes/404 semantics; the actual
  verification used the canonical routes/200-null semantics above.
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

## Execution Note — 2026-06-27

**Built** `apps/property` (Express/TypeScript, pnpm workspace) to the canonical
`system-design/api/property-service.md`:

- Files: `apps/property/src/{app.ts,server.ts,mappers.ts,mappers.test.ts}`,
  `package.json`, `tsconfig.json` (extends base).
- Routes: `POST /property/search/account`, `POST /property/search/address`,
  `GET /property/:id`, plus `/health` from `@easyrates/http`.
- Reuses the foundation: `@easyrates/http` `{data,error}` envelope + `ApiError` +
  `asyncHandler` + error/notFound middleware; the **shared** `requireAuth` RS256
  bearer middleware promoted into `@easyrates/auth-core` (one copy, reused by all
  three services + apps/auth); `@easyrates/db` Prisma singleton.
- Identity gate (ADR-003) enforced server-side hash-to-hash. ADR-004 200+null/[]
  honoured. Caching section implemented: `Cache-Control: private, max-age=1800` +
  strong `ETag`, `304` on `If-None-Match`. Money as 2dp decimal string; `ward`/
  `extentSqm`/`municipalValue`/`dataAsOf` read from `Property.metadata` (the synced
  raw fields).
- Seed extended (`packages/db/prisma/seed.ts`): the seed user's `idNumberHash` is
  now a real keyed HMAC that appears in the seed properties' `holderIdNumberHashes`
  (so the gate hits), a second property/account added (so address search returns an
  array and the dashboard can consolidate), property metadata populated. Schema
  gained notification-preference fields on `User` (see plan/12); `prisma db push`
  + reseed run green against live `easyrates_dev`.

**Verification:** `pnpm install` ✓; `pnpm -r exec tsc --noEmit` → exit 0 ✓;
`pnpm --filter ./apps/property test` → 9/9 green ✓; integration smoke vs the live
seeded DB with a real RS256 token (minted via `@easyrates/auth-core` TokenService +
the dev keypair) ✓ — account hit/null, address array/`[]`, both-fields 400, detail
with decimal `municipalValue`, cache headers + `304`, unknown-id 404, no-token 401.

**Honest ⚠️ remaining:** `GET /property/:id/pdf` and `POST /property/link` (in the
contract but outside this task's build scope); a true identity-gate-MISS smoke on the
search routes needs an 8-digit account held by ANOTHER user in the seed (the gate-miss
path is unit-tested, and the no-result null/`[]` path is smoke-verified). Rate-limiting
(`RateLimit-*`) not yet wired (cross-cutting; plan/05 queue/limiter track).
