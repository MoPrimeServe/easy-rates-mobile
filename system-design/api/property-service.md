# property-service API Contract

**Service:** property-service
**Figma flows:** FIND PROPERTY · ACCOUNT & SETTINGS (Manage Linked Properties → "Add property" entry)
**Base path:** `/property` (every path below is relative to the `/api/v1` prefix — see conventions §1).
**Auth:** **All routes require** `Authorization: Bearer <accessToken>`. No public routes. A
missing/expired token returns the standard `401 unauthenticated` (conventions §3), which the
Dio interceptor resolves via the refresh flow (conventions §6).

This contract conforms to `api/conventions.md`. The `{ data, error }` envelope, the standard
error codes (`validation_error`, `unauthenticated`, `forbidden`, `not_found`, `conflict`,
`rate_limit_exceeded`, …), date/datetime formats, money-as-decimal-string, camelCase JSON,
and the `RateLimit-*`/429 shape are all defined there and are **not** re-documented here. The
JSON bodies below show the **`data` payload only** unless stated otherwise; the real wire
response wraps it as `{ "data": <payload>, "error": null }`.

Data source: read-only mirror of the Emfuleni billing system synced into the local
`Property` table (see `docs/data-model/property-account.md`). This service never writes back
upstream. `Property` is hard-deleted and re-inserted on resync, so `id` is stable only
between syncs — clients resolve a property by `accountNumber`/search each session, then act
on the returned `id`.

---

## Central resolutions (apply to every route below)

- **Account number is exactly 8 digits** — `^\d{8}$`. Anything else is a `400 validation_error`
  before any lookup runs.
- **Identity gate.** Search results are returned **only if the requesting user's hashed SA ID
  matches the property's holder records** (`user.idNumberHash ∈ property.holderIdNumberHashes`,
  keyed HMAC — ADR-003). Enforced server-side, hash-to-hash; the client never sends an ID number,
  and no plaintext SA ID is stored on either side.
- **No-match is reported in the body, never via `404` (ADR-004).** The search routes return `200`;
  the client inspects the body for the business result. `POST /property/search/account` returns
  `{ property: null }`; `POST /property/search/address` returns `[]`. A `404` is **never** emitted
  for a no-match on either search route. (HTTP status on these routes is mechanical only: `200`,
  `400`, `401`, `429`, `5xx`.)
- **The null/empty result is deliberately ambiguous.** When an account/property does not exist
  **or** exists but fails the identity gate, the service returns the **byte-identical** result —
  `{ property: null }` (account search) or `[]` (address search). It must never reveal that an
  account exists but the user is unauthorized (security requirement — `screen-inventory.md`, FIND
  PROPERTY → Account Found? — Not Found: "Deliberately ambiguous"). Do **not** use `403` for an
  identity-gate miss on the search routes; `403` is reserved for `GET /property/:id` where a
  concrete resource id is already in hand.
- **Money fields are decimal strings** (e.g. `"1850000.00"`), per conventions §9 — never JSON
  numbers.

---

## POST /property/search/account

Look up a single property by its 8-digit account number, behind the identity gate.

**Figma transition:** Enter Account Number from Bill → **Account Found?** → Found (`200`,
`property` non-null, → Property Details Confirmation Screen) / Not Found (`200`, `property: null`,
→ Account Not Found — Try Again).

**Request:**
```json
{ "accountNumber": "10045821" }
```

| Field | Type | Required | Rules |
|---|---|---|---|
| accountNumber | string | yes | Exactly 8 digits (`^\d{8}$`) |

**Response 200 — match** (`data.property` is a property summary):
```json
{
  "data": {
    "property": {
      "id": "clr8x2k9a0001",
      "accountNumber": "10045821",
      "ownerName": "Jane Doe",
      "address": "123 Main Street, Vereeniging",
      "erfNumber": "ERF/001/VRG",
      "ward": "Ward 12"
    }
  },
  "error": null
}
```

**Response 200 — no match** (account does not exist **or** identity-gate miss — byte-identical,
deliberately ambiguous, ADR-004):
```json
{ "data": { "property": null }, "error": null }
```

