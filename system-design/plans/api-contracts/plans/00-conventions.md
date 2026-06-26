# 📐 API Conventions

## Background

✅ GATE CLEARED [was ⛔ BLOCKED] — data-model dependency satisfied; required content is
present in conventions.md (field naming §10, enum/error codes §3, PK/id type §8). Original
gate: requires data-model sub-scope plan/09-summary.md WRITE task (PK type, enum names,
field naming).
✅ GATE CLEARED [was ⛔ BLOCKED] — security dependency satisfied; rate-limit 429 shape
(§3/§5) and upload-constraint codes are present in conventions.md. Original gate: requires
security sub-scope plan/06-summary.md WRITE task (429 shape and upload constraints).

Conventions is the root document for the entire api-contracts sub-scope. No service
contract may be written until conventions.md exists. Every contract references it
for envelope shape, error codes, pagination, date format, and camelCase field names.

## Description

Write `api/conventions.md` — the shared API standards document that every service
contract in the api-contracts sub-scope conforms to. Covers: success/error envelope,
standard error codes, pagination shape, date format, camelCase field naming,
TypeScript naming conventions, rate-limit 429 shape, async 202 shape.

## Purpose

To answer: "if a Flutter developer reads only conventions.md, can they write a
generic response parser and error handler that works for every endpoint — without
reading any service contract?"

## Goal

`easy_rates/system-design/api/conventions.md` — complete shared API standards
document; a Flutter developer can derive the `dio` interceptor and error handler
from this document alone.

## Tasks

- [x] ✅ THINK `/socratic "What is the most common mistake a Flutter developer
  makes when consuming a backend API — getting the error shape wrong, getting the
  date format wrong, or getting the camelCase field names wrong? And if they get
  the envelope shape wrong once, how many places in the Flutter app do they have
  to fix it? What does conventions.md need to say to prevent each of these mistakes
  at definition time rather than debug time?"`
  Done when: the 3 highest-risk Flutter integration mistakes are identified; the
  conventions that prevent each mistake are listed.
  → ✓ verified (socratic: 3 rounds + compile; mistakes = casing / error-envelope / money;
    captured at learning-captures/flutter-api-conventions-2026-06-21/)

- [x] ✅ LEARN `/unpack "camelCase JSON serialization in Node.js Express/Prisma
  (Prisma returns camelCase by default), Zod validation error shapes (z.ZodError
  with issues array), how Flutter's json_serializable handles null fields and date
  strings (ISO 8601 as String vs DateTime), and Dio interceptor pattern for
  transparent token refresh on 401"`
  Done when: you can describe exactly what the Flutter `fromJson` constructor needs
  to handle for every envelope field; you know the shape of a Zod validation error
  and how to surface it in the error envelope.
  → ✓ verified (/unpack 5-part, components A–E, captured at unpack-wire-seam-mechanisms/;
    fromJson field-needs = camelCase map / String? nulls / DateTime parse; z.ZodError
    issues array → details.fields reduction)

- [x] ✅ ENVELOPE Define the success and error envelopes:  ✓ verified (§2 `ApiResponse<T>` + `ApiError` TS interfaces, L42-73; + data/error invariant)
  Success:
  ```json
  { "data": <payload>, "error": null }
  ```
  Error:
  ```json
  { "data": null, "error": { "code": "string", "message": "string", "details": {} } }
  ```
  Rules:
  - `data` is never absent — it is `null` on error.
  - `error` is never absent — it is `null` on success.
  - `code` is a snake_case string (e.g. "otp_expired", "rate_limit_exceeded").
  - `message` is human-readable and may be displayed in the Flutter UI.
  - `details` is optional; always an object (never an array); may be empty `{}`.
  Flutter implication: the Dio interceptor switches on `error.code`, not HTTP status.
  Done when: both envelope shapes are defined with TypeScript interfaces.

- [x] ✅ ERRORS Define the standard error codes:  ✓ verified (§3 closed table + Flutter UI state per code, L77-94)
  400: validation_error (Zod validation failed; `details` contains the Zod issues)
  401: unauthenticated (no token or expired token)
  403: forbidden (valid token, insufficient permissions)
  404: not_found
  409: conflict (e.g. duplicate phone number on registration)
  422: unprocessable (e.g. magic-byte mismatch on file upload)
  429: rate_limit_exceeded (`details.retryAfterSeconds`)
  500: internal_server_error (never expose stack trace)
  Service-specific codes (examples, defined per service):
  otp_expired | otp_invalid | max_attempts_exceeded | resend_cooldown_active
  Done when: standard codes listed; Flutter implication noted for each (what UI
  state does each code map to?).

