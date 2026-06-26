# Municipality Service — API Contract

**Service:** municipality-service
**Base path:** `/municipality` (relative to the `/api/v1` prefix — see `api/conventions.md`)
**Auth:** **Webhook-secret, NOT a JWT.** The single route is authenticated by the header `X-Municipal-Webhook-Secret`. There is no `Authorization: Bearer` token and no Dio refresh flow — **this contract is not consumed by the Flutter app.**

This is the **CRM ingestion webhook**: the back-office / municipal system pushes objection resolutions **in**. It absorbs the former status-service `POST /status/:ref/response` webhook. The Flutter app reads resolution outcomes through status-service polling / FCM push — never through this endpoint.

Conforms to `api/conventions.md`: the `{data,error}` envelope (§2), standard error codes (§3 — not re-documented here), ISO 8601 dates (§9), money as decimal strings (§9), camelCase fields and PascalCase TypeScript types (§10). The exception is **authentication**: §6 (JWT + refresh) does not apply — see the note on `401` below.

**Central resolutions used here:** `ObjectionStatus` has exactly 4 values (`UNDER_REVIEW` | `MORE_INFO_REQUESTED` | `UPHELD` | `REJECTED`); `refNumber` format is `ELM-2026-NNNNNN`; `adjustedAmount` is a decimal string; webhook auth is `X-Municipal-Webhook-Secret` (not a JWT).

---

## POST /municipality/objections/:ref/response  `[internal — municipal webhook]`

The municipal back-office system pushes a resolution for an objection it has reviewed. This is the **only** route in this service. Authenticated by the `X-Municipal-Webhook-Secret` header; **no bearer token.**

**Path parameters:**

| Name | Type | Notes |
|---|---|---|
| `ref` | string | The objection `refNumber`, format `ELM-2026-NNNNNN`. Resolves to the `Objection` row (`Objection.refNumber` is `@unique`). |

**Headers:**

| Header | Required | Notes |
|---|---|---|
| `X-Municipal-Webhook-Secret` | Yes | Shared secret for the municipal webhook. Missing/invalid → `401`. This is the **only** credential; there is no `Authorization` header. |

**Request body:**

| Field | Type | Required | Notes |
|---|---|---|---|
| `status` | string | Yes | One of the 4 `ObjectionStatus` values: `UNDER_REVIEW` \| `MORE_INFO_REQUESTED` \| `UPHELD` \| `REJECTED`. The new status the municipality is setting. |
| `note` | string | Yes | 10–1000 chars. The municipality's written justification — **shown to the resident** (verbatim) on the Tracking screens. |
| `adjustedAmount` | string | No | Decimal string (ZAR, 2 fraction digits). Set when `UPHELD` **with an adjustment**. Omit otherwise. |
| `resolvedBy` | string | Yes | Clerk id — audit only; not shown to the resident. |
| `idempotencyKey` | string | **Yes** | Dedupes retried webhook deliveries. See **Idempotency** below. |

```json
{
  "status": "UPHELD",
  "note": "Meter photo confirms the reading was over-estimated. Charge reduced to the corrected consumption.",
  "adjustedAmount": "812.50",
  "resolvedBy": "clerk-4417",
  "idempotencyKey": "muni-evt-9f3a1c7e"
}
```

### Side effects

On a successful (non-duplicate) call the service performs, in order:

1. **INSERT `MunicipalityResponse`** — `{ objectionId, status, note, adjustedAmount, respondedAt }`. **All** responses are logged for audit, even when they do not change `Objection.status` (see State transition rules).
2. **UPDATE `Objection.status`** — set to the incoming `status`, subject to the State transition rules below.
3. **Enqueue notification dispatch** — a BullMQ `objection.status_changed` event; notification-service fans out **SMS + PUSH + EMAIL** to the resident (`OBJECTION_STATUS`, or `MORE_INFO_REQUESTED` type).

**Transactionality:** **steps 1–2 are a single database transaction** (matching `docs/data-model/notification.md`). **Step 3 is async** — enqueued only after the transaction commits; the BullMQ consumer dispatches the channels. A `Notification` row may therefore lag the status change by a few seconds. The `200` returns `notificationQueued: true` to mean *enqueued*, not *delivered*.

**Success — 200:**

```json
{
  "data": {
    "refNumber": "ELM-2026-000142",
    "status": "UPHELD",
    "notificationQueued": true
  },
  "error": null
}
```

