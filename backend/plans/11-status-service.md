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

  - [x] ❌ DESCOPED (2026-06-27) T1  The status-service is **dissolved** by the
    canonical plan: status *reads* moved to objection-service (`GET /objections/:ref/status`,
    built in plan 09), and status *ingestion* is the **municipality-service** CRM
    webhook (built this build). There is no polling `fetchStatus` adapter — the
    municipality pushes resolutions in. The old enum is also wrong (`PENDING` is
    not a value; canonical is UNDER_REVIEW/MORE_INFO_REQUESTED/UPHELD/REJECTED).

- [x] ✅ — ✓ verified (2026-06-27) T2  Status read = `GET /objections/:ref/status`
  (built in objection-service, plan 09 — the dissolved status-service folds here).
  Returns `{ refNumber, status, submittedAt, lastUpdatedAt, statusTimeline,
  disputedItems, municipalityResponse }`; 404 unknown ref, 403 not owned. The
  timeline is derived from `submittedAt` + the `MunicipalityResponse` rows (no
  separate history table). Verified via smoke (200 with timeline).

- [x] ❌ DESCOPED (2026-06-27) T3  `GET /status/:refNumber/history` separate
  endpoint. The canonical contract folds the timeline INTO `GET /objections/:ref/status`
  (the `statusTimeline` field) — there is no standalone history route and no
  `ObjectionStatusHistory` table (the timeline is composed from `MunicipalityResponse`).

- [x] ✅ — ✓ verified (2026-06-27) T4  Municipality ingestion webhook —
  `POST /municipality/objections/:ref/response` (canonical path, NOT `/status/ingest`).
  Auth via `X-Municipal-Webhook-Secret` (constant-time compare), NOT a JWT.
  Required `idempotencyKey` with 30-day Redis dedup (replay returns the original
  200, no side effects). State machine: terminal UPHELD/REJECTED → **409**
  (re-open blocked); illegal/no-op → **422** with `{currentStatus, requestedStatus}`;
  valid → write MunicipalityResponse (in a txn with the status update) + enqueue
  the notification. **Every** response INSERTs a MunicipalityResponse for audit,
  even on 409. Verified via smoke: valid UNDER_REVIEW→UPHELD (200, status advanced,
  MunicipalityResponse row, notification enqueued) → replay (200 original, no dup)
  → terminal-reopen (409) → bad secret (401) → illegal no-op (422 w/ details).
  psql confirmed 2 MunicipalityResponse rows (the UPHELD + the audited-but-not-
  applied REJECTED) and the UPHELD objection status.

- [x] ✅ — ✓ verified (2026-06-27) T5  The seed objection `ELM-2026-000001`
  (UNDER_REVIEW) is the live fixture the webhook smoke advances through the state
  machine (→ UPHELD, then a blocked → REJECTED). No `ObjectionStatusHistory` seed
  rows (that table is DESCOPED); `PENDING` is not a canonical status.

- [x] ✅ — ✓ verified (2026-06-27) T6  Unit tests (vitest, 9 passing):
  `classifyTransition` (all legal apply paths, terminal→409, no-op→422),
  `isTerminal`, `secretMatches` (match / wrong / length-mismatch / empty),
  `decideIdempotency` (process vs replay). The live idempotency replay is also
  proven in the smoke against real Redis.

- [x] ✅ — ✓ verified (2026-06-27) T7  Integration smoke vs live DB + Redis drove
  the webhook state machine on the canonical routes: UNDER_REVIEW → UPHELD (200,
  status advanced, MunicipalityResponse + Notification rows), idempotency replay
  (200 original, no dup), terminal-reopen → 409, bad secret → 401, illegal no-op
  → 422 with `{currentStatus, requestedStatus}`. The reader side
  (`GET /objections/:ref/status`) returned the timeline. psql confirmed the rows.
  (The old `/status/ingest` + `ObjectionStatusHistory` + `STATUS_CHANGE` shapes are
  DESCOPED.)

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

---

## Execution Note — 2026-06-27

The status-service is **dissolved** per the canonical plan. Its two halves were built where
the contracts now place them:
- **Status reads** → `GET /objections/:ref/status` in **objection-service** (plan 09): the
  `statusTimeline` is composed from `submittedAt` + the `MunicipalityResponse` rows (no
  `ObjectionStatusHistory` table).
- **Status ingestion** → the **municipality-service** CRM webhook
  `POST /municipality/objections/:ref/response` (built this build). Webhook-secret auth (NOT
  a JWT), required `idempotencyKey` with 30-day Redis dedup, the 4-value state machine
  (terminal→409, illegal/no-op→422 with details), MunicipalityResponse INSERT (always, for
  audit) + status update in one txn + enqueued notification.

This plan predated the canonical contracts and described singular `/status/*` routes, a
polling `fetchStatus` adapter, a `PENDING` status, and an `ObjectionStatusHistory` table — all
superseded. Verified: `pnpm -r exec tsc --noEmit` → 0; 9 unit tests green; live-DB+Redis smoke
(transcript + psql). Honest ⚠️: the source-IP allowlist and full rate-limit infra are not built.
