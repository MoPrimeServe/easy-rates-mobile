# 🏛️ Municipality CRM Ingestion Contract

## Background

⛔ BLOCKED[Gate] — requires plan/00-conventions.md WRITE task.
⛔ BLOCKED[Gate] — requires data-model sub-scope plan/05-notification.md WRITE
task (MunicipalityResponse schema defined; state-transition model documented).
⛔ BLOCKED[Gate] — requires plan/06-objection-service.md WRITE task (Objection
status values and transitions defined).

The municipality service is a server-to-server endpoint. The municipality's CRM
sends a webhook when it updates an objection's status. This is NOT a Flutter-facing
endpoint. It feeds the TRACKING & RESOLUTION Figma flow by updating Objection status
and creating MunicipalityResponse records.

## Description

Write the HTTP API contract for the municipality CRM ingestion webhook: authentication
mechanism, idempotency key, payload shape, state transition rules. Includes TypeScript
interface for the webhook payload.

## Purpose

To answer: "what happens to the objection tracking flow if the municipality CRM
sends a duplicate status update — and does the API handle it idempotently so the
Flutter tracking screen doesn't show the wrong status?"

## Goal

`easy_rates/system-design/api/municipality-service.md` — POST webhook route with
authentication mechanism, idempotency, state transition rules, TypeScript interface.

## Tasks

- [x] ✅ THINK `/socratic "The municipality CRM sends a webhook when an objection
  status changes. What happens if it sends the same update twice — maybe due to a
  network retry? What happens if it sends an invalid state transition (e.g. trying
  to move a REJECTED objection to UPHELD)? And how does the EasyRates backend
  authenticate the municipality's CRM webhook — shared secret, API key, or something
  else?"` — ✓ verified (Idempotency § states retry on already-seen `idempotencyKey`
  returns original 200 with no side effects; invalid transition → 422, terminal-reopen
  → 409; auth = `X-Municipal-Webhook-Secret` shared secret)
  Done when: duplicate-update idempotency approach is stated; invalid-transition
  handling is defined; authentication mechanism is chosen.

- [x] ✅ FIGMA-TRACE Map TRACKING & RESOLUTION transitions driven by municipality
  CRM updates:
  Municipality updates CRM → POST /api/v1/municipality/objection-update (webhook)
  EasyRates updates Objection.status → Notification created → push sent
  Flutter tracking screen polls or receives push → shows updated status
  For each: the state transition triggered; which Notification is created.
  — ✓ verified (Figma Trace § table maps each of the 4 incoming statuses to its
  `Status?` branch, resident screen, and BullMQ → notification-service fan-out;
  webhook documented as upstream driver, status-service polling/FCM is the read path)
  Done when: full CRM-to-Flutter-screen chain documented.

- [x] ✅ AUTH Define the webhook authentication mechanism:
  Option A: Shared secret in `X-Municipality-Secret` header — EasyRates verifies
  the secret against an env variable. Simple; rotation requires coordination.
  Option B: API key per municipality — EasyRates issues an API key to each
  municipality CRM system; key is in `Authorization: Bearer <key>` header.
  Option C: HMAC signature — CRM signs the request body with a shared key;
  EasyRates verifies the signature.
  Choose one. Justify (ops complexity, municipality IT capability, key rotation).
  — ✓ verified (Option A chosen — shared secret in header, reconciled to
  `X-Municipal-Webhook-Secret`; env var `MUNICIPAL_WEBHOOK_SECRET` (.env.example
  line 52); justified as simplest for municipal IT, not a JWT, rotated out-of-band;
  source-IP allowlist added as defence-in-depth)
  Done when: authentication mechanism chosen with justification; env variable
  name for the secret/key stated.

