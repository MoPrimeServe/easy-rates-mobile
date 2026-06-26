# bill-service API contract

**Base path:** `/bills` (relative to `/api/v1` — see `api/conventions.md` §1)
**Auth:** Every route requires `Authorization: Bearer <accessToken>`. There are no `[public]` routes.
**Conforms to:** `api/conventions.md` (envelope, standard error codes, dates/money, camelCase, TS naming). This contract states only its own routes, payloads, and per-route error codes; standard codes (`401 unauthenticated`, `403 forbidden`, `404 not_found`, `400 validation_error`, `429 rate_limit_exceeded`, `500`) are defined there and not re-documented.

---

## Bill grain (read first)

The bill grain is the single most important thing to understand before consuming this service. There are **two layers**, and this service implements both.

**1. Per-service-account bills are the source of truth.**
Bills are stored per **service account**, keyed by `Bill.accountNumber` + `period` (see `docs/data-model/bill.md`). One physical property has **up to 3 service accounts** — water, electricity, and rates — and therefore up to 3 distinct bills per period, each with its own `accountNumber`, `status`, line items, and AI estimate. Every stored row, every `GET /bills`, `GET /bills/:id`, `GET /bills/:id/lines`, `POST /bills/:id/review`, and `GET /bills/:id/ai-estimate` operates at this per-account grain. This is the authoritative layer.

**2. `GET /bills/summary` is a consolidated projection, not a stored table.**
The Home Dashboard shows one consolidated total across all of the user's linked properties. That total is **computed on read** by projecting (aggregating) over the per-account bills the user is entitled to — it is **not** a stored, materialised `Summary` row. There is no summary table in the data model; do not treat it as a system of record. If the per-account bills change, the projection changes.

