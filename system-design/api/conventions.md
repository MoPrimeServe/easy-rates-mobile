# API Conventions

**Status:** Root contract — every service contract in `api/` conforms to this document.
**Scope:** EasyRates HTTP API, consumed by the Flutter mobile app (sole client).

This is the shared standard. A Flutter developer who reads **only this file** can build a
generic `Dio` response parser, an error interceptor, and a token-refresh interceptor that
work for every endpoint — without opening a single service contract. Each service contract
then specifies only its routes, payloads, and per-route error codes; it never re-states
anything here.

Source-of-truth documents this file consolidates:
- Envelope, error codes, pagination, dates, camelCase — `plans/api-contracts/plans/00-conventions.md`
- Rate-limit categories + 429 shape — `docs/security/rate-limits.md`
- Token model + Dio refresh flow — `docs/security/sessions.md`

---

## 0. Unanswered Questions (resolved)

The completeness test for these contracts: *a Flutter dev who reads only `api/*.md` should
have no question left to ask.* Each question a dev would realistically still raise is listed
here with the **specific contract element** that answers it. If a question below were
unresolved, it would surface as a blocked Flutter screen — so each is closed before any
service contract is opened.

- [x] "On an error, is `data` missing or `null` — what does my model parser branch on?" → resolved by the **§2 envelope biconditional** (`data == null` iff `error != null`; `data` is never absent; empty successes return `"data": {}`, never `204`), so `ApiResponse<T>.fromJson` decides its branch from the body alone.
- [x] "Several responses are `429` / `401` — do I switch on HTTP status or something else?" → resolved by **§2 + §3**: switch on `error.code`, never the HTTP status (three distinct `429`s — `rate_limit_exceeded`, `max_attempts_exceeded`, `resend_cooldown_active` — share a status).
- [x] "How do I paint inline form errors from a 400?" → resolved by the **§4 `validation_error` shape** (`details.fields`: field-name → first message, dot-joined for nested paths like `address.city`).
- [x] "What exactly does my Dio token-refresh interceptor do on a 401?" → resolved by the **§6 401 → `POST /auth/refresh` → retry-once contract** (single-use rotated refresh token in `flutter_secure_storage`, access token in memory; refresh-`401` ⇒ clear both, go to Login).
- [x] "Is money a JSON number? Will I get float rounding?" → resolved by **§9**: money is a **decimal string** (`"1250.00"`), parsed with `Decimal.parse`, never `double`; dates are ISO-8601 UTC strings.
- [x] "How do I page a list and know when to stop?" → resolved by the **§7 `Paginated<T>` shape** (`items`/`page`/`pageSize`/`total`/`totalPages`; request `page+1` while `page < totalPages`; `pageSize` max 100).
- [x] "Objection submit returns `202` — what do I poll, and until when?" → resolved by **§8 `AsyncJob`** (`jobId` + `statusUrl`) and objection-service `GET /objections/:ref/status`; poll `statusUrl` until a terminal `ObjectionStatus`.
- [x] "What are the real field keys — `bill_id` or `billId`?" → resolved by **§10**: all JSON keys are **camelCase** (`billId`, `accountNumber`, `aiExpectedAmount`); snake_case appears **only** inside `error.code`. Models are generated from each contract's TypeScript interface block (§12), never hand-written.
- [x] "I need to show the user's phone/ID — does the API return the full value?" → resolved by the **pre-masked fields in the contracts**: account-service `phoneMasked` / `idNumberMasked`, auth-service `maskedPhone`. The client renders the masked string directly; no client-side masking.
- [x] "The AI expected-amount is sometimes blank — is that an error or empty data?" → resolved by **bill-service**: `aiExpectedAmount` is `null` when `confidence < 0.85` (a valid `200`, not an error); the full `GET /bills/:id/ai-estimate` returns `confidence`, `isStale`, and `503 ai_unavailable` on timeout — each mapped to a defined screen-inventory fallback.

---

## 1. Base URL and versioning

All services sit behind a single origin and share the `/api/v1` path prefix. The host is
environment configuration, never hardcoded in a contract.

| Environment | Base URL |
|---|---|
| Local dev | `http://localhost:8080/api/v1` |
| Pilot | `https://api-pilot.easyrates.co.za/api/v1` |
| Production | `https://api.easyrates.co.za/api/v1` |

Every route in every contract is written **relative to the `/api/v1` prefix**. A contract
that lists `POST /auth/login` means `POST {baseUrl}/auth/login`.

**Flutter:** set the prefix once as the Dio `BaseOptions.baseUrl`. Contracts give the
relative path only.

---

## 2. Response envelope

Every response — success or error, every status code — has the same two-key shape.

```ts
interface ApiResponse<T> {
  data: T | null;     // payload on success; null on error
  error: ApiError | null; // null on success; populated on error
}

interface ApiError {
  code: string;       // snake_case, machine-readable; switch on THIS, not HTTP status
  message: string;    // human-readable; safe to show in the Flutter UI
  details?: Record<string, unknown>; // optional; always an object (never an array); may be {}
}
```

**Success:**
```json
{ "data": { "...": "..." }, "error": null }
```