- [x] ✅ PAYLOAD Define `POST /api/v1/municipality/objection-update`:
  Request (webhook payload):
  ```typescript
  interface MunicipalityWebhookPayload {
    idempotencyKey: string;  // CRM-generated; EasyRates deduplicates on this
    objectionReferenceNumber: string;  // matches Objection.referenceNumber
    newStatus: "UNDER_REVIEW" | "UPHELD" | "REJECTED" | "MORE_INFO_REQUESTED";
    responseText?: string;
    respondedAt: string;   // ISO 8601; the municipality's response timestamp
  }
  ```
  Response 200 (processed): `{ data: { objectionId: string, newStatus: string }, error: null }`
  Response 200 (duplicate, already processed): `{ data: { alreadyProcessed: true }, error: null }`
  Response 422 (invalid transition): `{ data: null, error: { code: "invalid_state_transition",
    message: "...", details: { currentStatus: string, requestedStatus: string } } }`
  — ✓ verified (route `POST /municipality/objections/:ref/response` with `ref` path
  param and full request-body table + JSON example; `idempotencyKey` REQUIRED with
  dedup stated; invalid transition → 422 `unprocessable`, terminal-reopen → 409
  `conflict`. DEVIATION: route shape and error codes differ from the plan's literal
  draft — deliverable uses path-param `ref` not body `objectionReferenceNumber`, and
  `unprocessable`/`conflict` not `invalid_state_transition`. The plan's required
  `details.{currentStatus, requestedStatus}` object IS now present on the 422
  `unprocessable` response (and the same shape on the 409 `conflict`), with a JSON
  example for each and a `StateTransitionErrorDetails` TS interface — gap-filled
  2026-06-27)
  Done when: idempotencyKey deduplication approach stated; invalid-transition
  response defined.

- [x] ✅ STATE-TRANSITIONS Define the allowed state transitions: — ✓ verified (state-transition table in municipality-service.md; UPHELD/REJECTED terminal; illegal→422, terminal-reopen→409)
  UNDER_REVIEW → UPHELD (valid)
  UNDER_REVIEW → REJECTED (valid)
  UNDER_REVIEW → MORE_INFO_REQUESTED (valid)
  MORE_INFO_REQUESTED → UNDER_REVIEW (valid — user supplied more info)
  MORE_INFO_REQUESTED → UPHELD (valid — municipality may uphold without re-review)
  MORE_INFO_REQUESTED → REJECTED (valid)
  UPHELD → * (invalid — terminal state; no transitions out of UPHELD)
  REJECTED → * (invalid — terminal state; no transitions out of REJECTED)
  State these rules in the contract. The backend enforces them and returns 422
  on invalid transition.
  — ✓ verified (State transition rules § table: UNDER_REVIEW and
  MORE_INFO_REQUESTED each → {the other, UPHELD, REJECTED}; UPHELD/REJECTED marked
  terminal; non-allowed non-terminal transitions → 422, terminal-reopen → 409;
  every response INSERTed for audit regardless)
  Done when: transition table complete; terminal states identified.

- [x] ✅ IDEMPOTENCY Define the idempotency mechanism:
  EasyRates checks `idempotencyKey` against the MunicipalityResponse table
  before processing. If the key is already in the table, return the
  "already processed" response immediately without writing.
  TTL for idempotency keys: how long should EasyRates remember a key?
  (e.g. 30 days — after which a duplicate would be re-processed if the CRM
  retried a very old event. State the TTL and justify.)
  — ✓ verified (Idempotency § — dedup on already-seen `idempotencyKey`, returns
  original 200 with no side effects; **TTL = 30 days** now stated and justified:
  Redis-or-`MunicipalityResponse`-table store keyed by `idempotencyKey`, retained
  30 days from first receipt — within-TTL re-delivery returns the original 200 with
  no side effect, after-TTL the key may be evicted (late re-delivery not expected);
  justified by the realistic municipal re-delivery/retry window plus audit-retention
  alignment — gap-filled 2026-06-27)
  Done when: idempotency mechanism described; TTL stated.

- [x] ✅ WRITE Write `easy_rates/system-design/api/municipality-service.md`:
  1 webhook route; authentication mechanism; idempotency; state transition table;
  TypeScript interface.
  — ✓ verified (file exists; 1 webhook route `POST /municipality/objections/:ref/response`;
  `X-Municipal-Webhook-Secret` auth; Idempotency §; State transition rules § table;
  `MunicipalityResponseWebhookRequest`/`Response` TS interfaces present)
  Done when: file exists; authentication mechanism chosen; transition table complete.