> "Not found" is a `200` with `property: null`, **not** a `404` (ADR-004). The Flutter layer reads
> `data.property == null` and shows the Account Not Found — Try Again state — never an error
> dialog. The null result is fixed and identical whether the account does not exist or exists but is
> not the user's; the client cannot distinguish the two cases.

**Error responses** (standard envelope; `error.code` in parentheses — reserved for mechanical
failures, never for no-match):
| HTTP | `error.code` | Reason | Figma branch |
|---|---|---|---|
| 400 | `validation_error` | `accountNumber` missing or not exactly 8 digits | (stays on Enter Account Number — inline error) |
| 401 | `unauthenticated` | Missing or invalid access token | — |

---

## POST /property/search/address

Search by free-text address (`q`) **or** ERF number (a UI toggle — one field active at a time),
behind the identity gate. Returns an **array** of property summaries (an ERF can map to multiple
service accounts — water, electricity, rates — per `docs/data-model/property-account.md`).

**Matching strategy (ADR-005):** `q` is a **partial, case-insensitive substring match** across
the physical-address fields (`LIKE %q%`); `erfNumber` is an **exact, normalized match**
(case-insensitive, whitespace-stripped) since it is an identifier, not free text. **No Azure SQL
full-text search** — the identity gate bounds the candidate set to the user's own holder-properties
(a handful of rows), so `LIKE` is adequate and a full-text catalog is unwarranted at MVP scale.
Consequently `q` yields `0..n` results, `erfNumber` yields `0..1`.

**Figma transition:** Manual Search (Address / ERF) → **Manual Match?** → Match (non-empty array,
→ Property Details Confirmation Screen) / No Match (empty array `[]`, → No Match — Contact
Support).

**Request:** exactly one of `q` **or** `erfNumber` (the active toggle tab):
```json
{ "q": "123 Main Street" }
```
```json
{ "erfNumber": "ERF/001/VRG" }
```

| Field | Type | Required | Rules |
|---|---|---|---|
| q | string | one of q \| erfNumber | Min 3 chars; partial case-insensitive substring match across address fields |
| erfNumber | string | one of q \| erfNumber | Min 3 chars; exact normalized (case-insensitive, trimmed) match on `Property.erfNumber` |

At least one field must be present and ≥ 3 chars. Sending both, or neither, is a
`400 validation_error`.

**Response 200** (`data` payload — an **array** of property summaries; **may be empty**):
```json
[
  {
    "id": "clr8x2k9a0001",
    "accountNumber": "10045821",
    "ownerName": "Jane Doe",
    "address": "123 Main Street, Vereeniging",
    "erfNumber": "ERF/001/VRG",
    "ward": "Ward 12"
  }
]
```

Empty result:
```json
{ "data": [], "error": null }
```

> **`[]` + 200 on no match — never `404`.** An identity-gate miss is folded into the empty array
> (the user is told nothing about whether a matching property exists for someone else). The
> Flutter layer routes an empty array to "No Match — Contact Support".

**Error responses:**
| HTTP | `error.code` | Reason |
|---|---|---|
| 400 | `validation_error` | Neither field present, both present, or active field < 3 chars |
| 401 | `unauthenticated` | Missing or invalid access token |

---

## GET /property/:id

Full property detail for the **Property Details Confirmation Screen**. Called after the user
selects a property from either search route. Because a concrete `id` is in hand, an
authorization miss here returns `403 forbidden` (not the deliberately ambiguous null the search
routes use — ADR-004).

**Figma transition:** Account Found? → Found **OR** Manual Match? → Match → Property Details
Confirmation Screen (`loading` → `loaded`).

**Path parameters:**
| Param | Type | Description |
|---|---|---|
| id | string | Property `id` (cuid) from a search response |

**Response 200** (`data` payload — full property detail):
```json
{
  "id": "clr8x2k9a0001",
  "accountNumber": "10045821",
  "ownerName": "Jane Doe",
  "address": "123 Main Street, Vereeniging",
  "erfNumber": "ERF/001/VRG",
  "ward": "Ward 12",
  "extentSqm": 495,
  "municipalValue": "1850000.00",
  "dataAsOf": "2026-06-15T02:00:00.000Z"
}
```

| Field | Type | Notes |
|---|---|---|
| extentSqm | number | Erf extent in square metres |
| municipalValue | string | **Money — decimal string** (conventions §9), ZAR, 2 fraction digits |
| dataAsOf | string | **Datetime** (conventions §9) — last sync of this record; drives the staleness warning |