**⚠ BLOCKED on the D1 billing-integration dependency.**
Cross-property and cross-account consolidation (grouping a user's water/electricity/rates accounts under the *same physical property*, and rolling all properties into one dashboard total) requires a **stable property-grouping join key** that ties multiple `accountNumber`s to one property. That key must come from **Emfuleni's billing export** and is **not yet guaranteed by the upstream data**. Until the join key is delivered and proven stable:

- `GET /bills/summary` `totalOutstanding` (the cross-property roll-up) and the per-property `outstanding` breakdown are **provisional** and **blocked on D1**.
- `GET /bills?propertyId=` filtering and the "grouped by property" UI presentation depend on the same join key and inherit the same block.
- Per-account reads (`GET /bills/:id`, `/lines`, `/review`, `/ai-estimate`) are **not** blocked — they need only `accountNumber`, which Emfuleni already supplies.

This is flagged here, not silently assumed. Treat any cross-account grouping as unverified until D1 closes.

---

## `GET /bills/summary`

**Category:** READ. Home Dashboard consolidated projection across the user's linked properties.

> This response is a **projection** computed on read over the per-account bills, not a stored table. `totalOutstanding` and the per-property `outstanding` breakdown are the **cross-property roll-up** and are **D1-blocked** (see Bill grain). `accountHolderName` and `nextDueDate` are derived from the same underlying bills.

**Request:** no path params, no query params.

**Success — 200:**
```json
{
  "data": {
    "totalOutstanding": "4820.50",
    "nextDueDate": "2026-07-15",
    "accountHolderName": "Thabo M. Nkosi",
    "properties": [
      {
        "propertyId": "clx7property001",
        "address": "12 Houtkop Road, Vanderbijlpark",
        "outstanding": "3120.00"
      },
      {
        "propertyId": "clx7property002",
        "address": "8 Frikkie Meyer Blvd, Vanderbijlpark",
        "outstanding": "1700.50"
      }
    ]
  },
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `totalOutstanding` | decimal string | Sum across all linked properties. **D1-blocked** (projection). |
| `nextDueDate` | date | Earliest upcoming `dueDate` across outstanding bills. |
| `accountHolderName` | string | Display name of the account holder. |
| `properties[].propertyId` | string | Property grouping id (depends on the D1 join key). |
| `properties[].address` | string | Display address. |
| `properties[].outstanding` | decimal string | Per-property outstanding (projection). **D1-blocked.** |

**Errors:** `401`, `403`.

---

## `GET /bills`

**Category:** READ. The source-of-truth bill rows (per service account). The UI groups these by linked property; that grouping depends on the D1 join key (see Bill grain).

**Request — query params:**

| Param | Type | Required | Notes |
|---|---|---|---|
| `propertyId` | string | No | Scope the list to a single property. Resolving `propertyId` → the property's service accounts depends on the **D1 join key** (Bill grain). Omitted → all bills the user is entitled to. |

**Success — 200:**
```json
{
  "data": [
    {
      "id": "clx7bill001",
      "accountNumber": "ACC-WATER-0012",
      "category": "WATER",
      "billingPeriod": "2026-06",
      "dueDate": "2026-07-15",
      "amount": "612.40",
      "status": "OVERDUE",
      "hasAnomaly": true,
      "aiExpectedAmount": "430.00"
    },
    {
      "id": "clx7bill002",
      "accountNumber": "ACC-ELEC-0012",
      "category": "ELECTRICITY",
      "billingPeriod": "2026-06",
      "dueDate": "2026-07-15",
      "amount": "1980.00",
      "status": "CURRENT",
      "hasAnomaly": false,
      "aiExpectedAmount": null
    }
  ],
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | Bill cuid. |
| `accountNumber` | string | Service-account key (source of truth). |
| `category` | LineItemCategory | `WATER` \| `ELECTRICITY` \| `PROPERTY_RATES` \| `SANITATION` \| `REFUSE` \| `ARREARS` \| `LEVY` \| `VAT` \| `OTHER`. |
| `billingPeriod` | string | `"YYYY-MM"`. |
| `dueDate` | date | ISO 8601 `YYYY-MM-DD`. |
| `amount` | decimal string | Bill total. |
| `status` | BillStatus | `CURRENT` \| `OVERDUE` \| `PAID` \| `DISPUTED`. |
| `hasAnomaly` | boolean | True if any line item on the bill is flagged. |
| `aiExpectedAmount` | decimal string \| null | AI expected total if a confident estimate exists; `null` otherwise (e.g. confidence < 0.85, or no calculation). Full estimate via `GET /bills/:id/ai-estimate`. |

**Errors:** `400` (invalid `propertyId`), `401`, `403` (property not owned), `404` (property not found).

---

## `GET /bills/:id`

**Category:** READ. Bill detail header for one service-account bill.

**Request:** path param `id` — bill cuid.

**Success — 200:**
```json
{
  "data": {
    "id": "clx7bill001",
    "accountNumber": "ACC-WATER-0012",
    "accountHolder": "Thabo M. Nkosi",
    "billingPeriod": "2026-06",
    "validFrom": "2026-06-01",
    "validTo": "2026-06-30",
    "totalAmount": "612.40",
    "status": "OVERDUE",
    "dataAsOf": "2026-06-18T04:12:00.000Z"
  },
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | string | Bill cuid. |
| `accountNumber` | string | Service-account key. |
| `accountHolder` | string | Account holder display name. |
| `billingPeriod` | string | `"YYYY-MM"`. |
| `validFrom` | date | Start of the billing period. |
| `validTo` | date | End of the billing period. |
| `totalAmount` | decimal string | Bill total. |
| `status` | BillStatus | `CURRENT` \| `OVERDUE` \| `PAID` \| `DISPUTED`. |
| `dataAsOf` | datetime | When EasyRates last synced this bill from the municipality (`Bill.fetchedAt`). |

**Errors:** `401`, `403`, `404`.

---

## `GET /bills/:id/lines`

**Category:** READ. Line-item breakdown for one bill. All amounts are decimal strings.

**Request:** path param `id` — bill cuid.

**Success — 200:**
```json
{
  "data": {
    "billId": "clx7bill001",
    "billingPeriod": "2026-06",
    "lineItems": [
      {
        "id": "clx7line001",
        "description": "Water consumption (45 kl)",
        "category": "WATER",
        "amount": "498.40",
        "anomalyFlag": true,
        "historicalAverage": "310.00"
      },
      {
        "id": "clx7line002",
        "description": "Sanitation levy",
        "category": "SANITATION",
        "amount": "34.20",
        "anomalyFlag": false,
        "historicalAverage": null
      }
    ],
    "subtotal": "532.60",
    "vatAmount": "79.80",
    "totalAmount": "612.40"
  },
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `billId` | string | Parent bill cuid. |
| `billingPeriod` | string | `"YYYY-MM"`. |
| `lineItems[].id` | string | Line-item cuid. |
| `lineItems[].description` | string | Line description. |
| `lineItems[].category` | LineItemCategory | Enum as above. |
| `lineItems[].amount` | decimal string | Line amount. |
| `lineItems[].anomalyFlag` | boolean | True = AI flagged this line. |
| `lineItems[].historicalAverage` | decimal string \| null | Per-category average for anomaly comparison; `null` = no history yet. |
| `subtotal` | decimal string | Sum of line amounts before VAT. |
| `vatAmount` | decimal string | VAT total. |
| `totalAmount` | decimal string | Bill total (matches `GET /bills/:id` `totalAmount`). |

**Errors:** `401`, `403`, `404`.

---

## `POST /bills/:id/review`

**Category:** WRITE. Records the outcome of the "Charges look correct?" review step for one bill.

**Request:** path param `id` — bill cuid.
```json
{ "outcome": "CORRECT" }
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `outcome` | string | Yes | `"CORRECT"` \| `"DISPUTED"`. |

**Success — 200:**
```json
{
  "data": {
    "billId": "clx7bill001",
    "outcome": "DISPUTED",
    "reviewedAt": "2026-06-21T08:40:00.000Z"
  },
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `billId` | string | Bill cuid reviewed. |
| `outcome` | string | Echo of the recorded outcome. |
| `reviewedAt` | datetime | When the review was recorded. |

**Errors:** `400` (invalid/missing `outcome`), `401`, `403`, `404`.

---

## `GET /bills/:id/ai-estimate`

**Category:** READ + AI. AI expected amount for one bill. Subject to **both** the READ limiter and the AI limiter (userId, 5/min). See Rate limits.

> **Endpoint naming (resolved):** this route is `/bills/:id/ai-estimate` — **not** `/bills/:id/expected-amount` or `/bills/:id/ai-expected-amount`. This is the single authoritative spelling, matching `service-map.md` and the AI calculation data model.

**Request:** path param `id` — bill cuid.

**Confidence threshold:** if `confidence < 0.85`, `estimatedAmount` (and therefore `variance`) is `null` and the Flutter app shows the screen-inventory fallback message rather than a number. At or above 0.85, the estimate is shown.

**Sync timeout / availability:** the estimate is served synchronously with a **15-second** timeout. On timeout or AI-backend unavailability, the route returns `503` (`ai_unavailable`) and the app shows the unavailable/retry fallback. A stale calculation (`isStale = true`) is still returned with `200`; the app shows a "Recalculate" prompt.

**Success — 200 (confident estimate):**
```json
{
  "data": {
    "billId": "clx7bill001",
    "actualAmount": "612.40",
    "estimatedAmount": "430.00",
    "variance": "182.40",
    "confidence": 0.91,
    "reasoning": "Your meter reading appears high relative to your 6-month average consumption.",
    "basis": "6-month consumption average + tariff schedule 2026/27",
    "calculatedAt": "2026-06-15T09:23:00.000Z",
    "isStale": false
  },
  "error": null
}
```

**Success — 200 (confidence below threshold):**
```json
{
  "data": {
    "billId": "clx7bill001",
    "actualAmount": "612.40",
    "estimatedAmount": null,
    "variance": null,
    "confidence": 0.72,
    "reasoning": "Not enough consistent history to produce a confident estimate.",
    "basis": "Insufficient historical data",
    "calculatedAt": "2026-06-15T09:23:00.000Z",
    "isStale": false
  },
  "error": null
}
```

| Field | Type | Notes |
|---|---|---|
| `billId` | string | Bill cuid. |
| `actualAmount` | decimal string | The billed total (`Bill.totalAmount`). |
| `estimatedAmount` | decimal string \| null | AI expected total. `null` when `confidence < 0.85`. |
| `variance` | decimal string \| null | `actualAmount − estimatedAmount`. `null` when `estimatedAmount` is `null`. |
| `confidence` | float | 0.0–1.0. Display threshold = **0.85**. |
| `reasoning` | string | AI explanation shown on the "View AI-Generated Expected Amount" screen. |
| `basis` | string | What the estimate was computed from. |
| `calculatedAt` | datetime | When the AI calculation was produced. |
| `isStale` | boolean | True if the deployed model version changed or the bill was re-fetched after the calculation; app shows "Recalculate". |

**Error — 503 (AI unavailable):**
```json
{ "data": null, "error": { "code": "ai_unavailable", "message": "The expected-amount estimate is temporarily unavailable. Please try again.", "details": {} } }
```

| HTTP | `error.code` | Meaning | `details` | Flutter UI |
|---|---|---|---|---|
| 503 | `ai_unavailable` | AI backend timed out (>15s) or is unreachable. Retryable. | `{}` | Unavailable fallback + retry CTA. |

**Errors:** `401`, `403`, `404`, `503` (`ai_unavailable`).

---

## TypeScript interfaces

```ts
type BillStatus = 'CURRENT' | 'OVERDUE' | 'PAID' | 'DISPUTED';

type LineItemCategory =
  | 'WATER'
  | 'ELECTRICITY'
  | 'PROPERTY_RATES'
  | 'SANITATION'
  | 'REFUSE'
  | 'ARREARS'
  | 'LEVY'
  | 'VAT'
  | 'OTHER';

type ReviewOutcome = 'CORRECT' | 'DISPUTED';

// GET /bills/summary  (consolidated projection — D1-blocked roll-up)
interface BillSummaryPropertyResponse {
  propertyId: string;
  address: string;
  outstanding: string; // decimal string
}

interface BillSummaryResponse {
  totalOutstanding: string; // decimal string — D1-blocked
  nextDueDate: string;      // date YYYY-MM-DD
  accountHolderName: string;
  properties: BillSummaryPropertyResponse[];
}

// GET /bills  (source-of-truth list; optional ?propertyId=)
interface BillListItemResponse {
  id: string;
  accountNumber: string;
  category: LineItemCategory;
  billingPeriod: string;          // "YYYY-MM"
  dueDate: string;                // date
  amount: string;                 // decimal string
  status: BillStatus;
  hasAnomaly: boolean;
  aiExpectedAmount: string | null; // decimal string | null
}

// GET /bills/:id  (detail header)
interface BillDetailResponse {
  id: string;
  accountNumber: string;
  accountHolder: string;
  billingPeriod: string; // "YYYY-MM"
  validFrom: string;     // date
  validTo: string;       // date
  totalAmount: string;   // decimal string
  status: BillStatus;
  dataAsOf: string;      // datetime
}

// GET /bills/:id/lines
interface BillLineItemResponse {
  id: string;
  description: string;
  category: LineItemCategory;
  amount: string;                  // decimal string
  anomalyFlag: boolean;
  historicalAverage: string | null; // decimal string | null
}

interface BillLinesResponse {
  billId: string;
  billingPeriod: string; // "YYYY-MM"
  lineItems: BillLineItemResponse[];
  subtotal: string;      // decimal string
  vatAmount: string;     // decimal string
  totalAmount: string;   // decimal string
}

// POST /bills/:id/review
interface BillReviewRequest {
  outcome: ReviewOutcome;
}

interface BillReviewResponse {
  billId: string;
  outcome: ReviewOutcome;
  reviewedAt: string; // datetime
}

// GET /bills/:id/ai-estimate
interface BillAiEstimateResponse {
  billId: string;
  actualAmount: string;          // decimal string
  estimatedAmount: string | null; // decimal string | null when confidence < 0.85
  variance: string | null;        // decimal string | null
  confidence: number;             // float 0.0–1.0; display threshold 0.85
  reasoning: string;
  basis: string;
  calculatedAt: string;           // datetime
  isStale: boolean;
}
```

---

## Figma Trace

| Screen / transition | Route |
|---|---|
| Home Dashboard (consolidated total, per-property breakdown, next due date) | `GET /bills/summary` |
| Bills List (source-of-truth bills, grouped by property) | `GET /bills` (optionally `?propertyId=`) |
| Bill detail header (entering a bill from the list) | `GET /bills/:id` |
| Bill Line Items Breakdown (usage breakdown screen) | `GET /bills/:id/lines` |
| "Charges look correct?" → choose CORRECT / DISPUTED | `POST /bills/:id/review` |
| Mark as Correct (confirm correct outcome) | `POST /bills/:id/review` `{ "outcome": "CORRECT" }` |
| View AI-Generated Expected Amount (estimate, reasoning, variance) | `GET /bills/:id/ai-estimate` |

---

## Rate limits

From `docs/security/rate-limits.md` (endpoint category table). Limiters emit RFC 9110 `RateLimit-*` headers + `Retry-After`; 429 uses the standard `rate_limit_exceeded` envelope.

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/bills/summary` | GET | READ | userId | 1 min | 60 |
| `/bills` | GET | READ | userId | 1 min | 60 |
| `/bills/:id` | GET | READ | userId | 1 min | 60 |
| `/bills/:id/lines` | GET | READ | userId | 1 min | 60 |
| `/bills/:id/review` | POST | WRITE | userId | 1 hour | 20 |
| `/bills/:id/ai-estimate` | GET | READ + AI | userId | 1 min | 5 |

`GET /bills/:id/ai-estimate` gets the **AI limiter (5/min)** *in addition to* the READ limiter (`aiEstimateLimiter` applied alongside `readLimiter` on this route only).
