# Account Service — API Contract

**Service:** account-service
**Base path:** `/account` (relative to the `/api/v1` prefix — see `api/conventions.md`)
**Auth:** **All routes require authentication.** Every route sends `Authorization: Bearer <accessToken>`; a missing/expired token returns `401 unauthenticated` and the Dio interceptor runs the refresh flow (conventions §6).

Conforms to `api/conventions.md`: the `{data,error}` envelope (§2), standard error codes (§3 — not re-documented here), pagination (§7), ISO 8601 dates (§9), money as decimal strings (§9), camelCase fields and PascalCase TypeScript types (§10).

> **Deferred (not in this contract):** Profile PATCH and change-password (MASTER_PLAN G4) are deferred — no Figma screen supports self-serve profile edits in MVP; included here they would be reverse orphans. Tracked for a later phase.

**Central resolutions used here:** `ObjectionStatus` has exactly 4 values (`UNDER_REVIEW` | `MORE_INFO_REQUESTED` | `UPHELD` | `REJECTED`); `refNumber` format is `ELM-2026-NNNNNN`; money is a decimal string; profile is read-only for MVP.

---

## GET /account/profile  (READ)

The signed-in user's profile. **Read-only for MVP** — the Profile Settings screen exposes no self-serve edits ("changes via support"). No write counterpart exists.

**Request:** no body, no query parameters.

**Success — 200:**

```json
{
  "data": {
    "userId": "clx9a0b1c2d3e4f5g6h7i8j9",
    "displayName": "Thabo Mokoena",
    "email": "thabo@example.co.za",
    "phoneMasked": "+27 82 XXX X234",
    "idNumberMasked": "8•••••••••••89"
  },
  "error": null
}
```

**Errors:** `401`.

---

## GET /account/properties  (READ)

The list of properties linked to the signed-in user, for the Manage Linked Properties screen.

> **Cross-reference:** Linking a *new* property is **`POST /property/link`** in `api/property-service.md` (the FIND PROPERTY flow ends there on "Save"). It is **not** duplicated here. This service only lists and unlinks.

**Request:** no body, no query parameters.

**Success — 200:** an array of linked properties.

```json
{
  "data": [
    {
      "id": "clx_link_001",
      "accountNumber": "10234567",
      "address": "12 Vaal Street, Vereeniging",
      "erfNumber": "ERF-4421",
      "ward": "Ward 21",
      "status": "ACTIVE",
      "linkedAt": "2026-05-02T08:15:00.000Z"
    }
  ],
  "error": null
}
```

Notes:
- `status` is the `AccountStatus` of the link (`ACTIVE` | `INACTIVE` | `ARCHIVED`, per `docs/data-model/property-account.md`); the UI renders it as a status chip.
- `erfNumber` may be `null` (Property.erfNumber is optional in the data model).
- `linkedAt` is an ISO 8601 datetime.

**Errors:** `401`.

---

## DELETE /account/properties/:id  (WRITE)

Unlink a property from the signed-in user (Manage Linked Properties → "Remove"). Removes the user–property link; it does **not** delete the underlying Property (the municipality is the authority for Property records).

**Path parameters:**

| Name | Type | Notes |
|---|---|---|
| `id` | string | The linked-property id from `GET /account/properties` (`item.id`). |

**Request:** no body.

**Success — 204 No Content:** **no response body.** This is the envelope exception noted in conventions: a `204` carries no `{data,error}` payload. The Flutter client treats any `2xx` with an empty body as success and removes the row.

**Errors:** `401`; `403` (`forbidden` — the link is not owned by the caller); `404` (`not_found` — no such linked property).

---

## GET /account/preferences  (READ)

The signed-in user's notification preferences, for the Notification Preferences screen.

> **MVP note (screen-inventory):** email and SMS are **always on** for MVP — the toggle UI is scaffold only. These fields are returned so the scaffold can render, but the backend dispatches both channels regardless of the stored values in MVP.

**Request:** no body, no query parameters.

**Success — 200:**

```json
{
  "data": {
    "smsEnabled": true,
    "pushEnabled": true,
    "emailEnabled": true,
    "language": "en"
  },
  "error": null
}
```

Notes:
- `language` is one of `en` | `zu` | `af` | `st`.

**Errors:** `401`.

---

## PUT /account/preferences  (WRITE)

Partial update of notification preferences. Any **subset** of the preference fields may be sent; omitted fields are left unchanged.

**Request body:** any subset of the four fields.

| Field | Type | Required | Notes |
|---|---|---|---|
| `smsEnabled` | boolean | No | |
| `pushEnabled` | boolean | No | |
| `emailEnabled` | boolean | No | |
| `language` | string | No | One of `en` \| `zu` \| `af` \| `st`. |

```json
{ "language": "zu", "pushEnabled": false }
```

**Success — 200:** the **full** updated preferences object (same shape as `GET /account/preferences`).

```json
{
  "data": {
    "smsEnabled": true,
    "pushEnabled": false,
    "emailEnabled": true,
    "language": "zu"
  },
  "error": null
}
```

**Errors:**
- `400` `validation_error` — an unknown `language` value (not one of `en|zu|af|st`); carries `details.fields.language` per conventions §4.
- `401`.

---