**Error responses:**
| HTTP | `error.code` | Reason |
|---|---|---|
| 401 | `unauthenticated` | Missing or invalid access token |
| 403 | `forbidden` | Property exists but is not linked to / authorized for this user |
| 404 | `not_found` | No property with this `id` (e.g. resync invalidated a stale `id`) |

---

## GET /property/:id/pdf

Returns a property report PDF for the Property Details Confirmation Screen "Download PDF" CTA.

**Figma transition:** Property Details Confirmation Screen → "Download PDF" → PDF export.

**Path parameters:**
| Param | Type | Description |
|---|---|---|
| id | string | Property `id` (cuid) |

**Response 200 — ENVELOPE EXCEPTION.** Unlike every other route in this service, a successful
response is **not** the `{ data, error }` JSON envelope. It is a **raw binary stream**:

```
HTTP/1.1 200 OK
Content-Type: application/pdf
Content-Disposition: attachment; filename="property-10045821.pdf"
Content-Length: <bytes>

<binary PDF bytes>
```

**Flutter:** request with `responseType: ResponseType.bytes`; do **not** run the response
through the generic `ApiResponse<T>.fromJson` envelope parser. On a `200` with
`Content-Type: application/pdf`, write the bytes to a file / hand to the viewer. **Error**
responses below still use the standard JSON envelope, so branch on the response
`Content-Type` / status before parsing.

**Error responses** (standard JSON envelope):
| HTTP | `error.code` | Reason |
|---|---|---|
| 401 | `unauthenticated` | Missing or invalid access token |
| 403 | `forbidden` | Property not linked to / authorized for this user |
| 404 | `not_found` | No property with this `id` |

---

## POST /property/link

Links the property to the current user (the Property Details Confirmation Screen "Save" CTA, and
the destination of the Manage Linked Properties "Add property" entry).

**Figma transition:** Property Details Confirmation Screen → "Save" (links property, stays on
screen). Entry path: ACCOUNT & SETTINGS → Manage Linked Properties → "Add property" → FIND
PROPERTY → … → this call.

**Request:**
```json
{ "propertyId": "clr8x2k9a0001" }
```

| Field | Type | Required | Rules |
|---|---|---|---|
| propertyId | string | yes | Property `id` (cuid) from a search/detail response |

**Response 201** (`data` payload — the linked property summary):
```json
{
  "id": "clr8x2k9a0001",
  "accountNumber": "10045821",
  "address": "123 Main Street, Vereeniging",
  "erfNumber": "ERF/001/VRG",
  "linkedAt": "2026-06-21T08:30:00.000Z"
}
```

| Field | Type | Notes |
|---|---|---|
| linkedAt | string | **Datetime** (conventions §9) — when the link was created |

**Error responses:**
| HTTP | `error.code` | Reason |
|---|---|---|
| 400 | `validation_error` | `propertyId` missing or malformed |
| 401 | `unauthenticated` | Missing or invalid access token |
| 404 | `not_found` | No property with this `propertyId` |
| 409 | `conflict` | Property already linked to this user |

---

## TypeScript interfaces

Per conventions §10: PascalCase types, camelCase fields, request types end `…Request`, response
types end `…Response`. These are the **`data` payload** shapes — wrap with `ApiResponse<T>` from
conventions §2 on the wire.

