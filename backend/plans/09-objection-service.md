# 📋 Objection Service — Document Upload, Create, Submit, Reference Number

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background

The EVIDENCE & CHALLENGE and SUBMISSION flows are the core value proposition of
EasyRates: a ratepayer selects a disputed charge, uploads supporting documents,
reviews a summary, and submits an objection to the municipality. The objection
service owns the full lifecycle from dispute category selection through to
reference number issuance. Document storage uses Azure Blob Storage (or
S3-compatible); for local dev a MinIO container in Podman Compose serves as the
blob emulator. The municipality submission adapter is stubbed with a clean
interface — the same replaceable pattern used in property and bill services.

## Description

Implement document upload to blob storage, objection creation, submission to the
municipality adapter, and reference number generation. All objection state lives
in PostgreSQL (Objection, Document tables). The EVIDENCE & CHALLENGE sufficiency
check is client-side in Flutter; this service does not enforce it.

## Purpose

Covers the EVIDENCE & CHALLENGE and SUBMISSION Figma flows: Upload Supporting
Documents → Review Summary → Confirm Submission → Reference Number Issued /
Error Retry or Save Draft.

## Goal

`easy_rates/backend/services/objection-service/` — document upload, objection
CRUD, submission, and reference number generation implemented; municipality
submission adapter is one replaceable function; seed data covers all SUBMISSION
Figma branches; integration smoke passes.

## Tasks

- [x] ✅ — ✓ verified (2026-06-27 adapters) T1  Real **Azure Blob Storage** adapter
  built. `apps/objection/src/blob-store.ts` now exposes an `EvidenceStore`
  interface with two impls: `AzureBlobStore`
  (`BlobServiceClient.fromConnectionString`, put/get/delete against the `evidence`
  container, auto-create-if-absent) and the existing `LocalBlobStore` stub. Backend
  selected by `BLOB_DRIVER` (azure when `AZURE_STORAGE_CONNECTION_STRING` present,
  else local) — `decideBlobDriver` is pure + unit-tested. Both use the same
  portable key shape `objections/<id>/<uuid>.<ext>`. Env added to `packages/config`
  + `.env.example` (placeholders). LIVE SMOKE against the `easyrates` storage
  account: uploaded `__smoketest/<ts>.txt` → downloaded (bytes matched) → DELETED
  (cleanup verified). MinIO emulator remains ❌ DESCOPED (not in any contract).

- [ ] ⚠️ T2  Write the municipality submission adapter interface at
  `easy_rates/backend/shared/adapters/municipality-submission-adapter.ts`:

  ```ts
  export interface SubmissionResult {
    referenceNumber: string
    submittedAt: string
    status: 'ACCEPTED' | 'FAILED'
  }
  export interface MunicipalitySubmissionAdapter {
    submitObjection(objectionId: string, payload: ObjectionPayload): Promise<SubmissionResult>
  }
  ```

  Stub implementation returns a generated ref number and `status: 'ACCEPTED'`.
  Done when: interface exists; stub compiles.

  - [x] ❌ DESCOPED (2026-06-27) T2  The canonical objection-service contract has
    no synchronous municipality-submission adapter. Submission is **async** (202
    + statusUrl, §8): `POST /objections/:id/submit` enqueues to the BullMQ
    `objection-submit` queue (`packages/queue`), whose worker assigns the
    `ELM-2026-NNNNNN` refNumber and finalises the Objection. The municipality
    side is the **inbound CRM webhook** (municipality-service, plan 11), not an
    outbound adapter from objection-service.

- [x] ✅ — ✓ verified (2026-06-27) T3  `POST /objections/draft` (canonical path,
  NOT `POST /objection`). UPSERT — one open draft per user+lineItem; create-or-
  overwrite in place; **200** either way (no 409 for an existing draft); 409 only
  when a *submitted* objection already covers the charge. Returns
  `{ objectionId, status:"DRAFT", uploadConfig }`. The durable Objection anchor is
  created here (refNumber/submittedAt null = pre-submission) so evidence can FK to
  it; editable form state co-stored in `ObjectionDraft`. `DRAFT` is a display
  marker, not an `ObjectionStatus` value. Verified via smoke (200 create + 200
  re-save same objectionId + 409 on submitted-charge) and unit tests
  (`decideDraftUpsert`).

- [x] ✅ — ✓ verified (2026-06-27) T4  `POST /objections/:id/evidence` (canonical
  path, NOT `/document`). `multipart/form-data` via multer (memory). **Magic-byte**
  MIME detection (`file-type`) — declared Content-Type NOT trusted (Rule C).
  Validates size (10 MiB → 413), MIME allowlist (pdf/jpeg/png → 422
  `invalid_file_type` with `{detectedType, allowedTypes}`), count (≤5 → 422),
  missing file → 400 `file_missing`. Stores to the local blob-store stub, records
  `EvidenceFile.storageKey`, returns the **detected** mimeType. 201 Created.
  MORE_INFO_REQUESTED upload auto-transitions back to UNDER_REVIEW. Verified:
  smoke (200 valid PDF written to disk + 422 on a zip masquerading as pdf) +
  unit tests (`validateEvidenceFile` size/MIME/count). ✅ Real Azure Blob now wired
  (T1) — `putEvidence` routes through the env-selected `EvidenceStore`.

