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

- [ ] ⚠️ T1  Add MinIO service to `podman-compose.yml` as blob storage emulator:
  - Image: `minio/minio`
  - Named volume, health check
  - Env vars: `BLOB_ENDPOINT`, `BLOB_ACCESS_KEY`, `BLOB_SECRET_KEY`, `BLOB_BUCKET`
  Done when: `podman-compose up minio` starts; MinIO console accessible.

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

- [ ] ⚠️ T3  `POST /objection` — create an objection draft:
  - Accept `{ userId, accountNumber, lineItemId, category, notes }`
  - Create `Objection` record via Prisma with status `DRAFT`
  - Return 201 + `{ objectionId }`
  Done when: curl creates Objection row in psql.

- [ ] ⚠️ T4  `POST /objection/:id/document` — upload supporting document:
  - Accept multipart form-data with file field
  - Validate file type (PDF, JPG, PNG only) and size (max from env)
  - Upload to blob storage; store key in `Document` record via Prisma
  - Return 201 + `{ documentId, storageKey }`
  Done when: uploaded file appears in MinIO; Document row in psql with storageKey.

- [ ] ⚠️ T5  `GET /objection/:id/summary` — return objection summary for review:
  - Return Objection + linked Documents + line item detail from bill-service
  - Return 200 + full summary, or 404
  Done when: curl returns objection with document list and line item.

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

- [ ] ⚠️ T7  Seed data for SUBMISSION Figma branches (add to `prisma/seed.ts`):
  - Draft objection (status DRAFT, no refNumber)
  - Submitted objection (status SUBMITTED, refNumber present)
  - Failed submission (status DRAFT — simulated adapter failure)
  Done when: `pnpm db:seed` runs; psql confirms Objection rows with varied status.

- [ ] ⚠️ T8  Unit tests: create objection, upload valid doc, upload invalid type → 400,
  submit (success), submit (already submitted → 409), submit (adapter failure → 502).
  Done when: `pnpm test` passes in objection-service directory.

- [ ] ⚠️ T9  Integration smoke: create objection → upload doc (MinIO check) →
  GET summary → submit → psql confirms SUBMITTED + refNumber → AuditLog row.
  Done when: full lifecycle passes with DB and blob storage state confirmed.

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