```ts
// ---- Shared summaries ----

/** Summary returned by /property/search/account and each element of /property/search/address. */
interface PropertySummaryResponse {
  id: string;
  accountNumber: string;     // exactly 8 digits
  ownerName: string | null;  // nullable per Property.ownerName (optional column)
  address: string;
  erfNumber: string | null;  // nullable per Property.erfNumber (optional column)
  ward: string;
}

/** One row of a property search result list. Identical to the summary above —
 *  lighter than PropertyDetailResponse (no extentSqm/municipalValue/dataAsOf) and
 *  never any balance (that lives in bill-service). Aliased to avoid type proliferation. */
type PropertySearchResult = PropertySummaryResponse;

// ---- POST /property/search/account ----

interface PropertySearchAccountRequest {
  accountNumber: string;     // ^\d{8}$
}

/**
 * 200 data payload. `property` is null on no-match OR identity-gate miss —
 * byte-identical in both cases, deliberately ambiguous (ADR-004).
 * There is NO 404 on no-match; non-2xx is a mechanical failure only
 * (400 validation_error, 401 unauthenticated, 429, 5xx).
 */
interface PropertySearchAccountResponse {
  property: PropertySummaryResponse | null;
}

// ---- POST /property/search/address ----

interface PropertySearchAddressRequest {
  q?: string;                // min 3 chars; partial substring match across address fields; mutually exclusive with erfNumber
  erfNumber?: string;        // min 3 chars; exact normalized match; mutually exclusive with q
}
// 200 data: PropertySearchResult[]  (may be [] — never 404 on empty; q → 0..n, erfNumber → 0..1)
// Matching: q = LIKE %q% (no Azure full-text — gate bounds the set, ADR-005).

// ---- GET /property/:id ----

interface PropertyDetailResponse {
  id: string;
  accountNumber: string;
  ownerName: string | null;
  address: string;
  erfNumber: string | null;
  ward: string;
  extentSqm: number;
  municipalValue: string;    // money — decimal string, ZAR, 2 dp
  dataAsOf: string;          // ISO 8601 datetime (UTC, ms, Z)
}

// ---- GET /property/:id/pdf ----
// Success is a raw application/pdf binary stream — NOT ApiResponse<T>.
// No success interface; errors use the standard ApiResponse error envelope.

// ---- POST /property/link ----

interface PropertyLinkRequest {
  propertyId: string;
}

interface PropertyLinkResponse {
  id: string;
  accountNumber: string;
  address: string;
  erfNumber: string | null;
  linkedAt: string;          // ISO 8601 datetime
}
```

---

## Figma Trace

Maps every FIND PROPERTY screen/branch (and the Manage Linked Properties entry) to the route
that serves it **and to the Flutter widget that triggers the call**. Screen names match
`docs/screen-inventory.md` exactly. The "Flutter trigger" column names the widget that owns the
transition in `mobile_app/easy_rates_app/lib/`; `(unbuilt)` marks a screen not yet created, with
the suggested component in parentheses.

| Figma screen / branch | Route | Flutter trigger | Notes |
|---|---|---|---|
| Manage Linked Properties → "Add property" | (entry) → Enter Account Number from Bill | ACCOUNT & SETTINGS entry (out of this flow) | No API call itself |
| Enter Account Number from Bill | `POST /property/search/account` | `AccountLookupScreen` — `TextField` + `ErButton('Look up account')` → `_lookup` | 8-digit input mask; `searching` state during the call |
| Account Found? — Found branch | `POST /property/search/account` → 200, `property` non-null | (same `_lookup`, non-null path) | → Property Details Confirmation Screen |
| Account Found? — Not Found branch | `POST /property/search/account` → 200, `property: null` (ADR-004) | (same `_lookup`, null path) | Ambiguous null → Account Not Found — Try Again (no error dialog) |
| Account Not Found — Try Again | (no call) | (unbuilt) | "Try again" → Enter Account Number; "Search by address or ERF" → Manual Search |
| Manual Search (Address / ERF) | `POST /property/search/address` | (unbuilt — `AppTabBar` Address/ERF toggle + `AppFormField` + `ErButton`) | Address/ERF toggle; one field per request |
| Manual Match? — Match branch | `POST /property/search/address` → 200 non-empty `[...]` | (unbuilt, search-submit 200 path) | → Property Details Confirmation Screen |
| Manual Match? — No Match branch | `POST /property/search/address` → 200 empty `[]` | (unbuilt, search-submit empty path) | Empty array (never 404) → No Match — Contact Support |
| No Match — Contact Support | (no call) | (unbuilt) | Terminal; client-side from an empty array |
| Property Details Confirmation Screen | `GET /property/:id` | (unbuilt — `ErCard` + `ErAmountDisplay` + `ErStatusBadge`) | Full detail incl. extentSqm, municipalValue, dataAsOf staleness warning |
| Property Details Confirmation Screen → "Save" | `POST /property/link` | (unbuilt — `ErButton('Save')`) | 201 → links property, stays on screen |
| Property Details Confirmation Screen → "Download PDF" | `GET /property/:id/pdf` | (unbuilt — `ErButton('Download PDF')`) | Binary `application/pdf` stream (envelope exception) |
| Property Details Confirmation Screen → "View More" | → **bill-service** (`bill-service.md`) | (unbuilt) | Out of scope here; routes into BILL REVIEW |

