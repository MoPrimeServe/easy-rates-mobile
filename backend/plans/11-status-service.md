# 📡 Status Service — Objection Status Query, Municipality Response Ingestion

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed, `gap-report.md` empty, AND
> plan/02 (Prisma schema + migrations) complete before this plan starts.

## Background

The TRACKING & RESOLUTION flow lets a ratepayer check the status of a submitted
objection and respond to municipality requests (upload additional docs, view
adjusted bill, escalate). The municipality's response arrives asynchronously —
either via a webhook from the municipality system or via periodic polling. This
service owns the status query surface (what Flutter polls) and the municipality
response ingestion path (what writes new status into PostgreSQL). The municipality
response adapter is stubbed with a clean interface using the same pattern as
property and billing adapters.

## Description

Implement the objection status query endpoint, the status history endpoint, and
the municipality response ingestion webhook/poll adapter. All status transitions
are written to `ObjectionStatusHistory`. When a status change arrives, the
service calls notification-service to alert the user.

## Purpose

Covers the TRACKING & RESOLUTION Figma flow: Track Objection Status → Status?
(Pending / Upheld / Rejected / More Info Requested) → all four terminal branches,
including escalation and upload-requested-docs.

## Goal

`easy_rates/backend/services/status-service/` — status query and history routes
implemented; municipality response adapter is one replaceable function; all four
TRACKING Figma status branches covered by seed data and integration smoke.

## Tasks

- [ ] ⚠️ T1  Write the municipality response adapter interface at
  `easy_rates/backend/shared/adapters/municipality-response-adapter.ts`:

  ```ts
  export type ObjectionStatus =
    'PENDING' | 'UPHELD' | 'REJECTED' | 'MORE_INFO_REQUESTED'

  export interface MunicipalityResponse {
    objectionRefNumber: string
    status: ObjectionStatus
    note: string | null
    adjustedAmount: number | null
    updatedAt: string
  }
  export interface MunicipalityResponseAdapter {
    fetchStatus(refNumber: string): Promise<MunicipalityResponse | null>
  }
  ```

  Stub implementation returns seed-controlled status responses.
  Done when: interface and stub exist; stub compiles.

- [ ] ⚠️ T2  `GET /status/:refNumber` — query objection status:
  - Call `municipalityAdapter.fetchStatus(refNumber)`
  - If adapter returns a status newer than the latest `ObjectionStatusHistory`
    row: write a new history row via Prisma; call `POST /notify` fire-and-forget
    (do not `await` — a notification failure must not block the status query response)
  - Return 200 + `{ status, note, adjustedAmount, history: [...] }`, or 404
  Done when: curl returns status + history; new history row written when status
  changes; notification-service called on change.

- [ ] ⚠️ T3  `GET /status/:refNumber/history` — return full status history:
  - Return `ObjectionStatusHistory` rows ordered by `updatedAt` desc
  Done when: curl returns ordered history array.

- [ ] ⚠️ T4  `POST /status/ingest` — municipality webhook endpoint (for when
  municipality pushes status updates rather than requiring polling):
  - Accept `{ refNumber, status, note, adjustedAmount }`
  - Write `ObjectionStatusHistory` row; call `POST /notify` fire-and-forget
    (do not `await` — a notification failure must not cause the ingest to fail)
  - Return 200
  Done when: curl POST /status/ingest → history row in psql + notification log.

- [ ] ⚠️ T5  Seed data for all four TRACKING Figma status branches (add to
  `prisma/seed.ts`):
  - PENDING (no municipality response yet)
  - UPHELD (adjustedAmount set, notification triggered)
  - REJECTED (note explaining rejection)
  - MORE_INFO_REQUESTED (upload-requested-docs branch)
  Done when: `pnpm db:seed` runs; psql confirms ObjectionStatusHistory rows
  covering all four statuses.

- [ ] ⚠️ T6  Unit tests: status found (all four statuses), status not found → 404,
  ingest webhook creates history row, duplicate ingest (same status) is idempotent.
  Done when: `pnpm test` passes in status-service directory.

