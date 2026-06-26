# EasyRates Mobile App — Backend Implementation

## Mission

Stand up the complete backend the Flutter mobile app calls — database, services,
queues, document storage, and the patterns chosen in the System Design ADR — so
that all seven EasyRates process flows (Onboarding, Find Property, Bill Review,
Evidence & Challenge, Submission, Tracking & Resolution, Account & Settings) are
runnable end-to-end from a terminal or skeleton frontend against a locally running
Podman Compose stack.

This scope serves the **Flutter mobile app exclusively**. The WhatsApp bot is a
separate channel and is out of scope. "Runnable" means a developer can trace
every Figma screen transition to a specific terminal command, SQL row, or HTTP
call — not just an exit-0 smoke script.

Tech stack (from ADR-001 in easy_rates/system-design/):

- Runtime: Node.js (TypeScript)
- ORM: Prisma (migration-first, PostgreSQL adapter)
- Auth: JWT (access + refresh tokens); bcrypt for password hashing
- OTP: Twilio SMS (Verify API or Programmable Messaging — from ADR)
- Queue: [decided in ADR-001 — RabbitMQ / Redis Streams / BullMQ]
- Database: PostgreSQL (primary store) + Redis (OTP TTL + session cache)
- Document storage: Azure Blob Storage (or S3-compatible) for uploaded docs
- Container runtime: Podman + podman-compose
- Config validation: Zod schema over process.env — fail fast at startup
- API style: REST (JSON) — paths from easy_rates/system-design/api/

Services (from system design bounded contexts):

1. auth-service        — registration, login, JWT issuance, forgot-password
2. otp-service         — Twilio dispatch, OTP validation, expiry, resend
3. property-service    — account-number lookup, address/ERF manual search
4. queue-consumer      — processes async OTP and notification jobs
5. bill-service        — bill fetch, line items, anomaly detection, AI expected amount
6. objection-service   — document upload, objection creation, submission, ref generation
7. notification-service — SMS/push dispatch for submission confirmation, status alerts
8. status-service      — objection status polling, municipality response ingestion
9. account-service     — profile settings, linked properties, notification preferences, history

## Objectives

1. **Gap report** — Figma PDF + ADR-001 ingested; every screen transition across
   all seven flows mapped to an API route; gap-report.md is empty before service
   implementation starts.
2. **Scaffold + configuration** — monorepo structure, shared types, Zod-validated
   env config that fails fast on missing variables, Podman Compose with all
   services + infra (PostgreSQL + Redis + queue broker + blob storage),
   health endpoints that report DB and queue connectivity.
3. **Database design + ORM** — complete entity-relationship model derived from all
   seven Figma flows; PostgreSQL schema in Prisma (normalized to 3NF minimum);
   all tables, columns, constraints, and indexes defined; migrations committed;
   seed data covering every Figma decision-point outcome across all flows.
4. **Auth service** — POST /auth/register, POST /auth/login, POST /auth/refresh,
   POST /auth/forgot-password; Prisma-backed; unit-tested.
5. **OTP service** — Twilio integration, OTP lifecycle (send, verify, expire,
   resend) via Redis TTL; all OTP state traceable in Redis and PostgreSQL AuditLog.
6. **Queue** — producer in auth-service, consumer in otp-service, dead-letter
   queue, broker in Podman Compose; full message lifecycle visible.
7. **Property service** — account-number lookup and address/ERF fuzzy search;
   swappable real-data adapter interface.
8. **Bill service** — bill fetch by account number, line items breakdown, anomaly
   flags, AI-calculated expected amount; municipality billing adapter stubbed with
   a clean interface.
9. **Objection service** — document upload to blob storage, objection creation,
   submission to municipality adapter, reference number generation; all state in
   PostgreSQL.
10. **Notification service** — dispatch SMS/push notifications for OTP, submission
    confirmation, and status change alerts; delivery log in PostgreSQL.
11. **Status service** — objection status query, municipality response ingestion,
    status history; municipality response adapter stubbed with a clean interface.
12. **Account service** — user profile CRUD, linked properties management,
    notification preference settings, objection history query.
13. **End-to-end flow verification** — every Figma screen transition across all
    seven flows exercisable via a terminal walkthrough (HTTP calls + psql queries)
    or a skeleton frontend; DB state visible at each decision point.

Gate rule: Objectives 4–12 (services) cannot start until Objective 3 (database +
Prisma schema) is complete and migrations run on the local stack. No service may
bypass the ORM by writing raw SQL in route handlers.

## Goals

- G0  `easy_rates/backend/docs/gap-report.md` — empty (zero unmatched transitions
  or routes across all seven flows) before any service implementation starts.
- G1  `easy_rates/backend/podman-compose.yml` — all nine services + postgres +
  redis + queue broker + blob storage emulator; `podman-compose up` starts
  cleanly; each service `/health` returns DB + queue connectivity status.
- G2  `easy_rates/backend/prisma/schema.prisma` — complete schema covering all
  seven flows: User, Account, Property, OTPRecord, RefreshToken, AuditLog, Bill,
  BillLineItem, Objection, Document, ObjectionStatusHistory,
  UserNotificationPreference. All relationships defined; indexes on lookup
  columns. `prisma/seed.ts` covers every Figma decision-point outcome.