- [x] ✅ VERIFY Confirm: ObjectionStatus values in the transition table match
  data-model/objection.md enum exactly (4 values, no extras).
  Confirm: authentication mechanism matches the env variable in container-topology
  plan/08 `.env.example`.
  — ✓ verified (docs/data-model/objection.md lines 23–27 enum = UNDER_REVIEW,
  MORE_INFO_REQUESTED, UPHELD, REJECTED — exactly the 4 in the deliverable's table,
  no extras. Auth: deliverable's `X-Municipal-Webhook-Secret` / `MUNICIPAL_WEBHOOK_SECRET`
  matches .env.example lines 48–52 and container-topology plan/08 line 278)
  Done when: both confirmations pass.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "duplicate update + invalid transition" question
   forces both idempotency and state machine correctness to be designed before
   implementation.
   — custom for contract writing.

## Engagement Instructions

Pass condition: authentication mechanism chosen and documented with env variable name. ✅ resolved
Pass condition: idempotency mechanism described with deduplication approach and TTL. ✅ resolved — dedup described; TTL = 30 days stated and justified.
Pass condition: state transition table shows all valid transitions and names the
terminal states (UPHELD, REJECTED). ✅ resolved
Pass condition: 422 invalid-transition response defined with `currentStatus` and
`requestedStatus` in details. ✅ resolved — 422 `unprocessable` (and 409 `conflict`) now carry `details.{currentStatus, requestedStatus}` with JSON examples and a `StateTransitionErrorDetails` TS interface.
Pass condition: webhook payload TypeScript interface has `idempotencyKey` field. ✅ resolved

## Execution Note — 2026-06-27

Executed against deliverable `easy_rates/system-design/api/municipality-service.md`. Per-task evidence is inline above. Cross-references checked against `docs/data-model/objection.md` and `.env.example`.

**Gap-fill 2026-06-27:** closed both honest gaps — added the 30-day idempotency-key TTL (justified) to the Idempotency §, and the `details.{currentStatus, requestedStatus}` shape (JSON examples + `StateTransitionErrorDetails` TS interface) to the 422 `unprocessable` and 409 `conflict` responses; IDEMPOTENCY and PAYLOAD tasks and their two engagement gates flipped to ✅.

**THINK / socratic answer (verbatim):**

A duplicate update (network retry) is handled by the required `idempotencyKey`: the webhook deduplicates on it, so a re-delivery carrying an already-seen key returns the original `200` result (same `refNumber`, `status`, `notificationQueued: true`) and re-applies no side effect — no second `MunicipalityResponse` INSERT, no second `Objection.status` UPDATE, no second notification enqueue. An invalid state transition is rejected by an enforced state machine: `UPHELD` and `REJECTED` are terminal, so a webhook trying to re-open a terminal objection (e.g. `REJECTED → UPHELD`) hits the terminal-state guard and returns `409 conflict`; a non-terminal illegal/no-op transition (e.g. `UNDER_REVIEW → UNDER_REVIEW`) returns `422 unprocessable`. In both rejection cases the `MunicipalityResponse` row is still INSERTed for audit, but `Objection.status` is not changed and no notification fires, so the Flutter tracking screen never shows a wrong status. The CRM webhook authenticates with a shared secret in the `X-Municipal-Webhook-Secret` header (env `MUNICIPAL_WEBHOOK_SECRET`) — not a JWT/bearer token, since no Flutter client calls this route — chosen over per-key/HMAC for the lowest municipal-IT burden, hardened with a source-IP allowlist and out-of-band rotation.

**Honest gaps (deliverable is otherwise the source of truth and largely complete):**

1. IDEMPOTENCY task — the plan explicitly requires a stated, justified TTL for idempotency keys; the deliverable describes the dedup mechanism but states no TTL. Genuine gap.
2. PAYLOAD task / engagement gate — the plan requires the 422 invalid-transition response to carry `details.{currentStatus, requestedStatus}`; the deliverable's 422 `unprocessable` row carries no such details object.
3. Non-blocking deviations (deliverable intentionally reconciled with sibling contracts, recorded for traceability, not gaps): route is `POST /municipality/objections/:ref/response` (path-param `ref`) rather than the plan's `POST /api/v1/municipality/objection-update` with `objectionReferenceNumber` in body; error codes are `unprocessable`/`conflict` rather than `invalid_state_transition`; auth header is `X-Municipal-Webhook-Secret` rather than the plan's draft `X-Municipality-Secret` (same Option A mechanism, reconciled to `.env.example`).
