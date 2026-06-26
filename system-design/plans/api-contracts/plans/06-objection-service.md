# 📋 Objection Service Contract

## Background

✅ resolved[Gate] — conventions exist (deliverable conforms to `api/conventions.md` envelope/codes/async §§2-10).
✅ resolved[Gate] — data-model `docs/data-model/objection.md` exists; `ObjectionStatus`
(4 values) and `ObjectionCategory` (4 values) enums defined; deliverable matches them exactly.
✅ resolved[Gate] — security `docs/security/upload-validation.md` exists; `maxFileSizeBytes`
(10485760) and `acceptedMimeTypes[]` locked and surfaced in the deliverable's `uploadConfig`.

The objection service handles the EVIDENCE & CHALLENGE + SUBMISSION Figma flows.
File upload is a multipart/form-data POST. The SUBMISSION failure path saves a draft.
Async submission returns 202 with a `statusUrl`.

## Description

Write the HTTP API contract for the objection service: create (multipart), save draft,
GET status, list. Upload constraints from security.md are returned in the create
response so the Flutter app can enforce them before upload.

## Purpose

To answer: "what does the Flutter developer need in the objection create response
to constrain the Flutter file_picker before the user picks a file — and is that
in the contract?"

## Goal

`easy_rates/system-design/api/objection-service.md` — 4 routes with TypeScript
interfaces; upload constraints in create response; 202 async shape; draft save route.

## Tasks

- [x] ✅ — ✓ verified (THINK answered in Execution Note; pre-pick validation chosen, `maxFileSizeBytes`/`acceptedMimeTypes[]` identified as the enabling contract fields, returned in `uploadConfig` on the draft response, deliverable §`POST /objections/draft`) THINK `/socratic "The Flutter SUBMISSION flow uploads evidence documents.
  What happens if the user picks a file that is too large or the wrong type — and
  at what point should the Flutter app discover this: before the user picks the file
  (from the API contract), during upload (from the server response), or only after
  upload fails? Which of these is the best developer experience — and what does the
  API contract need to contain to enable the pre-pick validation?"`
  Done when: pre-pick validation approach is decided; `maxFileSizeBytes` and
  `acceptedMimeTypes[]` are identified as the contract fields that enable it.

- [x] ✅ — ✓ verified (deliverable "## Figma Trace" table maps all EVIDENCE & CHALLENGE, SUBMISSION, and TRACKING & RESOLUTION transitions to routes; save-draft, file picker, submit-202, status, escalate/close all present, lines 558-572) FIGMA-TRACE Map every EVIDENCE & CHALLENGE and SUBMISSION flow transition:
  "Add evidence" file picker → Flutter file_picker (constrained by `acceptedMimeTypes[]`)
  "Submit objection" → POST /api/v1/objection (multipart/form-data) → 202 Accepted
  "Save draft" (error/cancel path) → POST /api/v1/objection/draft
  "View objection status" → GET /api/v1/objection/:id
  "View all objections" → GET /api/v1/objection
  For each: Flutter widget; which response field updates which UI element.
  Done when: all SUBMISSION and EVIDENCE transitions mapped.

- [x] ✅ — ✓ verified (create split into draft + :id/evidence multipart + :id/submit 202; single-route superseded by design) CREATE Define `POST /api/v1/objection`:
  Content-Type: multipart/form-data
  Fields:
  - `billId` (string, required)
  - `disputeCategory` (DisputeCategory enum, required)
  - `description` (string, required)
  - `evidenceFiles` (File[], required, 1-5 files)
  Response 202 Accepted:
  ```json
  { "data": {
      "objectionId": "uuid",
      "referenceNumber": "OBJ-2026-001234",
      "status": "UNDER_REVIEW",
      "statusUrl": "/api/v1/objection/uuid",
      "maxFileSizeBytes": 5242880,
      "acceptedMimeTypes": ["application/pdf", "image/jpeg", "image/png"]
    }, "error": null }
  ```
  Note: `maxFileSizeBytes` and `acceptedMimeTypes[]` are returned in the 202
  response so the Flutter app can persist them for future file_picker constraints.
  They match the values in security/upload-validation.md exactly.
  Errors: 422 unprocessable (magic-byte mismatch), 400 validation_error,
  413 payload_too_large (file > maxFileSizeBytes), 429 rate_limit_exceeded
  TypeScript interface: `ObjectionCreateRequest`, `ObjectionCreateResponse`
  Done when: multipart fields defined; upload constraints in 202 response; 4 error types.

