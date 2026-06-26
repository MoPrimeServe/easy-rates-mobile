# objection-service — API Contract

**Base path:** `/objections` (relative to the `/api/v1` prefix — see `api/conventions.md` §1).
**Auth:** every route requires `Authorization: Bearer <accessToken>`. There are no public
routes in this service.
**Conforms to:** `api/conventions.md` (envelope §2, standard codes §3, validation §4,
rate limits §5, async §8, dates/money §9, camelCase + PascalCase §10). This contract states
only its own routes, payloads, and per-route codes; it does not re-document the standard ones.

This service owns the full objection lifecycle — draft, evidence, submission, tracking, and
resolution. It **absorbs the former status-service** `GET …/status` route (the plan dissolves
status-service; `GET /objections/:ref/status` now lives here). The inbound municipality status
webhook is **not** part of this service — it is handled by municipality-service.

---

## Status model

`ObjectionStatus` has **exactly four** values, locked from the Figma TRACKING & RESOLUTION
flow (`docs/data-model/objection.md`):

```
UNDER_REVIEW | MORE_INFO_REQUESTED | UPHELD | REJECTED
```

The Figma screens show more labels than this (`draft`, `submitted`, `pending`, `escalated`,
`closed`). Those are **not** enum values. They map onto the four-value model as follows:

| Figma label | What it actually is | Mapping |
|---|---|---|
| `draft` | The `ObjectionDraft` entity (a separate model, pre-submission) | Not an `Objection` and not a status. A draft has no `ObjectionStatus`. The `POST /objections/draft` response returns the literal string `"DRAFT"` as a client display marker only. |
| `submitted` / `pending` | The just-submitted state | `UNDER_REVIEW`. There is no intermediate `SUBMITTED` status — creating the `Objection` row *is* the submission, and it is born `UNDER_REVIEW`. |
| `escalated` | A formal appeal after `REJECTED` | A **client-side display state** layered on top of the enum. The `refNumber` and the underlying status are unchanged; `escalated: true` is returned by `POST /objections/:ref/escalate` for the client to render. |
| `closed` | A case the user closed after `UPHELD` | A **client-side display state**, not an enum value. `POST /objections/:ref/close` returns `closed: true` for the client to render. |

The server never stores `draft`, `submitted`, `pending`, `escalated`, or `closed` as a status.
Flutter renders these display states from the four enum values plus the boolean flags above.

`refNumber` format: `ELM-2026-NNNNNN` (assigned on submission completion).

---

## `POST /objections/draft`

Create or save a draft objection. Returns the upload constraints so the Flutter `file_picker`
can validate before upload, not after.

**Upsert (idempotent save).** A user has **at most one open draft** per
objection-in-progress (keyed by the disputed `lineItemIds` / charges). This route is an
**UPSERT**: if no open draft exists it **creates** one; if an open draft already exists it
**overwrites** it in place with the new payload. Either way the response is `200 OK` with the
saved draft. Repeated saves are therefore idempotent — re-saving the same form does not stack
up multiple drafts, and there is **no `409` for "a draft already exists."** (The `409 conflict`
below is reserved for the distinct case where a *submitted, active objection* already covers
one or more of these charges — not for an existing open draft.)

**Category:** WRITE · **Auth:** required.

### Request

| Field | Type | Required | Notes |
|---|---|---|---|
| `lineItemIds` | `string[]` | Yes | IDs of the disputed bill line items. |
| `category` | `ObjectionCategory` | Yes | One of `WRONG_METER_READING`, `INCORRECT_TARIFF`, `PROPERTY_NOT_OCCUPIED`, `DUPLICATE_OTHER`. |
| `notes` | `string` | No | 10–2000 chars when present. |

```json
{
  "lineItemIds": ["clitem_a1", "clitem_a2"],
  "category": "WRONG_METER_READING",
  "notes": "The meter reading on this bill is far higher than my actual usage."
}
```

### Response — `200 OK`

`200` whether the draft was newly created or an existing open draft was overwritten (UPSERT —
see above). The response always carries the saved draft.

```json
{
  "data": {
    "objectionId": "cldraft_x1",
    "status": "DRAFT",
    "uploadConfig": {
      "maxFileSizeBytes": 10485760,
      "acceptedMimeTypes": ["application/pdf", "image/jpeg", "image/png"],
      "maxFilesPerObjection": 5
    }
  },
  "error": null
}
```