- [ ] ⚠️ T7  Integration smoke covering all four TRACKING branches:
  ```
  ▶ Status: Pending
    curl GET /status/REF001 → assert 200, status=PENDING

  ▶ Status: Upheld
    curl POST /status/ingest { refNumber: REF001, status: UPHELD, adjustedAmount: 450 }
    psql: SELECT status, "adjustedAmount" FROM "ObjectionStatusHistory" WHERE ...
    NotificationLog: row with type STATUS_CHANGE

  ▶ Status: Rejected
    curl GET /status/REF002 → status=REJECTED, note present

  ▶ Status: More Info Requested
    curl GET /status/REF003 → status=MORE_INFO_REQUESTED
  ```
  Done when: all four branches confirmed with psql state.

## Recommended skill

▶ `/build-to-contract` ✅ — builds status routes from the API contract in
   `system-design/api/status.md`.
   alt: `/architect-contract` ✅ — for finalising the municipality response
   adapter interface before T1.

## Engagement Instructions

```bash
# 1. Municipality response adapter interface exists
ls easy_rates/backend/shared/adapters/municipality-response-adapter.ts
# Expected: present

# 2. Unit tests green
cd easy_rates/backend/services/status-service && pnpm test
# Expected: all tests pass (4 statuses + not found + ingest idempotency)

# 3. Status: Pending — 200 + PENDING from seed data
BODY=$(curl -s http://localhost:${STATUS_PORT:-3008}/status/REF001)
echo "status: $(echo $BODY | jq -r '.status')"   # Expected: PENDING

# 4. Ingest webhook: UPHELD + history row + NotificationLog STATUS_CHANGE
curl -s -X POST http://localhost:${STATUS_PORT:-3008}/status/ingest \
  -H "Content-Type: application/json" \
  -d '{"refNumber":"REF001","status":"UPHELD","note":null,"adjustedAmount":450}' | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT status, \"adjustedAmount\" FROM \"ObjectionStatusHistory\" WHERE status='UPHELD' ORDER BY \"updatedAt\" DESC LIMIT 1;"
psql "$DATABASE_URL" -t -c \
  "SELECT type, status FROM \"NotificationLog\" WHERE type='STATUS_CHANGE' ORDER BY \"sentAt\" DESC LIMIT 1;"
# Expected: history row with adjustedAmount=450; NotificationLog STATUS_CHANGE row

# 5. All 4 TRACKING branches reachable via curl
for ref_status in "REF001:UPHELD" "REF002:REJECTED" "REF003:MORE_INFO_REQUESTED"; do
  REF=$(echo $ref_status | cut -d: -f1)
  EXP=$(echo $ref_status | cut -d: -f2)
  STATUS=$(curl -s "http://localhost:${STATUS_PORT:-3008}/status/$REF" | jq -r '.status')
  printf "%-10s expected: %-25s got: %s\n" "$REF" "$EXP" "$STATUS"
done
# Expected: each matches expected status

# 6. Duplicate ingest is idempotent — no duplicate history rows
curl -s -X POST http://localhost:${STATUS_PORT:-3008}/status/ingest \
  -H "Content-Type: application/json" \
  -d '{"refNumber":"REF001","status":"UPHELD","note":null,"adjustedAmount":450}' | jq .
psql "$DATABASE_URL" -t -c \
  "SELECT COUNT(*) FROM \"ObjectionStatusHistory\" WHERE status='UPHELD';"
# Expected: still 1 row (idempotent)

# 7. Swappability: adapter wired only in factory/DI
grep -r "municipality-response-adapter" \
  easy_rates/backend/services/status-service/ 2>/dev/null
# Expected: 0 results
```

Gate: check 4 must show both ObjectionStatusHistory AND NotificationLog rows —
a status change without a notification is a functional defect. All four TRACKING
Figma terminal states (check 5) must be exercisable with psql confirmation at
each step before plan/07 (flow walkthrough) may include this flow.