- G3  `easy_rates/backend/services/auth-service/` — implemented; unit + integration tests green.
- G4  `easy_rates/backend/services/otp-service/` — Twilio wired; Redis TTL enforced;
  TWILIO_MOCK=true for CI.
- G5  `easy_rates/backend/queue/` — producer + consumer + DLQ; message lifecycle visible.
- G6  `easy_rates/backend/services/property-service/` — four Figma FIND PROPERTY
  branches covered; real-data adapter is one replaceable function.
- G7  `easy_rates/backend/services/bill-service/` — bill fetch, line items, anomaly
  flags, AI expected amount; municipality billing adapter stubbed with a clean
  interface identical in shape to property-adapter.
- G8  `easy_rates/backend/services/objection-service/` — document upload to blob
  storage, objection lifecycle (create → submit → ref number); all state in psql.
- G9  `easy_rates/backend/services/notification-service/` — SMS/push dispatch for
  all notification touchpoints; delivery log in AuditLog.
- G10 `easy_rates/backend/services/status-service/` — status query, municipality
  response ingestion; municipality response adapter is one replaceable function.
- G11 `easy_rates/backend/services/account-service/` — profile CRUD, linked
  properties, notification preferences, objection history.
- G12 `easy_rates/backend/scripts/flow-walkthrough.sh` — narrated terminal script
  covering every Figma decision-point branch across all seven flows. Each step:
  named curl call with screen label, then psql query showing resulting DB state.
  Exits 0 on all-pass, 1 with a named error on any failure.

## Expected Outcome

A developer can verify the complete app — all seven process flows — either by
running the narrated terminal walkthrough (HTTP calls + psql queries) or by
driving a skeleton frontend against the local stack. Either path covers every
Figma screen transition as a named step, with the HTTP response and the resulting
database row visible at each decision point — no production GUI required.

## Definition of Done

1. `podman-compose up` starts all services with zero errors.
2. Each service `/health` returns `{ status: "ok", db: "connected", queue: "connected" }`.
3. `pnpm db:migrate` applies all migrations with zero errors on a fresh database.
4. `pnpm db:seed` populates all fixture data covering every Figma branch across
   all seven flows.
5. `bash scripts/flow-walkthrough.sh` exits 0 against the local stack, with every
   Figma decision-point branch represented across all seven flows.
6. Alternatively, a skeleton frontend (or Postman/Bruno collection) can drive
   every Figma screen transition and reach the expected terminal state.
7. After the walkthrough, `psql` shows rows in all tables corresponding to the
   operations performed.
8. Database schema is 3NF — no transitive dependencies, no repeating groups,
   every non-key column depends on the whole key.
9. No hardcoded credentials — all secrets in `.env`; startup fails with a clear
   error message if any required variable is missing.
10. Property, bill, and status services each expose a single replaceable adapter
    function with an interface comment; zero route handler changes needed to swap
    in the real municipal data source.
11. `easy_rates/backend/docs/gap-report.md` is empty across all seven flows.

Note: The Figma PDF and ADR-001 are both required inputs before Objective 3
starts. If either is unavailable, block and surface — do not start schema design
blind.

## JIRA Binding

to be added — read from here once populated

## Sub-Scopes

none yet

## Plans

- ⚠️ [00-ingest-adr.md](plans/00-ingest-adr.md) — ingest Figma PDF + ADR-001; cross-check all seven flows → routes; gap-report.md empty before plan/01 starts
- ⚠️ [01-scaffold.md](plans/01-scaffold.md) — monorepo layout, Zod env config, Podman Compose, /health endpoints ⛔ BLOCKED[Gate: ADR-001 + gap-report.md empty]
- ⚠️ [02-database.md](plans/02-database.md) — ER model (all 7 flows), Prisma schema (3NF), migrations, seed data ⛔ BLOCKED[Gate: ADR-001 + gap-report.md empty]
- ⚠️ [03-auth-service.md](plans/03-auth-service.md) — register, login, refresh, forgot-password ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [04-otp-service.md](plans/04-otp-service.md) — Twilio consumer, verify, resend, DLQ; OTP state in Redis + psql ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [05-queue-wiring.md](plans/05-queue-wiring.md) — producer, consumer, DLQ, full message lifecycle visible ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [06-property-service.md](plans/06-property-service.md) — account lookup, manual search, swappable adapter ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [07-flow-walkthrough.md](plans/07-flow-walkthrough.md) — narrated terminal script; all seven flows; exits 0 with psql state ⛔ BLOCKED[Gate: plans/03–12 complete]
- ⚠️ [08-bill-service.md](plans/08-bill-service.md) — bill fetch, line items, anomaly flags, AI expected amount, billing adapter ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [09-objection-service.md](plans/09-objection-service.md) — doc upload, objection creation, submission, ref generation ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [10-notification-service.md](plans/10-notification-service.md) — SMS/push dispatch, delivery log, all notification touchpoints ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [11-status-service.md](plans/11-status-service.md) — status query, municipality response ingestion, status history ⛔ BLOCKED[Gate: plan/02 complete]
- ⚠️ [12-account-service.md](plans/12-account-service.md) — profile CRUD, linked properties, notification prefs, objection history ⛔ BLOCKED[Gate: plan/02 complete]