**Errors:**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | Body failed validation — unknown `status`, `note` outside 10–1000 chars, malformed `adjustedAmount`, missing `idempotencyKey`/`resolvedBy`. Carries `details.fields` (conventions §4). |
| 401 | `unauthenticated` | Missing/invalid `X-Municipal-Webhook-Secret`. **Note:** same `401`/`unauthenticated` code as conventions §3, but here the credential is the **webhook secret**, not a bearer token — the Dio refresh flow does **not** apply (no Flutter client calls this route). |
| 404 | `not_found` | No `Objection` matches `refNumber`. |
| 409 | `conflict` | Terminal-state guard — the objection is already `UPHELD` or `REJECTED` and the incoming status would re-open it. The `MunicipalityResponse` is still INSERTed for audit (step 1), but `Objection.status` is **not** changed and no notification is enqueued. Re-opening a closed case requires an explicit service-level guard. Carries `details: { currentStatus, requestedStatus }` (same shape as the `422` — see below). |
| 422 | `unprocessable` | Illegal (but non-terminal) state transition — e.g. `UNDER_REVIEW → UNDER_REVIEW`, or any transition not in the table below that is not a terminal-reopen. Carries `details: { currentStatus, requestedStatus }` (both `ObjectionStatus`) — see below. |

**`422` / `409` `details` shape.** Both the illegal-transition (`422 unprocessable`) and the terminal-reopen (`409 conflict`) responses carry a `details` object naming exactly which transition was rejected, so the caller and the audit log see the `currentStatus` it found on the `Objection` and the `requestedStatus` the webhook asked for — both drawn from the 4-value `ObjectionStatus` enum:

```json
{
  "data": null,
  "error": {
    "code": "unprocessable",
    "message": "Illegal state transition for objection ELM-2026-000142.",
    "details": {
      "currentStatus": "UNDER_REVIEW",
      "requestedStatus": "UNDER_REVIEW"
    }
  }
}
```

The `409 conflict` body is identical in shape — `error.code` is `conflict` and `currentStatus` is the terminal value (`UPHELD` or `REJECTED`):

```json
{
  "data": null,
  "error": {
    "code": "conflict",
    "message": "Objection ELM-2026-000142 is terminal and cannot be re-opened.",
    "details": {
      "currentStatus": "REJECTED",
      "requestedStatus": "UPHELD"
    }
  }
}
```

---

## State transition rules

The four `ObjectionStatus` values and the transitions this webhook may apply, feeding the TRACKING & RESOLUTION flow:

| From | Allowed `→` to |
|---|---|
| `UNDER_REVIEW` | `MORE_INFO_REQUESTED`, `UPHELD`, `REJECTED` |
| `MORE_INFO_REQUESTED` | `UNDER_REVIEW`, `UPHELD`, `REJECTED` |
| `UPHELD` | **terminal** |
| `REJECTED` | **terminal** |

- `UPHELD` and `REJECTED` are **terminal**. A webhook that targets an already-terminal objection hits the terminal-state guard and returns **`409 conflict`**; re-opening requires an explicit service-level guard.
- A transition that is neither allowed above nor a terminal-reopen (e.g. a no-op `UNDER_REVIEW → UNDER_REVIEW`, or `MORE_INFO_REQUESTED → MORE_INFO_REQUESTED`) returns **`422 unprocessable`**.
- **Duplicate-handling (audit):** **every** response is logged via INSERT (step 1) for audit — even on `409` (terminal guard) and even when the status does not change. Only step 2 (the `Objection.status` UPDATE) and step 3 (notification) are gated by the rules. This matches the "Duplicate status update handling" note in `docs/data-model/notification.md`.

---

## Idempotency

Webhook deliveries are retried by the municipal system on timeout or network failure, so the same logical resolution may arrive more than once.

- `idempotencyKey` is **required** on every call.
- A retried delivery carrying an `idempotencyKey` **already seen** returns the **original `200` result** (same `refNumber`, `status`, `notificationQueued: true`) **without re-applying any side effect** — no second `MunicipalityResponse` INSERT, no second `Objection.status` UPDATE, no second notification enqueue.
- This is distinct from duplicate-status handling above: a *different* `idempotencyKey` carrying the same status is **not** a retry — it is a new response and is logged (INSERT) for audit, then gated by the State transition rules.