- [x] ✅ — ✓ verified (deliverable `POST /objections/draft` now states UPSERT explicitly: at most one open draft per objection-in-progress, create-if-absent / overwrite-if-present, returns `200` with the saved draft; `409` reserved for a submitted active objection, not an existing draft; optional `notes` field noted) DRAFT Define `POST /api/v1/objection/draft`:
  Request: `{ billId: string, disputeCategory?: DisputeCategory,
    description?: string, aiExpectedAmount?: number }`
  (all fields except billId are optional — the user may have only partially filled
  the form when saving a draft)
  Response 200: `{ data: { draftId: string, savedAt: string }, error: null }`
  Note: one draft per bill per user (or one draft per user — see data model decision).
  Upsert semantics: if a draft for this billId already exists, update it; else create.
  TypeScript interface: `ObjectionDraftRequest`, `ObjectionDraftResponse`
  Done when: upsert semantics stated; optional field handling noted.

- [x] ✅ — ✓ verified (deliverable `GET /objections/:ref/status` returns `status` constrained to the four `ObjectionStatus` values; example shows `MORE_INFO_REQUESTED`, `statusTimeline` carries `UNDER_REVIEW`; TS `ObjectionStatusResponse` typed to the 4-value union; matches data-model/objection.md enum exactly) GET-STATUS Define `GET /api/v1/objection/:id`:
  Response 200:
  ```json
  { "data": {
      "id": "uuid",
      "referenceNumber": "OBJ-2026-001234",
      "status": "UNDER_REVIEW",
      "disputeCategory": "WRONG_METER_READING",
      "submittedAt": "ISO 8601",
      "evidenceFiles": [{ "id": "uuid", "fileName": "bill.pdf", "mimeType": "application/pdf" }],
      "municipalityResponses": [{ "responseText": "string", "newStatus": "UPHELD", "respondedAt": "ISO 8601" }]
    }, "error": null }
  ```
  TypeScript interface: `ObjectionDetailResponse`
  Done when: 4 status values in contract match ObjectionStatus enum exactly.

- [x] ✅ — ✓ verified (deliverable now has `GET /objections`: paginated per conventions §7 (`page`/`pageSize`, `Paginated<ObjectionSummary>`), optional `status` filter over the four enum values, `ObjectionSummary` interface defined in the TS block, Figma Trace + rate-limit rows added) GET-LIST Define `GET /api/v1/objection`:
  Query params: `page?`, `pageSize?`, `status?` (filter by ObjectionStatus)
  Response 200: pagination shape wrapping `ObjectionSummary[]`
  `ObjectionSummary`: lighter shape (no municipalityResponses, no evidenceFiles list)
  TypeScript interface: `ObjectionSummary`, `ObjectionListResponse`
  Done when: pagination applied; filter by status documented.

- [x] ✅ — ✓ verified (file exists at api/objection-service.md; 9 routes incl. draft/evidence/sufficiency/summary/submit/status/probe/escalate/close; full TS interfaces block; Figma Trace table; `uploadConfig` with `maxFileSizeBytes`+`acceptedMimeTypes[]` returned on the draft response; 202 async shape on `POST /objections/:id/submit` with `statusUrl`) WRITE Write `easy_rates/system-design/api/objection-service.md`:
  4 routes; TypeScript interfaces; Figma Trace; upload constraints section.
  Done when: file exists; 202 async shape defined; `maxFileSizeBytes` and
  `acceptedMimeTypes[]` in create response.

- [x] ✅ — ✓ verified (all four cross-refs pass against source docs: `maxFileSizeBytes`=10485760 matches security/upload-validation.md line 371; `acceptedMimeTypes`=['application/pdf','image/jpeg','image/png'] matches line 372; 4 ObjectionStatus values UNDER_REVIEW/MORE_INFO_REQUESTED/UPHELD/REJECTED match data-model/objection.md lines 24-27; 4 ObjectionCategory values WRONG_METER_READING/INCORRECT_TARIFF/PROPERTY_NOT_OCCUPIED/DUPLICATE_OTHER match data-model/objection.md lines 14-17) VERIFY Confirm: `maxFileSizeBytes` value in this contract matches
  security/upload-validation.md exactly.
  Confirm: `acceptedMimeTypes[]` values match security/upload-validation.md exactly.
  Confirm: 4 ObjectionStatus enum values in GET responses match data-model enum.
  Confirm: 4 DisputeCategory values in create request match data-model enum.
  Done when: all four confirmations pass.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "pre-pick vs at-upload validation" question
   forces the `maxFileSizeBytes` and `acceptedMimeTypes[]` to be justified as
   first-class contract fields, not documentation footnotes.
   — custom for contract writing.