**Error:**
```json
{ "data": null, "error": { "code": "not_found", "message": "Bill not found.", "details": {} } }
```

Invariants:
- `data` is **never absent** — it is `null` on error.
- `error` is **never absent** — it is `null` on success.
- `data` and `error` are **mutually exclusive and exhaustive**: exactly one is non-null.
  Formally, `data == null` **if and only if** `error != null`. A success therefore **always**
  carries a non-null `data`. An operation with no payload (logout, delete, ack) returns
  `"data": {}` — never `null`, and never a bodiless `204` (the envelope is present on every
  response, §2 opening line). This biconditional is what lets the generic
  `ApiResponse<T>.fromJson` decide its branch from the body alone: `error == null` ⇒ `data` is
  present, parse it as `T`; no need to special-case empty successes or read the HTTP status.
- `error.code` is the contract. The Flutter interceptor switches on `error.code`, **not** on
  the HTTP status, because several codes share a status (e.g. three different `429`s).

**Flutter:** one generic `ApiResponse<T>.fromJson(json, dataParser)` handles every endpoint.
Get the envelope wrong once and you fix it in one place; get it right once and every screen
benefits.

---

## 3. Standard error codes

These codes apply across all services. A service contract lists only the codes specific to it
(e.g. `otp_expired`); it never re-documents these.

| HTTP | `error.code` | Meaning | `details` | Flutter UI state |
|---|---|---|---|---|
| 400 | `validation_error` | Zod request validation failed | `details.fields` (see §4) | Inline field errors |
| 401 | `unauthenticated` | No token, or token expired/invalid | `{}` | Trigger refresh (§6); else Login |
| 403 | `forbidden` | Valid token, not permitted (e.g. resource not owned) | `{}` | "Not available" / back |
| 404 | `not_found` | Resource does not exist | `{}` | Empty / not-found screen |
| 409 | `conflict` | State conflict (e.g. phone already registered) | `{}` | Inline conflict message |
| 422 | `unprocessable` | Well-formed but semantically rejected | varies | Context-specific message |
| 429 | `rate_limit_exceeded` | Generic rate limiter tripped | `details.retryAfterSeconds: int` | Countdown / retry-later |
| 500 | `internal_server_error` | Unexpected server fault (never leaks a stack trace) | `{}` | Generic error + retry |

Service-specific codes (defined in their own contracts): `otp_expired`, `otp_invalid`,
`max_attempts_exceeded`, `resend_cooldown_active`, `invalid_file_type`, `file_missing`.

---

## 4. Validation errors (400) — field-level shape

A `validation_error` carries a `fields` map in `details`: field name → first message for that
field. Nested fields use dot-joined paths (`address.city`).

```json
{
  "data": null,
  "error": {
    "code": "validation_error",
    "message": "One or more fields are invalid.",
    "details": {
      "fields": {
        "phone": "Must be a +27 E.164 number.",
        "password": "At least 8 characters."
      }
    }
  }
}
```

**Flutter:** map each `details.fields` key onto the matching form field to paint inline errors.

---

## 5. Rate limiting

Every endpoint belongs to a rate-limit category (source: `docs/security/rate-limits.md`).
Each contract states its endpoints' categories in a **Rate limits** section. Limiters emit
RFC 9110 `RateLimit-*` headers plus `Retry-After`.

| Category | Scope | Window | Limit |
|---|---|---|---|
| AUTH | IP | 15 min | 10 |
| OTP-VERIFY | phone | 10 min | 10 |
| OTP-SEND | phone | 10 min | 3 |
| READ | userId | 1 min | 60 |
| SEARCH | userId | 1 min | 10 |
| WRITE | userId | 1 hour | 20 |
| SUBMIT | userId | 24 hours | 5 |
| AI | userId | 1 min | 5 |
| SYSTEM (refresh/logout) | IP / userId | 15 min | 30 / 10 |

On 429, the body is the standard `rate_limit_exceeded` envelope and the response carries:

```
RateLimit-Limit: <n>
RateLimit-Remaining: 0
RateLimit-Reset: <epoch-seconds>
Retry-After: <seconds>
```

`details.retryAfterSeconds` mirrors `Retry-After`. **Flutter:** read it to drive a countdown.
(OTP-specific 429s — `max_attempts_exceeded`, `resend_cooldown_active` — use their own
`error.code` and are issued by otp-service, not the generic limiter. Switch on `error.code`.)

---

## 6. Authentication and token refresh

- **Access token:** RS256 JWT, **15-minute** TTL (`ACCESS_TOKEN_TTL_SECONDS = 900`). Sent as
  `Authorization: Bearer <accessToken>`. Stored **in memory only** on the client (never disk).
- **Refresh token:** opaque 256-bit hex, **30-day** TTL, single-use (rotated on every refresh).
  Stored in `flutter_secure_storage`.
- Routes marked `[public]` need no token. All others require the `Authorization` header.

**The 401 → refresh → retry contract (the Dio interceptor builds this once):**

1. Any endpoint returns `401 unauthenticated`.
2. Read the refresh token from secure storage; `POST /auth/refresh`.
3. On `200`: store the new access token (memory) and new refresh token (secure storage);
   **retry the original request once** with the new access token.