## GET /account/objections  (READ)

The **History of Objections** list (Account & Settings → History). Read-only; tapping a row deep-links to Track Objection Status by `refNumber`. **Paginated** per conventions §7.

**Query parameters:**

| Name | Type | Required | Notes |
|---|---|---|---|
| `page` | int | No | 1-indexed. Default `1`. |
| `pageSize` | int | No | Default `20`, max `100`. |

**Success — 200:** a `Paginated<ObjectionHistoryItem>` envelope (conventions §7).

```json
{
  "data": {
    "items": [
      {
        "refNumber": "ELM-2026-000142",
        "propertyAddress": "12 Vaal Street, Vereeniging",
        "accountNumber": "10234567",
        "submittedAt": "2026-06-10T09:30:00.000Z",
        "status": "UNDER_REVIEW",
        "disputedAmount": "1250.00"
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

Notes:
- `refNumber` format: `ELM-2026-NNNNNN`.
- `status` is one of the 4 `ObjectionStatus` values: `UNDER_REVIEW` | `MORE_INFO_REQUESTED` | `UPHELD` | `REJECTED`.
- `disputedAmount` is a decimal string (ZAR, 2 fraction digits).

**Errors:**
- `400` `validation_error` — invalid pagination params (e.g. `pageSize` > 100).
- `401`.

---

## TypeScript interfaces

```ts
// ---- GET /account/profile ----
interface AccountProfileResponse {
  userId: string;
  displayName: string;
  email: string;
  phoneMasked: string;      // e.g. "+27 82 XXX X234"
  idNumberMasked: string;   // e.g. "8•••••••••••89"
}

// ---- GET /account/properties ----
type AccountStatus = "ACTIVE" | "INACTIVE" | "ARCHIVED";

interface LinkedPropertyResponse {
  id: string;               // linked-property id; used by DELETE /account/properties/:id
  accountNumber: string;
  address: string;
  erfNumber: string | null;
  ward: string;
  status: AccountStatus;
  linkedAt: string;         // ISO 8601 datetime
}

type AccountPropertiesResponse = LinkedPropertyResponse[];

// DELETE /account/properties/:id -> 204 No Content, no body.

// ---- GET /account/preferences ----
type PreferenceLanguage = "en" | "zu" | "af" | "st";

interface AccountPreferencesResponse {
  smsEnabled: boolean;
  pushEnabled: boolean;
  emailEnabled: boolean;
  language: PreferenceLanguage;
}

// ---- PUT /account/preferences ----
interface AccountPreferencesUpdateRequest {
  smsEnabled?: boolean;
  pushEnabled?: boolean;
  emailEnabled?: boolean;
  language?: PreferenceLanguage;
}
// Response: AccountPreferencesResponse (full updated object).

// ---- GET /account/objections ----
type ObjectionStatus =
  | "UNDER_REVIEW"
  | "MORE_INFO_REQUESTED"
  | "UPHELD"
  | "REJECTED";

interface ObjectionHistoryItem {
  refNumber: string;        // format ELM-2026-NNNNNN
  propertyAddress: string;
  accountNumber: string;
  submittedAt: string;      // ISO 8601 datetime
  status: ObjectionStatus;
  disputedAmount: string;   // decimal string, ZAR
}

// Paginated<ObjectionHistoryItem> per conventions §7.
```

---

## Figma Trace

| Screen (screen-inventory ACCOUNT & SETTINGS) | Transition / action | Route |
|---|---|---|
| **Profile Settings** | Screen load (`loading` → `loaded`) | `GET /account/profile` |
| **Manage Linked Properties** | Screen load — list linked properties (`loading` → `loaded` / `empty`) | `GET /account/properties` |
| **Manage Linked Properties** | "Add property" CTA → FIND PROPERTY entry | `POST /property/link` (property-service — cross-reference, not in this contract) |
| **Manage Linked Properties** | "Remove" → unlinks UserProperty | `DELETE /account/properties/:id` |
| **Notification Preferences** | Screen load (`loading` → `loaded`) | `GET /account/preferences` |
| **Notification Preferences** | "Save" (scaffold only for MVP) | `PUT /account/preferences` |
| **History of Objections** | Screen load — list all objections (`loading` → `loaded` / `empty`) | `GET /account/objections` |
| **History of Objections** | Tap row → Track Objection Status | (deep-link by `refNumber` → status-service `GET /objections/:ref/status`) |
| **Log Out** | "Log out" confirm → clears tokens, → App Launch | `POST /auth/logout` (auth-service — cross-reference, not in this contract) |

---

## Rate limits

From `docs/security/rate-limits.md` (Endpoint category table). Every endpoint in this contract has an entry — 0 gaps.

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/account/profile` | GET | READ | userId | 1 min | 60 |
| `/account/properties` | GET | READ | userId | 1 min | 60 |
| `/account/properties/:id` | DELETE | WRITE | userId | 1 hour | 20 |
| `/account/preferences` | GET | READ | userId | 1 min | 60 |
| `/account/preferences` | PUT | WRITE | userId | 1 hour | 20 |
| `/account/objections` | GET | READ | userId | 1 min | 60 |

On 429, the response is the standard `rate_limit_exceeded` envelope with `details.retryAfterSeconds` (conventions §5).