### Response field → card element (Property Details Confirmation Screen)

Binds the `GET /property/:id` `PropertyDetailResponse` to the user-facing fields named in
`screen-inventory.md`. Suggested Flutter widget in brackets; no bound widget exists yet.

| Response field | Card element | Widget | Notes |
|---|---|---|---|
| `accountNumber` | Account number | `Text` | 8 digits |
| `ownerName` | Account holder name(s) | `Text` | nullable — needs fallback rendering |
| `address` | Physical address | `Text` | |
| `erfNumber` | ERF / portion | `Text` | nullable |
| `extentSqm` | Extent (m²) | `Text` | JSON number |
| `municipalValue` | Property value (municipal) | `ErAmountDisplay` | **decimal string** — parse, do not treat as a raw double |
| `dataAsOf` | "Data as of" + staleness warning | `ErStatusBadge` | drives the staleness warning past threshold |

Search-result rows (Manual Match → multiple matches) bind the `PropertySummary` subset
(`ownerName`, `address`, `accountNumber`, `erfNumber`, `ward`) into a row card built on `ErCard`.

> **Build snapshot (2026-06-22).** Of this flow, only *Enter Account Number from Bill* exists in
> Flutter (`screens/account_lookup/account_lookup_screen.dart`), and it is a **stub**: `_lookup`
> fakes a delay and navigates to `/dashboard` instead of calling `POST /property/search/account`,
> there is no `PropertyService` client, validation is `isEmpty`-only (not `^\d{8}$`), and the
> field hint shows a 10-digit example. The four other screens, the Property card widget, and the
> address/ERF search are not built. This note is a dated snapshot — the rows above are the durable
> contract; track build progress in `mobile_app/`, not here.

---

## Rate limits

Copied from `docs/security/rate-limits.md` (Endpoint category table). Limiters emit RFC 9110
`RateLimit-*` headers and the standard `429 rate_limit_exceeded` envelope (conventions §5).

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/property/search/account` | POST | SEARCH | userId | 1 min | 10 |
| `/property/search/address` | POST | SEARCH | userId | 1 min | 10 |
| `/property/:id` | GET | READ | userId | 1 min | 60 |
| `/property/:id/pdf` | GET | READ | userId | 1 min | 60 |
| `/property/link` | POST | WRITE | userId | 1 hour | 20 |

The two SEARCH routes carry the tighter 10/min limit because they are the account/ERF
enumeration surface (POPIA breach-by-enumeration risk); a scraper hits the limit after 10
lookups and must wait a minute between bursts.

---

## Caching

Property data here is pure **identity reference data** (address, ERF, owner, ward) — a read-only
mirror that changes **only on the upstream billing sync** (see Data source above). The property
lookup/search responses are therefore cacheable, with revalidation:

| Header | Value | Applies to |
|---|---|---|
| `Cache-Control` | `private, max-age=1800` | `POST /property/search/account`, `POST /property/search/address`, `GET /property/:id` |
| `ETag` | strong validator over the response body | same |

- **`private, max-age=1800`** — cacheable for **30 minutes**. `private` (never `public`) because the
  result is **identity-gated** (`user.idNumberHash ∈ property.holderIdNumberHashes`, ADR-003/ADR-004),
  so it is **user-specific** and must never be stored in a shared/proxy cache.
- **`ETag` + `If-None-Match` revalidation.** The client may revalidate with `If-None-Match: <etag>`;
  an unchanged record returns **`304 Not Modified`** with an empty body. The validator changes when
  the billing sync re-inserts the row (`dataAsOf` advances), which naturally invalidates the cache.
- **No `no-store` exclusion is needed.** property-service carries **no financial fields** —
  balance/arrears live in bill-service (ADR-004) — so there is nothing here to mark uncacheable; only
  the identity TTL applies. (bill-service documents its own, stricter financial caching policy.)
- The PDF route (`GET /property/:id/pdf`) and the write route (`POST /property/link`) are outside this
  policy; treat their responses as `no-store`.