**Retention (TTL): 30 days.** The dedup store keyed by `idempotencyKey` (Redis, or equivalently the `MunicipalityResponse` table keyed by `idempotencyKey`) retains each key for **30 days** from first receipt.

- **Within the TTL:** a re-delivered key returns the **original `200`** result and applies **no side effect** (as above).
- **After the TTL:** the key may be evicted. A re-delivery arriving this late is **not expected** — the municipal system's retry/re-delivery window is far shorter — so if an evicted key were to reappear it would be treated as a new response and gated by the State transition rules (in practice the terminal-state guard, since the objection has long since resolved).
- **Why 30 days:** it comfortably covers the realistic municipal re-delivery / retry window (timeouts, network failures, back-office replays) with margin, and aligns the dedup horizon with the audit-retention need — every `MunicipalityResponse` is logged for audit, so keeping the key for the same period keeps the dedup decision and its audit trail consistent.

---

## TypeScript interfaces

```ts
type ObjectionStatus =
  | "UNDER_REVIEW"
  | "MORE_INFO_REQUESTED"
  | "UPHELD"
  | "REJECTED";

// ---- POST /municipality/objections/:ref/response ----
// Auth: header X-Municipal-Webhook-Secret (NOT a JWT). Path param: ref (ELM-2026-NNNNNN).
interface MunicipalityResponseWebhookRequest {
  status: ObjectionStatus;     // the new status the municipality is setting
  note: string;                // 10-1000 chars; shown to the resident
  adjustedAmount?: string;     // decimal string, ZAR; set when UPHELD with an adjustment
  resolvedBy: string;          // clerk id — audit only
  idempotencyKey: string;      // REQUIRED — dedupes retried webhooks
}

interface MunicipalityResponseWebhookResponse {
  refNumber: string;           // format ELM-2026-NNNNNN
  status: ObjectionStatus;     // the status now on the Objection
  notificationQueued: true;    // BullMQ enqueue accepted (not "delivered")
}

// error.details on 422 `unprocessable` (illegal/no-op transition) and
// 409 `conflict` (terminal-state re-open) — names the rejected transition.
interface StateTransitionErrorDetails {
  currentStatus: ObjectionStatus;    // the status currently on the Objection
  requestedStatus: ObjectionStatus;  // the status the webhook asked to set
}
```

---

## Figma Trace

This single webhook is the **upstream driver** of the TRACKING & RESOLUTION flow. It renders no screen itself (the Flutter app does not call it); instead, the status it writes is what the resident's `Status?` diamond reads on next poll / push, and the notification it enqueues is the deep-link delivery. Mapping the one route to the downstream screen transitions it causes:

| Incoming `status` | `Status?` branch (status-service, next poll) | Resident screen reached | Notification (BullMQ → notification-service) |
|---|---|---|---|
| `UNDER_REVIEW` | Pending branch | ⏳ Under Review by Municipality | OBJECTION_STATUS → re-poll loop |
| `MORE_INFO_REQUESTED` | More Info branch | 🔁 More Info Requested | MORE_INFO_REQUESTED → SMS + PUSH + EMAIL, deep-link to 🔁 More Info Requested |
| `UPHELD` | Upheld branch | ✅ Objection Upheld → View Adjusted Bill / Credit (`adjustedAmount`) | OBJECTION_STATUS → SMS + PUSH + EMAIL, deep-link to ✅ Objection Upheld |
| `REJECTED` | Rejected branch | ❌ Objection Rejected | OBJECTION_STATUS → SMS + PUSH + EMAIL, deep-link to ❌ Objection Rejected |
| (notification dispatch, all of the above) | — | Notification Sent to User → re-polls `Status?` | the SMS + PUSH + EMAIL fan-out is the enqueued step 3 |

Note: `note` is the verbatim text surfaced as the "municipality's request text" / "rejection reason" / upheld justification on those screens; `adjustedAmount` populates the adjusted-amount field on ✅ Objection Upheld / View Adjusted Bill / Credit.

---

## Rate limits

**Internal webhook — not subject to the Flutter-client rate-limit categories** in `docs/security/rate-limits.md` (conventions §5). It is not called by a `userId`-scoped client, so the READ / WRITE / SUBMIT / AI categories do not apply.

Instead it is secured by:
- the `X-Municipal-Webhook-Secret` shared secret, and
- a **source-IP allowlist** (the municipal back-office origin).

No `RateLimit-*` headers and no `429 rate_limit_exceeded` envelope are emitted on this route.
