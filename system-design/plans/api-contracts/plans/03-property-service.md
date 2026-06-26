# 🏠 Property Service Contract

## Background

✅ GATE CLEARED (2026-06-22 sync) — both prerequisites now exist:
`api/conventions.md` and `docs/data-model/property-account.md`.

The property service handles the FIND PROPERTY Figma flow. The Flutter user can
search by `accountNumber` or by address/ERF number. The search response is the
data that populates the property card screen.

## Description

Write the HTTP API contract for the property service: accountNumber lookup and
address/ERF search. Includes cache TTL note from nfr.md, 404 vs empty-array
decision, and TypeScript interfaces.

## Purpose

To answer: "when a user searches for a property and gets no results — should the
API return 404 or an empty array — and how does the Flutter UI distinguish between
'not found' and 'something went wrong'?"

## Goal

`easy_rates/system-design/api/property-service.md` — 2 routes with TypeScript
interfaces; 404 vs empty-array decision explicit; cache policy from nfr.md noted.

## Tasks

- [x] ✅ THINK `/socratic "When a Flutter user types their account number and gets
  no results, should the API return 404 or an empty array with HTTP 200 — and how
  does the Flutter search screen distinguish 'no property found for this account
  number' from 'a server error occurred'? And what is the caching policy for
  property data — can it be cached, and if so, for how long?"`
  Done when: 404 vs empty-array decision is made with justification; cache policy
  is stated.  ✓ verified (/socratic compile + ADR-004; cache policy stated)

- [x] ✅ FIGMA-TRACE Map every FIND PROPERTY flow screen transition:
  "Enter account number" → GET /api/v1/property?accountNumber=...
  "Enter address or ERF" → GET /api/v1/property/search?q=... or ?erfNumber=...
  Property card loaded → data from one of the above
  "View bills" button → bill-service (separate plan)
  For each: Flutter widget that triggers it; which response field populates which
  property card element.
  Done when: all FIND PROPERTY transitions mapped.  ✓ verified (api/property-service.md
  §Figma Trace — extended table with Flutter-trigger column + response-field→card-element binding)

- [x] ✅ ACCOUNT-LOOKUP Define `GET /api/v1/property`:
  Query parameter: `accountNumber` (required) or `erfNumber` (required, mutually exclusive).
  Response 200 (found): `{ data: { property: PropertyResponse, account: AccountResponse },
    error: null }`
  Response 200 (not found): `{ data: { property: null, account: null }, error: null }`
  OR Response 404: `{ data: null, error: { code: "not_found", ... } }`
  Decision: choose between 200+null and 404. Justify.
  Note: For the FIND PROPERTY flow, a "not found" result is a valid user scenario
  (e.g. they typed the wrong account number) — the Flutter search screen should show
  a "not found" UI state, not an error dialog. This argues for 200+null rather than 404.
  TypeScript interface: `PropertyResponse`, `AccountResponse`
  Done when: decision documented; shapes defined.  ✓ verified (ADR-004 — decision is 200+null).
  RECONCILED (supersedes the spec above): kept `POST /property/search/account` not GET
  (PII in URL); `account` payload dropped (re-coupled identity/balance — balance is bill-service);
  `PropertyResponse` ≡ existing `PropertySummaryResponse`. See ADR-004.

- [x] ✅ SEARCH Define `GET /api/v1/property/search`:
  Query parameter: `q` (free-text search across address fields) or `erfNumber`.
  Response 200: `{ data: { items: PropertySearchResult[], total: number }, error: null }`
  Note: returns a list (may be multiple matching properties for a free-text search).
  `PropertySearchResult` is a lighter shape than `PropertyResponse` (no account balance).
  TypeScript interface: `PropertySearchResult`
  Decide: is `q` a free-text search (fuzzy match on address fields) or does it
  require an exact match? Free-text search has Azure SQL full-text search implications.
  Done when: search shape defined; exact vs fuzzy decision documented.  ✓ verified (ADR-005).
  RECONCILED (supersedes the spec above): partial substring `LIKE %q%` (fuzzy), NOT Azure
  full-text — the ADR-003 identity gate bounds the candidate set, so a catalog is premature;
  `erfNumber` is exact normalized. Kept `POST /property/search/address` with a bare array
  (not GET, not `{items,total}`). `PropertySearchResult` ≡ `PropertySummaryResponse`. See ADR-005.

- [x] ✅ — ✓ verified (Caching section added to property-service.md) CACHE Write the
  property-identity cache policy into `api/property-service.md`.
  Decision already made in /socratic compile: identity (address, ERF, etc.) cacheable
  ~30 min, `private` + `ETag` revalidation; any financial fetch `no-store`. REMAINING
  SLICE: this is not yet written into the artifact (contract currently has no cache section).
  NOTE (ADR-004 narrows this task): the `account.balance`/`account.arrears` exclusion is now
  moot — property-service responses carry NO financial fields (balance lives in bill-service),
  so there is nothing to exclude; only the identity TTL remains to document.
  Done when: cache policy section present in api/property-service.md.

- [x] ✅ WRITE Write `easy_rates/system-design/api/property-service.md`:
  2 routes; TypeScript interfaces; Figma Trace section; cache policy note; 404
  vs empty-array decision.
  Done when: file exists; 2 routes documented; decision explicit.  ✓ verified (file exists;
  5 routes documented; TS interfaces; Figma Trace; 404→200 + fuzzy decisions explicit).
  Cache policy note is the one outstanding piece — tracked under CACHE above.