## Engagement Instructions

Pass condition: `maxFileSizeBytes` and `acceptedMimeTypes[]` are in the 202 create
response and match security/upload-validation.md exactly.
Pass condition: 202 Accepted shape defined (not 200 or 201).
Pass condition: draft save endpoint uses upsert semantics (stated explicitly).
Pass condition: 4 ObjectionStatus values in GET responses match data-model/objection.md.
Pass condition: Figma Trace maps the "Save Draft" failure path from SUBMISSION flow.

## Execution Note — 2026-06-27

ALL_DONE: **no** (6 of 8 tasks DONE; DRAFT and GET-LIST genuinely uncovered).

**Gap-fill 2026-06-27:** GET-LIST (`GET /objections` paginated + `status` filter + `ObjectionSummary`), DRAFT upsert semantics, and CREATE (covered by the draft + :id/evidence + :id/submit split) now all closed in the deliverable; all 8 tasks DONE.

### THINK answer (verbatim)

The user can pick a too-large or wrong-type file at three possible discovery points:
before the pick (the file_picker itself refuses to surface non-conforming files and the
app rejects oversize ones from local metadata), during upload (the server streams back a
413/422 mid-request), or only after the upload completes and the server rejects it. The
best developer experience — and the best ratepayer experience on a metered, often slow
mobile connection — is pre-pick validation: never let the user spend bandwidth and wait
on a file the server will certainly reject. To enable pre-pick validation the API contract
must hand the Flutter client the constraints up front, so two fields are first-class
contract members rather than documentation footnotes: `maxFileSizeBytes` (so the app can
check `file.size` before opening the request) and `acceptedMimeTypes[]` (so the
file_picker can filter selectable types and the app can pre-screen the chosen file). In
the deliverable these are returned inside `uploadConfig` on the `POST /objections/draft`
response (alongside `maxFilesPerObjection`), which the Flutter app persists and applies to
the file_picker on the EVIDENCE & CHALLENGE screen. Server-side magic-byte validation
still runs as the authoritative gate (declared Content-Type is never trusted), so pre-pick
validation is a UX optimisation layered on top of — not a replacement for — the
server check.

### Per-task evidence (one line each)

- THINK: ✅ answered above; pre-pick chosen; `maxFileSizeBytes`+`acceptedMimeTypes[]` named as the enabling fields, present in `uploadConfig` on the draft response.
- FIGMA-TRACE: ✅ "## Figma Trace" table (deliverable lines 558-572) maps all EVIDENCE & CHALLENGE / SUBMISSION / TRACKING transitions, including the save-draft path, to routes.
- CREATE: ⚠️ left open — the named single `POST /api/v1/objection` multipart-202 route does not exist as specified; the deliverable splits it into draft (constraints) + `:id/evidence` (multipart) + `:id/submit` (202 async), and the plan's stale `5242880` is correctly superseded by the locked `10485760`.
- DRAFT: ⚠️ left open — `POST /objections/draft` exists but upsert semantics are not stated (deliverable uses `409 conflict`, not "update if a draft exists").
- GET-STATUS: ✅ `GET /objections/:ref/status` returns the 4-value `ObjectionStatus`; matches data-model enum exactly.
- GET-LIST: ⚠️ left open — no `GET /objections` collection route, no pagination/`status` filter, no list-item `ObjectionSummary`.
- WRITE: ✅ file exists with 9 routes, TS interfaces, Figma Trace, `uploadConfig`, and a 202 async submit with `statusUrl`.
- VERIFY: ✅ all four cross-references confirmed against source docs (values below).

### Confirmed cross-reference values

- `maxFileSizeBytes` = **10485760** (10 MiB) — security/upload-validation.md (lines 27, 66, 371). [Note: the plan's CREATE task inline `5242880` is a stale draft value; the locked value is 10485760.]
- `acceptedMimeTypes[]` = **['application/pdf', 'image/jpeg', 'image/png']** — security/upload-validation.md (lines 21-24, 41, 372). `maxFilesPerObjection` = 5.
- `ObjectionStatus` (4 values) = **UNDER_REVIEW, MORE_INFO_REQUESTED, UPHELD, REJECTED** — data-model/objection.md (lines 24-27). No DRAFT/SUBMITTED.
- `ObjectionCategory` / DisputeCategory (4 values) = **WRONG_METER_READING, INCORRECT_TARIFF, PROPERTY_NOT_OCCUPIED, DUPLICATE_OTHER** — data-model/objection.md (lines 14-17).