4. On refresh `401`: refresh token is expired or a reuse was detected — clear both tokens,
   navigate to Login.

A reused (already-rotated) refresh token revokes the whole token family — see
`docs/security/sessions.md`.

---

## 7. Pagination

List endpoints accept `?page=<int>&pageSize=<int>` (1-indexed page) and return:

```ts
interface Paginated<T> {
  items: T[];      // always an array, never null
  page: number;
  pageSize: number;
  total: number;     // total before pagination
  totalPages: number; // ceil(total / pageSize)
}
```

```json
{ "data": { "items": [], "page": 1, "pageSize": 20, "total": 142, "totalPages": 8 }, "error": null }
```

Defaults: `page=1`, `pageSize=20` (max `pageSize=100`).
**Flutter:** request `page + 1` while `page < totalPages`.

---

## 8. Async operations (202)

Long-running operations return `202 Accepted` with a job handle and a URL to poll.

```ts
interface AsyncJob {
  jobId: string;
  statusUrl: string; // relative path to poll for the result
}
```

```json
{ "data": { "jobId": "clx...", "statusUrl": "/api/v1/objections/clx..." }, "error": null }
```

**Flutter:** on `202`, show a "processing" state and poll `statusUrl` until the resource
reaches a terminal state. Used by objection submission.

---

## 9. Dates and money

- **Date:** `"2026-06-15"` (ISO 8601 `YYYY-MM-DD`, UTC).
- **Datetime:** `"2026-06-15T10:30:00.000Z"` (ISO 8601, milliseconds, `Z`). Always UTC on the
  wire; convert to local in the Flutter UI. Parse with `DateTime.parse(...)`.
- **Money:** a **decimal string**, not a JSON number — e.g. `"1250.00"`. Backend `Decimal`
  (Prisma) serializes to string to avoid float rounding. **Flutter:** parse with
  `Decimal.parse(...)` (package `decimal`), never `double`. Always 2 fraction digits, ZAR.

---

## 10. Field naming and TypeScript conventions

- All JSON field names are **camelCase**: `billId`, `accountNumber`, `billingPeriod`,
  `aiExpectedAmount`, `ttlSeconds`, `resendCooldownSeconds`, `maxFileSizeBytes`,
  `acceptedMimeTypes`. Never `bill_id`, `account_number` (snake_case appears **only** inside
  `error.code` values).
- TypeScript: **PascalCase** for interfaces/types (`BillResponse`, `ObjectionCreateRequest`),
  **camelCase** for fields. Request types end `…Request`; response types end `…Response`.
- Every contract includes a **TypeScript interfaces** block. These interfaces are not copied
  into Dart by hand — they are the source the Flutter models are **generated** from (§12), and
  the source the backend serializers are validated against in CI.
- Every contract includes a **Figma Trace** section mapping each route to the screen
  transitions it serves.

---

## 11. Contract file structure (every service contract follows this)

1. Header — service name, base path, auth requirement.
2. One section per route: method + path, request (table + JSON), success response (JSON in
   envelope), error codes (table).
3. **TypeScript interfaces** — request/response types for the whole service.
4. **Figma Trace** — screen transition → route, for every route.
5. **Rate limits** — category per endpoint (from `docs/security/rate-limits.md`).

---

## 12. Contract generation (contract-first)

Every rule above (envelope, error codes, dates, money, camelCase) prevents an integration bug
**at definition time only if the contract is decided before either side writes code, and both
sides generate from it.** A rule defended by prose alone is defended by developer vigilance,
which eventually lapses — and the worst lapse (a casing mismatch) fails *silently*:
`json['accountNumber']` against a wire `account_number` returns `null`, not an error.

**Contract-first, not backend-first.** The contract (this file + the service contracts'
TypeScript interfaces) is agreed **before** the route is built. The backend does not ship and
let the wire shape become the contract by accident; the contract is the input to both sides.

| Aspect | Backend-first | Contract-first |
|---|---|---|
| Contract is | a description of what the backend emitted | the agreed input to both sides |
| Mismatch surfaces | at integration (debug time, prod) | at codegen / CI (definition time) |
| Casing slip | silent runtime `null` | compile / generation failure |

**Both sides generate from the one contract:**

- **Flutter:** models are **generated** (`freezed` / `json_serializable` via `build_runner`)
  from the contract's TypeScript interfaces — not hand-written. The wire key for each field is
  declared once (`@JsonKey(name: ...)` where it differs); a casing change regenerates the model
  with zero hand edits. **Do not hand-write model classes. Do not access `json['key']` directly
  anywhere outside generated code** — that is the only place a silent casing null can enter.
- **Backend:** serializers are validated against the same interfaces in CI; a drift fails the
  build, not a Flutter screen.

What generation cannot enforce — and so stays a prose rule above — is **semantics**: UTC-only
datetimes (§9), money as a decimal string never a `double` (§9), the single envelope-unwrap
point and switch-on-`error.code` (§2), and the closed error-code set (§3). The schema fixes the
*shape*; this document fixes the *meaning*.