`status` is the literal display marker `"DRAFT"` (see Status model). `uploadConfig` mirrors
`docs/security/upload-validation.md` exactly. `objectionId` is stable across re-saves of the
same open draft.

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | Missing `lineItemIds`/`category`, or `notes` outside 10–2000 chars. |
| 401 | `unauthenticated` | No / invalid token. |
| 409 | `conflict` | A **submitted, active objection** already exists for one or more of these charges. (Not raised for an existing open *draft* — that path UPSERTs and returns `200`.) |

---

## `POST /objections/:id/evidence`

Attach **one** evidence file. Call repeatedly to attach up to `maxFilesPerObjection` (5).
`multipart/form-data`. The file is magic-byte validated server-side (declared `Content-Type`
is not trusted — see `docs/security/upload-validation.md` Rule C).

This route **resolves the naming split** (`/objection/:id/documents` vs
`/objections/:id/evidence`) in favour of `/objections/:id/evidence`.

**MORE_INFO_REQUESTED re-upload (audit F-3):** when the objection is in
`MORE_INFO_REQUESTED`, a successful upload via this route also **auto-transitions** its status
back to `UNDER_REVIEW` (screen-inventory: Upload Requested Docs → automatic
`more_info_requested → under_review`). No separate re-submit call is needed; the upload is the
trigger.

**Category:** WRITE · **Auth:** required · **Content-Type:** `multipart/form-data`.

### Request (form fields)

| Field | Type | Required | Notes |
|---|---|---|---|
| `file` | binary | Yes | The evidence file. Max 10 MiB (`10485760` bytes). Detected type must be one of `application/pdf`, `image/jpeg`, `image/png`. |
| `label` | string | No | Optional human label for the file. |

### Response — `201 Created`

```json
{
  "data": {
    "evidenceId": "clev_9",
    "filename": "meter-photo.jpg",
    "mimeType": "image/jpeg",
    "sizeBytes": 2483910,
    "uploadedAt": "2026-06-21T10:30:00.000Z"
  },
  "error": null
}
```

`mimeType` is the **detected** type, not the client-declared header.

### Errors

| HTTP | `error.code` | When | `details` |
|---|---|---|---|
| 400 | `file_missing` | No `file` part in the request. | `{}` |
| 401 | `unauthenticated` | No / invalid token. | `{}` |
| 403 | `forbidden` | Objection not owned by the caller. | `{}` |
| 404 | `not_found` | Objection / draft does not exist. | `{}` |
| 413 | (multer default) | File exceeds 10 MiB. | — |
| 422 | `invalid_file_type` | Detected type not in the allowlist (or unrecognised magic bytes). | `{ detectedType, allowedTypes }` |

```json
{
  "data": null,
  "error": {
    "code": "invalid_file_type",
    "message": "File type not supported. Upload PDF, JPG, or PNG only.",
    "details": {
      "detectedType": "application/zip",
      "allowedTypes": ["application/pdf", "image/jpeg", "image/png"]
    }
  }
}
```

---

## `GET /objections/:id/sufficiency`

Evidence-sufficiency check — backs the "Check evidence" CTA and the **Sufficient evidence?**
diamond in EVIDENCE & CHALLENGE. Rule-based for MVP: document count + type per dispute
category (AI content verification is post-MVP). Closes the forward orphan for this transition.

**Category:** READ · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": {
    "objectionId": "cldraft_x1",
    "sufficient": false,
    "missing": [
      { "category": "WRONG_METER_READING", "requiredDocTypes": ["meter_photo", "previous_reading"] }
    ]
  },
  "error": null
}
```

`sufficient: true` → the client proceeds to Review Summary; `false` → the client routes to
**Prompt — Add More Evidence**, rendering `missing[].requiredDocTypes` as the "what's missing"
copy. `missing` is empty when `sufficient` is `true`.

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | Objection / draft does not exist. |

---

## `GET /objections/:id/summary`

Review Summary screen — the pre-submission "check everything is right" view.

**Category:** READ · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": {
    "objectionId": "cldraft_x1",
    "property": {
      "accountNumber": "1234567890",
      "address": "12 Vaal Street, Vanderbijlpark"
    },
    "billingPeriod": "2026-05",
    "disputedItems": [
      {
        "lineItemId": "clitem_a1",
        "label": "Water consumption",
        "chargedAmount": "1850.00",
        "expectedAmount": "620.00",
        "category": "WRONG_METER_READING"
      }
    ],
    "documents": [
      { "evidenceId": "clev_9", "filename": "meter-photo.jpg", "mimeType": "image/jpeg" }
    ],
    "totalDisputedAmount": "1230.00"
  },
  "error": null
}
```