- [ ] ⚠️ T5  `GET /objections/:id/summary` — Review Summary view. Defined in the
  canonical contract but **out of this build's scope** (the 5 core routes built
  were draft / evidence / submit / list / status). Not yet implemented. Adjacent
  contract routes also deferred: `GET /objections/:id/sufficiency`,
  `POST /objections/:ref/probe`, `/escalate`, `/close`.

- [ ] ⚠️ T6  `POST /objection/:id/submit` — submit objection to municipality:
  - Validate objection status is `DRAFT` (reject 409 if already submitted)
  - Call `municipalityAdapter.submitObjection(...)` — stub returns ref number
    - If adapter fails: return 502 immediately; do NOT update Objection status —
      the record stays DRAFT so the user can retry (the municipality never received it)
    - If adapter succeeds: update `Objection.status = 'SUBMITTED'` and
      `Objection.refNumber = ref` in a single Prisma write
  - Write `AuditLog` event `OBJECTION_SUBMITTED`
  - Call `POST /notify` fire-and-forget — do not `await` or block the response;
    a notification-service failure must not cause the submission to fail
  - Return 200 + `{ referenceNumber }` on success
  Done when: curl submit → psql shows SUBMITTED status + refNumber; AuditLog row present.

  - [x] ✅ — ✓ verified (2026-06-27) T6  `POST /objections/:id/submit` rebuilt to
    the canonical **async** contract: **202 Accepted** + `{ jobId, statusUrl }`
    (§8), NOT a synchronous 200. Enqueues to the BullMQ `objection-submit` queue;
    the worker assigns `ELM-2026-NNNNNN`, stamps `submittedAt`, consumes the draft,
    and enqueues an OBJECTION_RECEIVED notification. 409 if already submitted; 422
    if no evidence attached. ❌ DESCOPED from the old task: the `SUBMITTED` enum
    value (born UNDER_REVIEW), the synchronous adapter + 502, the AuditLog write,
    and the `POST /notify` call (replaced by the BullMQ notification queue).
    Verified via smoke (202 + statusUrl → worker assigned ELM-2026-000002, psql
    confirms refNumber + UNDER_REVIEW + the notification row).

- [x] ✅ — ✓ verified (2026-06-27) T7  Seed already provides the submitted
  objection `ELM-2026-000001` (UNDER_REVIEW) + a flagged WATER line item, which
  the smoke drives end-to-end. No new seed rows were required (`DRAFT`/`SUBMITTED`
  enum values do not exist — DESCOPED). The smoke itself exercises create-draft →
  evidence → submit → status transitions live.

- [x] ✅ — ✓ verified (2026-06-27) T8  Unit tests (vitest, 15 passing):
  `decideDraftUpsert` (create / overwrite / 409-on-submitted), `validateEvidenceFile`
  (valid pdf/jpg/png, missing, too-large, invalid-type with detectedType, unknown
  magic bytes, too-many, count-precedence), uploadConfig-mirrors-contract,
  `objectionTitle`. (Old "adapter failure → 502" case DESCOPED — no adapter.)

- [x] ✅ — ✓ verified (2026-06-27) T9  Integration smoke vs **live DB + Redis**:
  draft (200) → re-save UPSERT (200, same id) → submitted-charge (409) → evidence
  valid PDF (201, file on disk) → zip-as-pdf (422 invalid_file_type) → submit
  (202 + statusUrl) → worker assigns ELM-2026-NNNNNN → GET /objections (paginated)
  → GET /objections/:ref/status. psql confirmed the EvidenceFile.storageKey row +
  blob on disk + the submitted Objection. (MinIO check + AuditLog DESCOPED.)

## Recommended skill

▶ `/build-to-contract` ✅ — builds objection routes from the API contract in
   `system-design/api/objection.md`.
   alt: `/architect-contract` ✅ — for finalising the municipality submission
   adapter interface before T2.

## Engagement Instructions