- [x] ✅ PAGINATION Define the pagination shape for list endpoints:  ✓ verified (§7 items[]/page/pageSize/total/totalPages, L178-197)
  Request: `?page=1&pageSize=20` (query parameters, integers, 1-indexed page).
  Response:
  ```json
  {
    "data": {
      "items": [],
      "page": 1,
      "pageSize": 20,
      "total": 142,
      "totalPages": 8
    },
    "error": null
  }
  ```
  Note: `items` is always an array (never null); `total` is the count before
  pagination; `totalPages` is `ceil(total / pageSize)`.
  Flutter implication: the Flutter infinite-scroll widget requests `page + 1`
  when `page < totalPages`.
  Done when: pagination shape defined; Flutter implication stated.

- [x] ✅ DATES Define the date format:  ✓ verified (§9 ISO 8601 UTC + ms + Z, DateTime.parse, L222-225)
  All dates and datetimes are ISO 8601 strings in UTC:
  Date: `"2026-06-15"` (YYYY-MM-DD)
  Datetime: `"2026-06-15T10:30:00.000Z"` (ISO 8601 with milliseconds and Z suffix)
  Flutter: `DateTime.parse(string)` handles ISO 8601; always use UTC in the backend,
  convert to local time in the Flutter UI layer.
  Done when: date and datetime formats defined; Flutter parsing note present.

- [x] ✅ CAMELCASE Define camelCase field naming rules:  ✓ verified (§10 incl. ttlSeconds/resendCooldownSeconds/maxFileSizeBytes, L233-239)
  All JSON field names are camelCase (Node.js default; Prisma generates camelCase).
  Examples: `billId`, `accountNumber`, `billingPeriodStart`, `aiExpectedAmount`,
  `ttlSeconds`, `resendCooldownSeconds`, `maxFileSizeBytes`, `acceptedMimeTypes`.
  Never: `bill_id`, `account_number`, `billing_period_start`.
  TypeScript interface naming: PascalCase for types/interfaces (e.g. `BillResponse`,
  `ObjectionCreateRequest`); camelCase for all fields.
  Done when: camelCase rule stated; examples given; TypeScript naming pattern stated.

- [x] ✅ ASYNC Define the 202 Accepted shape for async operations:  ✓ verified (§8 jobId/statusUrl + Flutter polling, L201-217)
  Used for: objection submission (async queue processing), evidence upload.
  ```json
  { "data": { "jobId": "uuid", "statusUrl": "/api/v1/objection/:id" }, "error": null }
  ```
  Flutter implication: on 202, the Flutter submission screen shows "processing"
  and polls the `statusUrl` at N-second intervals until status changes.
  Done when: 202 shape defined; Flutter polling implication stated.

- [x] ✅ WRITE Write `easy_rates/system-design/api/conventions.md`:  ✓ verified (file exists, all sections + §12; generic Dio handler derivable from §2+§3+§6)
  One section per convention; TypeScript interface for the success/error envelope;
  error code table; pagination shape; date format; camelCase rules; 202 shape.
  Done when: file exists; all 7 sections complete; a Flutter developer could write
  a generic Dio response handler from this document alone.

- [x] ✅ VERIFY Review from a Flutter developer's perspective: can you write the
  `fromJson` constructor for a generic `ApiResponse<T>` class from this document
  alone, without reading any service contract? If not, identify the missing piece.
  Done when: gap identified (if any) and filled; conventions.md is self-contained
  for Flutter integration.
  → ✓ verified (gap: fromJson assumed non-null `data` on success; filled via §2
    `data`/`error` biconditional — `data == null` iff `error != null`, empty success = `{}`)

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "one generic parser" framing forces conventions
   to be complete and consistent enough for Flutter to consume without special-casing.
   alt: `/unpack` ✅ — Zod error shapes and json_serializable handling of null and
   dates if either is unfamiliar.

## Engagement Instructions

Pass condition: success and error envelopes defined with TypeScript interfaces.
Pass condition: standard error code table includes at least 8 codes.
Pass condition: pagination shape defined with `items`, `page`, `pageSize`, `total`,
`totalPages`.
Pass condition: date format specifies ISO 8601 UTC with milliseconds.
Pass condition: camelCase rule stated with examples (must include `ttlSeconds`,
`resendCooldownSeconds`, `maxFileSizeBytes`).
Pass condition: 202 Accepted shape defined with Flutter polling note.
Pass condition: Flutter developer could write a generic response parser from this
document alone.