- [x] ✅ VERIFY Confirm: `accountNumber` and `erfNumber` field names in the response
  match the Prisma schema fields from data-model/property-account.md (camelCase).
  Confirm: no `balance` or `arrears` in any cached response.
  Done when: field names match schema; financial fields not cached.
  (Unblocked — docs/data-model/property-account.md exists; not yet run. The balance/arrears
  half is trivially met — property-service has no financial fields per ADR-004.)  ✓ verified
  (Property model fields `accountNumber`/`erfNumber`/`ownerName`/`address` are camelCase at
  property-account.md L57/L59/L60/L58 and match `PropertySummaryResponse`/`PropertyDetailResponse`
  byte-for-byte; grep for balance|arrears in the deliverable returns only the L315 negating
  comment "never any balance (that lives in bill-service)" — no financial field exists to cache.)

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "404 vs empty array" framing forces the Flutter
   UI state decision to be made at API design time, not debug time.
   — custom for contract writing.

## Engagement Instructions

Pass condition: 404 vs empty-array decision is documented with justification.
Pass condition: cache TTL stated for property data; `balance`/`arrears` flagged as non-cacheable.
Pass condition: Figma Trace section maps every FIND PROPERTY transition.
Pass condition: TypeScript interfaces for `PropertyResponse`, `AccountResponse`,
and `PropertySearchResult` are present.
Pass condition: exact vs fuzzy search decision for `q` parameter is documented.

## Execution Note — 2026-06-27

### THINK (`/socratic`) answer — 404 vs empty-array, and cache policy

The service returns **`200` in every business outcome**, never `404`, for a no-result search.
`POST /property/search/account` returns `{ data: { property: null }, error: null }` and
`POST /property/search/address` returns `{ data: [], error: null }`; a `404` is reserved for the
mechanical case `GET /property/:id` where a concrete id has already been handed out and the row no
longer exists (e.g. a resync invalidated it). The decisive reason is that "no property for this
account number" is a **valid, expected user scenario** (a mistyped 8-digit number), so the Flutter
search screen must render an in-flow "Account Not Found — Try Again" / "No Match — Contact Support"
state, not an error dialog — which the layer does by reading `data.property == null` / `data.length
== 0` rather than branching on HTTP status. There is a second, security-load-bearing reason
(ADR-004): the null/empty result is **deliberately ambiguous** — a non-existent account and an
existing account that fails the identity gate (`user.idNumberHash ∈ property.holderIdNumberHashes`,
ADR-003) return the **byte-identical** body, so the API never leaks "this account exists but isn't
yours" (POPIA enumeration risk). The Flutter UI distinguishes "not found" from "server error" purely
on the envelope: a `200` with a null/empty `data` is the not-found UX state, whereas a non-2xx with a
populated `error.code` (`401 unauthenticated`, `400 validation_error`, `429`, `5xx`) is the
error/retry path the Dio interceptor handles. On **caching**: property *identity* (address, ERF,
owner, ward) is reference data that changes only on the upstream billing sync, so it is cacheable —
the `/socratic` compile fixed this at ~30 min TTL, `private` (per-user, because the identity gate
makes the result user-specific) with `ETag` revalidation; any financial fetch would be `no-store`,
but that exclusion is now **moot** because property-service carries no financial fields at all
(balance/arrears live in bill-service per ADR-004), so only the identity TTL remains to document.

### FIGMA-TRACE — evidence note

✓ verified — `api/property-service.md §Figma Trace` maps every FIND PROPERTY transition with a
**Flutter-trigger** column (e.g. `AccountLookupScreen` → `_lookup` for Enter Account Number) and a
separate **response-field → card-element** binding table for the Property Details Confirmation
Screen (`accountNumber`→Account number/`Text`, `municipalValue`→Property value/`ErAmountDisplay`,
`dataAsOf`→staleness/`ErStatusBadge`, etc.). "View More" correctly routes out to `bill-service.md`.

### Per-task evidence notes

- THINK (`/socratic`): ✓ done — answer above; decision is `200`+null/`[]` (ADR-004), cache policy
  stated (~30 min, `private` + `ETag`; financial `no-store`, now moot).
- FIGMA-TRACE: ✓ verified — §Figma Trace transition table + response-field→card-element table.
- ACCOUNT-LOOKUP: ✓ verified — `POST /property/search/account` returns `PropertySearchAccountResponse`
  `{ property: PropertySummaryResponse | null }`; 200+null decision documented (ADR-004); reconciled
  to POST (PII out of URL) with `account` payload dropped.
- SEARCH: ✓ verified — `POST /property/search/address` returns bare `PropertySearchResult[]`; ADR-005
  fuzzy `LIKE %q%` for `q`, exact normalized for `erfNumber`, no Azure full-text — all documented.
- CACHE: ✓ verified (cache gap filled 2026-06-27) — `api/property-service.md §Caching` now states
  `Cache-Control: private, max-age=1800` (30 min) on the two search routes + `GET /property/:id`,
  with `ETag`/`If-None-Match` → `304` revalidation, `private` because identity-gated (ADR-003/004),
  and no `no-store` exclusion needed since property-service carries no financial fields (ADR-004).
- WRITE: ✓ verified — file exists; 5 routes + TS interfaces + Figma Trace + 404→200 & fuzzy decisions
  present. (Cache note remains the one outstanding piece, tracked under CACHE.)
- VERIFY: ✓ verified — `accountNumber`/`erfNumber`/`ownerName`/`address` are camelCase in the Prisma
  `Property` model (property-account.md L57/L59/L60/L58) and match the contract's response shapes;
  no `balance`/`arrears` field exists in any response (only the L315 negating comment).