```bash
# 1. MinIO running; submission adapter interface exists
podman-compose -f easy_rates/backend/podman-compose.yml ps minio
ls easy_rates/backend/shared/adapters/municipality-submission-adapter.ts
# Expected: MinIO healthy; adapter file present

# 2. Unit tests green
cd easy_rates/backend/services/objection-service && pnpm test
# Expected: all tests pass

# 3. Create objection: 201 + psql row with DRAFT status
OBJ_ID=$(curl -s -X POST http://localhost:${OBJ_PORT:-3006}/objection \
  -H "Content-Type: application/json" \
  -d '{"userId":"<seed-user-id>","accountNumber":"ACC001","lineItemId":"<line-id>","category":"WATER","notes":"Unusually high"}' \
  | jq -r '.objectionId')
psql "$DATABASE_URL" -t -c \
  "SELECT id, status FROM \"Objection\" WHERE id='$OBJ_ID';"
# Expected: 1 row, status = DRAFT

# 4. Document upload: file in MinIO bucket AND Document row in psql
curl -s -X POST "http://localhost:${OBJ_PORT:-3006}/objection/$OBJ_ID/document" \
  -F "file=@/tmp/test.pdf" | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT id, \"storageKey\" FROM \"Document\" WHERE \"objectionId\"='$OBJ_ID';"
# Expected: Document row with non-null storageKey; file present in MinIO bucket
# (check MinIO console at http://localhost:9001 or via mc CLI)

# 5. Submit: SUBMITTED + refNumber in psql + AuditLog row
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${OBJ_PORT:-3006}/objection/$OBJ_ID/submit")
echo "submit: HTTP $CODE"   # Expected: 200
psql "$DATABASE_URL" -t -c \
  "SELECT status, \"refNumber\" FROM \"Objection\" WHERE id='$OBJ_ID';"
psql "$DATABASE_URL" -t -c \
  "SELECT event FROM \"AuditLog\" WHERE event='OBJECTION_SUBMITTED' ORDER BY \"createdAt\" DESC LIMIT 1;"
# Expected: status=SUBMITTED, refNumber non-null, AuditLog row present

# 6. Already submitted → 409
CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "http://localhost:${OBJ_PORT:-3006}/objection/$OBJ_ID/submit")
echo "re-submit: HTTP $CODE"   # Expected: 409

# 7. Swappability: municipality adapter wired only in factory/DI
grep -r "municipality-submission-adapter" \
  easy_rates/backend/services/objection-service/ 2>/dev/null
# Expected: 0 results (swap the factory import; zero route handler changes)
```

Gate: check 4 requires both MinIO file AND psql Document row — one without
the other fails. Check 5 requires AuditLog row, not just HTTP 200.

---

## Execution Note — 2026-06-27

Built the objection-service to the **canonical** `system-design/api/objection-service.md`
contract (the plan above predated it and described singular `/objection` routes, a MinIO
emulator, a synchronous municipality adapter, `DRAFT`/`SUBMITTED` enum values, and `POST
/notify` — all superseded). Implemented the 5 core routes:
`POST /objections/draft` (UPSERT), `POST /objections/:id/evidence` (multipart + magic-byte
validation), `POST /objections/:id/submit` (202 async + BullMQ), `GET /objections`
(paginated + status filter), `GET /objections/:ref/status`.

Key reconciliations:
- **Evidence FK.** `EvidenceFile.objectionId` is a NON-NULL FK to `Objection`, so evidence
  cannot attach to a bare `ObjectionDraft`. The durable `Objection` anchor is therefore
  created at draft-upsert time (refNumber/submittedAt null = pre-submission marker); the
  editable form lives in `ObjectionDraft`. `:id` in the routes is the `Objection.id`.
- **Blob storage.** Local filesystem stub (`BLOB_DIR`, gitignored) records the storageKey.
  Azure Blob is the prod target and remains ⚠️ TODO (single-file adapter swap).
- **Async submit.** 202 + statusUrl per conventions §8; finalisation (refNumber, notify)
  runs on the BullMQ `objection-submit` worker (`packages/queue`).

Verified: `pnpm -r exec tsc --noEmit` → 0; 15 unit tests green; full live-DB+Redis smoke
(transcript + psql row checks). Deferred (honest ⚠️): `GET /:id/summary`, `/:id/sufficiency`,
`/:ref/probe`, `/escalate`, `/close`, real Azure Blob, and the full rate-limit infra.

---

## Execution Note — 2026-06-27 (adapters)

Wired the **real Azure Blob Storage** evidence backend behind an `EvidenceStore`
interface in `apps/objection/src/blob-store.ts`:
- `AzureBlobStore` — `BlobServiceClient.fromConnectionString` → `evidence`
  container (created-if-absent); `put` (uploadData with content-type), `get`
  (downloadToBuffer), `delete` (deleteIfExists). `LocalBlobStore` keeps the
  filesystem stub. `selectEvidenceStore()`/`decideBlobDriver()` choose by
  `BLOB_DRIVER` (auto: azure iff `AZURE_STORAGE_CONNECTION_STRING` set, else local).
  `putEvidence` (used by the route) now delegates to the selected store.
- Env added to `packages/config` Zod + `.env.example` (placeholders):
  `AZURE_STORAGE_CONNECTION_STRING`, `AZURE_BLOB_CONTAINER` (default `evidence`),
  `BLOB_DRIVER`.

**Verification**
- `pnpm -r exec tsc --noEmit` → 0; full suite **104 passed** (objection +5:
  `decideBlobDriver` selection + `LocalBlobStore` put/get/delete round-trip).
- LIVE SMOKE (storage account `easyrates`, container `evidence`): uploaded
  `__smoketest/<ts>.txt` → downloaded (bytesMatch true) → deleted
  (cleanupVerified true). The smoke object was removed; no residue.
- WRITE/READ/SUBMIT rate-limits wired on the objection routes (draft/evidence →
  WRITE, submit → SUBMIT 5/24h, list/status → READ).
