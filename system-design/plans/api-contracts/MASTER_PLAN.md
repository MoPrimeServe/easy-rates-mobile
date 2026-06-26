# EasyRates API Contracts

## Mission

Design and document the complete HTTP API surface for EasyRates — serving the Flutter
mobile app as the sole client. The seven Figma process flows reveal 9 service contracts:
7 Flutter-facing REST services, the municipality CRM ingestion endpoint (feeds the
Tracking & Resolution flow), and the AI expected-amount endpoint (feeds the Bill Review
screen). Shared TypeScript conventions are established first; one contract file per
service follows; every contract includes a TypeScript interface and a Figma Trace
section. The scope closes with a full orphan audit for the Flutter client.

## Objectives

1. Establish shared API conventions before any service contract is written: envelope
   shape, error codes, pagination, date format, camelCase field names, and TypeScript
   interface naming conventions.
2. Write seven Flutter-facing service contracts: auth, otp, property, account, bill,
   objection, notification.
3. Write two supporting contracts that serve the Flutter mobile app indirectly: the
   municipality CRM ingestion endpoint (feeds objection status updates into the
   Tracking flow) and the AI expected-amount endpoint (embedded in the bill service,
   feeds the Bill Review screen).
4. Include a TypeScript interface in every contract sufficient for a developer to
   implement the Dio model class without further reference; include a Figma Trace
   section covering the relevant mobile app screen transitions.
5. Run a full orphan audit for the Flutter client: zero unmatched Figma transitions,
   zero unmatched routes in either direction.

## Goals

- G0 `api/conventions.md` — envelope shape, error codes, pagination format, date
  format (ISO 8601), camelCase field names; TypeScript interface naming convention;
  gates all service contracts.
- G1 `api/auth-service.md` — register, login, token/refresh, logout, forgot-password.
- G2 `api/otp-service.md` — send, verify, resend; `ttlSeconds` + `resendCooldownSeconds`
  matching twilio-integration.md exactly; 4 machine-readable error codes.
- G3 `api/property-service.md` — `accountNumber` lookup; address/ERF search.
- G4 `api/account-service.md` — profile GET/PATCH; notification preferences; manage
  linked properties; change-password.
- G5 `api/bill-service.md` — bill list; bill detail + line items; AI expected-amount
  endpoint (`GET /api/v1/bills/:id/ai-estimate` — naming resolved, api orphan audit D-5).
- G6 `api/objection-service.md` — create (multipart/form-data); save draft; status
  (4 exact values from data-model sub-scope); list; async 202 response shape.
- G7 `api/notification-service.md` — list (paginated); mark-read; 3 channel types;
  push vs in-app split explicit.
- G8 `api/municipality-service.md` — CRM response ingestion webhook; objection status
  update from municipality system; state transition rules feeding the Tracking flow.
- G9 Orphan audit — zero unmatched transitions (forward) and zero unmatched routes
  (reverse) for the Flutter client; cross-reference checks vs twilio-integration.md
  (OTP params) and security sub-scope (upload constraints).

## Expected Outcome

A complete api/ directory that a Flutter developer can read to build the entire mobile
client without asking a single follow-up question. Every Figma screen transition maps
to a named HTTP call. Every HTTP route maps to a Figma transition. OTP values and
upload constraints are cross-referenced and consistent with their source documents.

## Definition of Done

1. ✅ `api/conventions.md` written; all 9 service contracts conform to it.
2. ✅ Nine service contracts written (7 Flutter-facing + 2 supporting).
3. ✅ TypeScript interface in every contract; sufficient for a developer to write the
   Dio model class directly.
4. ✅ Figma Trace section in every contract covering the relevant mobile app screen
   transitions.
5. ✅ Orphan audit passes: zero unmatched transitions and zero unmatched routes for the
   Flutter client.
6. ✅ OTP `ttlSeconds` and `resendCooldownSeconds` match twilio-integration.md exactly.
7. ✅ Objection upload constraints (`maxFileSizeBytes`, `acceptedMimeTypes[]`) match
   security sub-scope output exactly.
8. ✅ Objection status values in objection-service.md match data-model sub-scope Prisma
   enum exactly (4 values).

## Sub-Scopes

(none)

## Plans

- ✅ [plans/00-conventions.md](plans/00-conventions.md) — shared API standards: envelope, error codes, pagination, camelCase, 202 shape
- ✅ [plans/01-auth-service.md](plans/01-auth-service.md) — register, login, token refresh, logout; JWT TTL fields in response
- ✅ [plans/02-otp-service.md](plans/02-otp-service.md) — send, verify, resend; ttlSeconds + resendCooldownSeconds; 4 error codes
- ✅ [plans/03-property-service.md](plans/03-property-service.md) — accountNumber/ERF lookup; 404 vs empty-array decision; cache policy
- ✅ [plans/04-account-service.md](plans/04-account-service.md) — profile GET/PATCH (partial update); notification prefs; POPIA note
- ✅ [plans/05-bill-service.md](plans/05-bill-service.md) — bill list, bill detail + lineItems, AI expected-amount with staleness
- ✅ [plans/06-objection-service.md](plans/06-objection-service.md) — create multipart (202), draft save, GET status, list; upload constraints
- ✅ [plans/07-notification-service.md](plans/07-notification-service.md) — list, mark-read; push vs in-app split; 3 channel types
- ✅ [plans/08-municipality-service.md](plans/08-municipality-service.md) — CRM webhook; authentication; idempotency; state transitions
- ✅ [plans/09-orphan-audit.md](plans/09-orphan-audit.md) — forward + reverse orphan audit; 6 cross-reference checks