All amounts are decimal strings (§9). `expectedAmount` is nullable (no AI estimate available).

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | Objection / draft does not exist. |

---

## `POST /objections/:id/submit`

Submit the draft as a formal objection. **Asynchronous** — submission triggers a queue task,
notifications, and the municipality adapter. Returns `202 Accepted` with the async job handle
(§8). On completion a `refNumber` (`ELM-2026-NNNNNN`) is assigned and `status` becomes
`UNDER_REVIEW`. Idempotency key = the draft id (resubmitting the same draft returns the same
job / objection rather than creating a duplicate).

**Category:** SUBMIT · **Scope:** userId · **Window/limit:** 5 / 24 hours · **Auth:** required.

### Response — `202 Accepted`

```json
{
  "data": {
    "jobId": "cljob_77",
    "statusUrl": "/api/v1/objections/cljob_77/status"
  },
  "error": null
}
```

Flutter shows a "processing" state and polls `statusUrl` until the objection reaches a
terminal state (§8).

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | No documents attached, or no description/notes. |
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Draft not owned by the caller. |
| 404 | `not_found` | Draft does not exist. |
| 409 | `conflict` | This draft has already been submitted. |
| 422 | `unprocessable` | Draft is incomplete (semantically rejected for submission). |

---

## `GET /objections`

List the caller's objections — backs the **Tracking** list screen (the "My objections"
overview the user lands on before drilling into a single case). Paginated per
`api/conventions.md` §7 (`?page=&pageSize=`, `Paginated<ObjectionSummary>`). Returns a
**lighter** shape than `GET /objections/:ref/status` — one summary row per objection, with no
`statusTimeline`, no `disputedItems`, and no `municipalityResponse`.

**Category:** READ · **Auth:** required.

### Request (query params)

| Param | Type | Required | Notes |
|---|---|---|---|
| `page` | `int` | No | 1-indexed. Default `1` (§7). |
| `pageSize` | `int` | No | Default `20`, max `100` (§7). |
| `status` | `ObjectionStatus` | No | Filter to one status (`UNDER_REVIEW`, `MORE_INFO_REQUESTED`, `UPHELD`, `REJECTED`). Omit for all. |

### Response — `200 OK`

```json
{
  "data": {
    "items": [
      {
        "refNumber": "ELM-2026-000123",
        "category": "WRONG_METER_READING",
        "status": "MORE_INFO_REQUESTED",
        "title": "Water consumption — 12 Vaal Street",
        "propertyLabel": "12 Vaal Street, Vanderbijlpark",
        "createdAt": "2026-06-18T08:00:00.000Z"
      }
    ],
    "page": 1,
    "pageSize": 20,
    "total": 3,
    "totalPages": 1
  },
  "error": null
}
```

Scoped to the authenticated user (a caller only ever sees their own objections). `status` is
one of the four `ObjectionStatus` values. `title` is a short server-composed label for the
list row; `propertyLabel` is the human-readable address. An invalid `status` value is a
`400 validation_error`.

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | `status` is not one of the four `ObjectionStatus` values, or `page`/`pageSize` out of range. |
| 401 | `unauthenticated` | No / invalid token. |

---

## `GET /objections/:ref/status`

Track Objection Status screen. Folded in from the dissolved status-service. Looked up by the
human-readable `refNumber`.

**Category:** READ · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": {
    "refNumber": "ELM-2026-000123",
    "status": "MORE_INFO_REQUESTED",
    "submittedAt": "2026-06-18T08:00:00.000Z",
    "lastUpdatedAt": "2026-06-20T14:12:00.000Z",
    "statusTimeline": [
      { "status": "UNDER_REVIEW", "at": "2026-06-18T08:00:00.000Z", "note": "Submitted." },
      { "status": "MORE_INFO_REQUESTED", "at": "2026-06-20T14:12:00.000Z", "note": "Please supply a recent meter photo." }
    ],
    "disputedItems": [
      {
        "lineItemId": "clitem_a1",
        "label": "Water consumption",
        "chargedAmount": "1850.00",
        "expectedAmount": "620.00",
        "category": "WRONG_METER_READING"
      }
    ],
    "municipalityResponse": {
      "note": "Please supply a recent meter photo.",
      "adjustedAmount": null
    }
  },
  "error": null
}
```

`status` is always one of the four `ObjectionStatus` values. `municipalityResponse` is `null`
until the municipality responds; `adjustedAmount` is a nullable decimal string.

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | No objection with that `refNumber`. |

---

## `POST /objections/:ref/probe`

"Request status update" CTA. Sends a nudge to the municipality for a stalled case. Rate-limited
at the **business level** (separate from the express limiter): max 3 probes per objection, at
most one per 24 h. After the 3rd probe, the case auto-escalates to support.

**Category:** WRITE · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": {
    "refNumber": "ELM-2026-000123",
    "probesSent": 2,
    "probesRemaining": 1
  },
  "error": null
}
```

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | No objection with that `refNumber`. |
| 429 | `rate_limit_exceeded` | Probe limit reached (3 total, or one already sent in the last 24 h). `details.retryAfterSeconds`. |

---

## `POST /objections/:ref/escalate`

File a formal appeal after a `REJECTED` decision. Keeps the **same** `refNumber`. `escalated`
is a client display state, **not** one of the four enum values (see Status model) — the
underlying `ObjectionStatus` is unchanged.

**Category:** WRITE · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": { "refNumber": "ELM-2026-000123", "escalated": true },
  "error": null
}
```

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | No objection with that `refNumber`. |
| 409 | `conflict` | Objection is not in `REJECTED` state — escalation is only valid after a rejection. |

---

## `POST /objections/:ref/close`

Close the case after an `UPHELD` decision and adjustment has been viewed. `closed` is a client
display state, **not** an enum value (see Status model).

**Category:** WRITE · **Auth:** required.

### Response — `200 OK`

```json
{
  "data": { "refNumber": "ELM-2026-000123", "closed": true },
  "error": null
}
```

### Errors

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | No / invalid token. |
| 403 | `forbidden` | Objection not owned by the caller. |
| 404 | `not_found` | No objection with that `refNumber`. |

---

## TypeScript interfaces

```ts
// ---- Enums (locked — see docs/data-model/objection.md) ----
type ObjectionCategory =
  | 'WRONG_METER_READING'
  | 'INCORRECT_TARIFF'
  | 'PROPERTY_NOT_OCCUPIED'
  | 'DUPLICATE_OTHER';

// Exactly four values. draft/submitted/pending/escalated/closed are NOT members.
type ObjectionStatus =
  | 'UNDER_REVIEW'
  | 'MORE_INFO_REQUESTED'
  | 'UPHELD'
  | 'REJECTED';

// ---- Shared upload config (from docs/security/upload-validation.md) ----
interface UploadConfig {
  maxFileSizeBytes: number;        // 10485760
  acceptedMimeTypes: string[];     // ['application/pdf','image/jpeg','image/png']
  maxFilesPerObjection: number;    // 5
}

// ---- POST /objections/draft ----
interface ObjectionDraftRequest {
  lineItemIds: string[];
  category: ObjectionCategory;
  notes?: string;                  // 10–2000 chars when present
}

interface ObjectionDraftResponse {
  objectionId: string;
  status: 'DRAFT';                 // client display marker only — not an ObjectionStatus
  uploadConfig: UploadConfig;
}

// ---- POST /objections/:id/evidence (multipart) ----
interface EvidenceUploadResponse {
  evidenceId: string;
  filename: string;
  mimeType: string;                // detected type, not the declared header
  sizeBytes: number;
  uploadedAt: string;              // ISO 8601 datetime
}

interface InvalidFileTypeDetails {
  detectedType: string;            // e.g. 'application/zip' or 'unknown'
  allowedTypes: string[];
}

// ---- GET /objections/:id/sufficiency ----
interface SufficiencyMissingEntry {
  category: ObjectionCategory;
  requiredDocTypes: string[];
}

interface ObjectionSufficiencyResponse {
  objectionId: string;
  sufficient: boolean;
  missing: SufficiencyMissingEntry[]; // empty when sufficient = true
}

// ---- GET /objections/:id/summary ----
interface DisputedItem {
  lineItemId: string;
  label: string;
  chargedAmount: string;           // decimal string
  expectedAmount: string | null;   // nullable decimal string
  category: ObjectionCategory;
}

interface SummaryDocument {
  evidenceId: string;
  filename: string;
  mimeType: string;
}

interface ObjectionSummaryResponse {
  objectionId: string;
  property: { accountNumber: string; address: string };
  billingPeriod: string;
  disputedItems: DisputedItem[];
  documents: SummaryDocument[];
  totalDisputedAmount: string;     // decimal string
}

// ---- POST /objections/:id/submit (async 202) ----
// Response is the shared AsyncJob shape from conventions.md §8:
//   interface AsyncJob { jobId: string; statusUrl: string }

// ---- GET /objections (list) ----
// One lightweight row per objection. Wrapped in Paginated<T> from conventions.md §7.
interface ObjectionSummary {
  refNumber: string;               // ELM-2026-NNNNNN
  category: ObjectionCategory;
  status: ObjectionStatus;
  title: string;                   // short server-composed list label
  propertyLabel: string;           // human-readable address
  createdAt: string;               // ISO 8601 datetime
}
// Response shape: Paginated<ObjectionSummary> (see conventions.md §7).

// ---- GET /objections/:ref/status ----
interface StatusTimelineEntry {
  status: ObjectionStatus;
  at: string;                      // ISO 8601 datetime
  note: string;
}

interface MunicipalityResponse {
  note: string;
  adjustedAmount: string | null;   // nullable decimal string
}

interface ObjectionStatusResponse {
  refNumber: string;               // ELM-2026-NNNNNN
  status: ObjectionStatus;
  submittedAt: string;             // ISO 8601 datetime
  lastUpdatedAt: string;           // ISO 8601 datetime
  statusTimeline: StatusTimelineEntry[];
  disputedItems: DisputedItem[];
  municipalityResponse: MunicipalityResponse | null;
}

// ---- POST /objections/:ref/probe ----
interface ProbeResponse {
  refNumber: string;
  probesSent: number;
  probesRemaining: number;
}

// ---- POST /objections/:ref/escalate ----
interface EscalateResponse {
  refNumber: string;
  escalated: true;                 // client display state, not an ObjectionStatus
}

// ---- POST /objections/:ref/close ----
interface CloseResponse {
  refNumber: string;
  closed: true;                    // client display state, not an ObjectionStatus
}
```

---

## Figma Trace

Maps each route to the screen transition it serves (`docs/screen-inventory.md`).

| Flow | Screen / CTA | Route |
|---|---|---|
| EVIDENCE & CHALLENGE | Select disputed line items + category, save draft | `POST /objections/draft` |
| EVIDENCE & CHALLENGE | Attach evidence (file picker, one file at a time, up to 5) | `POST /objections/:id/evidence` |
| EVIDENCE & CHALLENGE | "Check evidence" → Sufficient evidence? diamond (→ Review Summary / Prompt — Add More Evidence) | `GET /objections/:id/sufficiency` |
| SUBMISSION | Review Summary screen (property, disputed items, documents, total) | `GET /objections/:id/summary` |
| SUBMISSION | "Submit objection" → processing state (async) | `POST /objections/:id/submit` (202; poll `statusUrl`) |
| TRACKING & RESOLUTION | "My objections" list / Tracking overview (filter by status) | `GET /objections` |
| TRACKING & RESOLUTION | Track Objection Status (timeline, municipality response) | `GET /objections/:ref/status` |
| TRACKING & RESOLUTION | "Request status update" CTA | `POST /objections/:ref/probe` |
| TRACKING & RESOLUTION | "Appeal" CTA after a REJECTED decision (display: escalated) | `POST /objections/:ref/escalate` |
| TRACKING & RESOLUTION | "Close case" after UPHELD + adjustment viewed (display: closed) | `POST /objections/:ref/close` |

---

## Rate limits

From `docs/security/rate-limits.md` (Endpoint category table). Every route has an entry.

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/objections/draft` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:id/evidence` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:id/sufficiency` | GET | READ | userId | 1 min | 60 |
| `/objections/:id/summary` | GET | READ | userId | 1 min | 60 |
| `/objections/:id/submit` | POST | SUBMIT | userId | 24 hours | 5 |
| `/objections` | GET | READ | userId | 1 min | 60 |
| `/objections/:ref/status` | GET | READ | userId | 1 min | 60 |
| `/objections/:ref/probe` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:ref/escalate` | POST | WRITE | userId | 1 hour | 20 |
| `/objections/:ref/close` | POST | WRITE | userId | 1 hour | 20 |

Note: `/objections/:ref/probe` carries a **second, business-level** limit beyond the WRITE
limiter above — max 3 probes per objection, one per 24 h — which surfaces as
`429 rate_limit_exceeded` on that route.

On `429`, the body is the standard `rate_limit_exceeded` envelope with
`details.retryAfterSeconds` (conventions §5).
```
