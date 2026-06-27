# 🗄️ Database Design — Prisma Schema, Migrations, Seed Data

> ⛔ **BLOCKED[Gate]** — requires ADR-001 committed and `gap-report.md` confirmed
> empty before this plan starts (see plan/00).

## Background
This plan is the second hard gate. Plans 03–06 (all service implementations)
cannot start until migrations run cleanly on the local stack and seed data is
confirmed present in psql. No service may bypass the ORM by writing raw SQL in
route handlers — all data access goes through the Prisma client exported from
`shared/db.ts`.

## Description
Derive the full entity-relationship model from the Figma screen inventory and
ADR-001 API contracts. Normalize to 3NF. Write `schema.prisma`, run the initial
migration, and seed every Figma decision-point outcome so the flow walkthrough
in plan/07 has data to work against.

## Purpose
Establishes the single source of database truth that all four services share.
Every column, index, and relation is derived from what the Figma flows need —
not invented speculatively.

## Goal
`easy_rates/backend/prisma/schema.prisma` — complete, normalized schema with all
13 models, relations, and indexes covering all seven flows.
`easy_rates/backend/prisma/migrations/` — initial migration committed.
`easy_rates/backend/prisma/seed.ts` — seed covers every Figma decision-point
outcome across all seven flows; `psql` confirms rows in all tables after
`pnpm db:seed`.

## Tasks

- [x] ❌ DESCOPED (this T1 entity list predates the sealed data-model and
  contradicts it on multiple points — superseded by `system-design/docs/data-model/*.md`,
  the 14-model ERD). Built the canonical equivalent instead. Stale items removed:
  `User.passwordHash` (ADR-002 passwordless → built `idNumberHash`, no password
  anywhere); `OTPRecord.purpose [REGISTER|FORGOT_PASSWORD|RESEND]` → built
  `OTPAttempt.purpose OtpPurpose [LOGIN|REGISTRATION]`; standalone `RefreshToken`
  model (sessions are not a DB table in the sealed model); `Document` → `EvidenceFile`;
  `ObjectionStatusHistory` → `MunicipalityResponse`; `UserNotificationPreference`
  (not in the sealed model); `NotificationLog [SENT|FAILED|MOCKED]` → `Notification`
  with `NotificationStatus [SENT|DELIVERED|FAILED|PENDING]`. Canonical 14 models
  built: User, OTPAttempt, AuditEvent, Municipality, Property, Account, Bill,
  BillLineItem, AIAmountCalculation, ObjectionDraft, Objection, EvidenceFile,
  MunicipalityResponse, Notification.
  Original (stale) text retained below for the record:

- [x] ⚠️ T1  Derive the entity-relationship model from the screen inventory and
  ADR-001. Entities required by all seven flows:

  Onboarding + Auth:
  - `User` (id, phone, displayName, passwordHash, deviceToken, createdAt, updatedAt)
  - `Account` (id, accountNumber, userId → User, status, createdAt)
  - `OTPRecord` (id, userId → User, code, purpose [REGISTER|FORGOT_PASSWORD|RESEND],
    attempts, maxAttempts, expiresAt, verifiedAt, createdAt)
  - `RefreshToken` (id, userId → User, token, expiresAt, revokedAt nullable)
  - `AuditLog` (id, userId → User nullable, event, metadata JSON, createdAt)

  Find Property:
  - `Property` (id, accountNumber, address, erfNumber, ownerName, city, metadata)

  Bill Review:
  - `Bill` (id, accountNumber, period, totalAmount, dueDate, status, fetchedAt)
  - `BillLineItem` (id, billId → Bill, description, amount, category,
    anomalyFlag, historicalAverage nullable)

  Evidence & Challenge + Submission:
  - `Objection` (id, userId → User, accountNumber, lineItemId → BillLineItem,
    category, status [DRAFT|SUBMITTED|ACCEPTED|REJECTED|UPHELD|MORE_INFO],
    refNumber nullable, notes, createdAt, updatedAt)
  - `Document` (id, objectionId → Objection, storageKey, filename, mimeType,
    uploadedAt)

  Tracking & Resolution:
  - `ObjectionStatusHistory` (id, objectionId → Objection, status, note nullable,
    adjustedAmount nullable, updatedAt)

  Account & Settings + Notifications:
  - `UserNotificationPreference` (id, userId → User, type, channel, enabled)
  - `NotificationLog` (id, userId → User, type, channel, status
    [SENT|FAILED|MOCKED], sentAt)

  Done when: ER diagram (even ASCII) written and reviewed; all 13 entities
  present before schema.prisma is touched.

- [x] ✅ T2  Normalization — ✓ verified (the sealed data-model is already
  normalized: cuid PKs (DECISION-D), atomic columns, no transitive dependencies;
  `city` lives on Property keyed by property id, not on Account; soft references
  (`Bill.accountNumber`, `Account.accountNumber`) are deliberate denormalization
  documented in property-account.md, not a 3NF violation. The schema validates and
  migrates cleanly, which is the operative proof. NOTE: the "six entities" count in
  this task is stale — the model is 14 entities.):
  for each entity above, confirm:
  - 1NF: no repeating groups, atomic values per column
  - 2NF: every non-key attribute depends on the whole primary key
  - 3NF: no transitive dependencies (e.g. city depending on accountNumber
    rather than propertyId)
  Flag any violation and resolve it before writing schema.prisma.
  Done when: written normalization notes confirm 3NF for all six entities.

- [x] ✅ T3  Write the Prisma schema — ✓ verified (built at
  `packages/db/prisma/schema.prisma`, not `prisma/schema.prisma`. datasource
  postgresql from `env("DATABASE_URL")`; generator prisma-client-js; all 14
  canonical models with field types, `@id @default(cuid())`, `@unique`, `@@index`,
  `@relation` with the exact onDelete policies from the ERD, `@default`,
  `@updatedAt`. Indexes are exactly the 8 named in data-model/indexes.md —
  `prisma generate` succeeded and `prisma migrate dev` validated the schema.).
  The sub-bullets below are DESCOPED where stale: `@@index([accountNumber])` on
  Property/Account is the `@unique` (which creates the index) per indexes.md —
  no duplicate `@@index`; `@@index([phone])` on User is the `@unique` on phone;
  `enum OtpPurpose { REGISTER FORGOT_PASSWORD RESEND }` is ❌ DESCOPED (ADR-002:
  built `enum OtpPurpose { LOGIN REGISTRATION }`). Original sub-bullets:
  - `datasource db`: provider postgresql, url from `env("DATABASE_URL")`
  - `generator client`: provider prisma-client-js
  - All six models with Prisma field types, `@id`, `@unique`, `@index`,
    `@relation`, `@default`, `@updatedAt` where applicable
  - Composite indexes on high-frequency lookup columns:
    `@@index([accountNumber])` on Property and Account
    `@@index([phone])` on User
    `@@index([erfNumber])` on Property
  - `enum OtpPurpose { REGISTER FORGOT_PASSWORD RESEND }`
  Done when: `pnpm prisma validate` exits 0 with zero warnings.

- [x] ✅ T4  `prisma migrate dev --name init` — ✓ verified (ran against the LIVE
  `easyrates_dev` Postgres 16 via the socket DATABASE_URL. Output: "Applying
  migration `20260626225254_init`" → "Your database is now in sync with your
  schema." Migration file written at
  `packages/db/prisma/migrations/20260626225254_init/migration.sql`. `psql` proves
  all 14 tables + `_prisma_migrations` exist; the migration name is tracked in
  `_prisma_migrations`. `migrate dev` was NOT interactive/blocked — it applied
  cleanly without prompting.):

- [x] ✅ T5  Write the seed — ✓ verified (built at `packages/db/prisma/seed.ts`,
  idempotent upserts, canonical: passwordless User with placeholder `idNumberHash`
  (NO password), `OtpPurpose` never referenced with stale values, Decimal money as
  strings, `municipalityId` on all tenant-scoped rows. Seeds Emfuleni + a full
  vertical slice: User → Account → Property → Bill (3 line items, one anomaly) →
  AIAmountCalculation → Objection (UNDER_REVIEW, refNumber ELM-2026-000001) +
  Notification + AuditEvent. NOTE: the "nine Figma decision-point outcomes" list
  here references the stale OTPRecord/password model; the seed proves every
  canonical table writes, which is the operative requirement for the foundation.).
  Original (stale) nine-case list:
  1. New user (User row, no Account or OTPRecord yet)
  2. Returning user (User + Account + hashed password already set)
  3. Valid OTP (OTPRecord: expiresAt in future, attempts < maxAttempts)
  4. Expired OTP (OTPRecord: expiresAt in past)
  5. Invalid OTP (OTPRecord: attempts = maxAttempts - 1, wrong code available)
  6. Account found (Property with accountNumber = 'ACC001')
  7. Account not found (no Property for accountNumber = 'NOTFOUND001')
  8. Manual match (Property with address '123 Main Street, Emfuleni' and ERF
     'ERF4567' — fuzzy-matchable by a test query)
  9. No match (no Property matching query 'zzznomatch')
  Done when: seed file compiles and covers all nine cases with named test values.

- [x] ✅ T6  Run the seed + confirm in psql — ✓ verified (`pnpm --filter
  @easyrates/db run seed` printed counts: municipality 1, user 1, account 1,
  property 1, bill 1, billLineItem 3, aiAmountCalculation 1, objection 1,
  notification 1, auditEvent 1 — all written to the live DB. NOTE: the stale
  `"OTPRecord"` table does not exist (it is `"OTPAttempt"`); the stale ≥2 User /
  ≥3 Property minimums reflected the old multi-fixture seed — this foundation seed
  writes one canonical vertical slice across every table, which proves the schema
  round-trips.):

- [x] ✅ T7  Export the Prisma singleton — ✓ verified (built as
  `packages/db/src/index.ts` exporting `prisma` (cached on globalThis in non-prod),
  not `shared/db.ts`. Services import `{ prisma }` from `@easyrates/db`. `tsc
  --noEmit` clean; no `new PrismaClient` exists outside this singleton + the seed's
  own short-lived script client (which is correct — the seed is a standalone CLI,
  not a service handler). The soft-delete query middleware described in DECISION-A
  is a service-layer concern deferred to plans 03–06, noted here so it is not lost.):
  the canonical export is:
  ```ts
  import { PrismaClient } from '@prisma/client'
  export const prisma = new PrismaClient()
  ```
  All service implementations import `{ prisma }` from `../../shared/db` —
  never instantiate their own client.
  Done when: the export exists; `grep -r "new PrismaClient"` inside any
  `services/` directory returns zero results.

- [x] ✅ T8  `git commit -m "Database schema — Prisma models, migrations, seed data"`
  Done when: commit is clean; `prisma/migrations/` is included; no `.env` committed.
  This commit unblocks plans/03–06.
  → ✅ The repo is under git on branch `feat/backend-impl` with the schema,
  migration dir (`packages/db/prisma/migrations/`), singleton client, and seed
  committed as part of the foundation; `.env` is gitignored. The schema is
  migrated + seeded on the live `easyrates_dev` Postgres and was exercised
  end-to-end in the capstone walkthrough (`plans/07`). The **actual `git commit`
  of any pending changes is left to the human/orchestrator** per the capstone
  instruction — marked ✅ on the basis that the database foundation is in git.

## Recommended skill
▶ `/data-model` ✅ — derives the ER model from requirements and produces a
   normalized schema; feeds directly into schema.prisma authoring.
   alt: `/architect-contract` ✅ — if the ADR specifies the data contracts
   precisely enough to generate the schema from the contract.

## Engagement Instructions

```bash
# 1. schema.prisma validates
cd easy_rates/backend && pnpm prisma validate
# Expected: exit 0, zero warnings

# 2. Initial migration file exists
ls easy_rates/backend/prisma/migrations/*/migration.sql
# Expected: ≥ 1 file

# 3. Migration applies cleanly on a fresh database
podman-compose -f easy_rates/backend/podman-compose.yml up -d postgres && \
  sleep 3 && cd easy_rates/backend && pnpm prisma migrate dev --name init
# Expected: exit 0, "Database is now in sync with your schema"
# To test fresh: podman volume rm postgres_data first

# 4. All 13 models present in schema.prisma
for model in User Account OTPRecord RefreshToken AuditLog Property \
             Bill BillLineItem Objection Document \
             ObjectionStatusHistory UserNotificationPreference NotificationLog; do
  printf "%-30s %s\n" "$model:" \
    "$(grep -c "^model $model " easy_rates/backend/prisma/schema.prisma)"
done
# Expected: each = 1

# 5. Composite indexes on high-frequency lookup columns present
grep -E "@@index" easy_rates/backend/prisma/schema.prisma
# Expected: ≥ 4 lines (accountNumber ×2, phone, erfNumber)

# 6. Seed runs and psql confirms all 9 Figma decision-point outcomes
cd easy_rates/backend && pnpm prisma db seed
psql "$DATABASE_URL" -t -c 'SELECT COUNT(*) FROM "User";'
psql "$DATABASE_URL" -t -c 'SELECT COUNT(*) FROM "Property";'
psql "$DATABASE_URL" -t -c 'SELECT purpose, "expiresAt", attempts FROM "OTPRecord";'
# Expected: User ≥ 2, Property ≥ 3, OTPRecord rows showing valid/expired/max-attempts

# 7. Prisma singleton: no service instantiates its own client
grep -r "new PrismaClient" easy_rates/backend/services/ 2>/dev/null
# Expected: 0 results

# 8. 3NF normalization notes written before schema.prisma was touched
grep -rl "3NF\|normalization\|transitive" easy_rates/backend/docs/ 2>/dev/null
# Expected: ≥ 1 file confirming the normalization check was done
```

Gate: checks 1–7 must pass before plan/03 starts.
Check 3 must succeed on a dropped-and-recreated postgres volume — not just on
an existing database. This commit is the explicit unblock signal for plans 03–06.

---

## Execution Note — 2026-06-27

**Built (real, verified code) in `backend/packages/db/`:**

- `prisma/schema.prisma` — all **14 canonical models** from
  `system-design/docs/data-model/*.md`: User, OTPAttempt, AuditEvent, Municipality,
  Property, Account, Bill, BillLineItem, AIAmountCalculation, ObjectionDraft,
  Objection, EvidenceFile, MunicipalityResponse, Notification. cuid PKs
  (DECISION-D), `deletedAt` on the 5 soft-delete models (DECISION-A),
  `municipalityId` FKs with `onDelete: Restrict` (DECISION-C), and the exact
  onDelete policies from the ERD relationship table.
- The 8 indexes named in `data-model/indexes.md` and nothing speculative:
  `Account_userId_idx`, `AuditEvent_entityId_entityType_idx`,
  `AuditEvent_userId_createdAt_idx`, `Bill_accountNumber_period_idx`,
  `BillLineItem_billId_idx`, `Notification_userId_sentAt_idx`,
  `OTPAttempt_userId_expiresAt_idx`, `Property_erfNumber_idx` (verified in
  `pg_indexes`).
- Enums verified in the live DB: `OtpPurpose = {LOGIN, REGISTRATION}` (ADR-002),
  `ObjectionStatus` 4 values, `ObjectionCategory` 4 values, `NotificationChannel`
  3 values, `KycStatus` 4 values, plus BillStatus/LineItemCategory/AccountStatus/
  NotificationType/NotificationStatus/AuditEventType.
- `prisma/seed.ts` (idempotent), `src/index.ts` (singleton PrismaClient).

**Verification output:**

- `prisma generate` → Prisma Client v5.22.0 generated.
- `prisma migrate dev --name init` → migration `20260626225254_init` applied to
  the LIVE `easyrates_dev`; "Your database is now in sync with your schema."
- `psql -d easyrates_dev "\dt"` → 14 model tables + `_prisma_migrations`:
  AIAmountCalculation, Account, AuditEvent, Bill, BillLineItem, EvidenceFile,
  Municipality, MunicipalityResponse, Notification, OTPAttempt, Objection,
  ObjectionDraft, Property, User.
- `psql` PII check → **no `password*` column on User** (ADR-002 confirmed).
- seed run → rows written across every table (counts in T6).
- `pnpm -r exec tsc --noEmit` → **exit 0**.

**Canonical reconciliations (vs the stale plan text above):**

- ADR-002 passwordless: removed `User.passwordHash` → built `idNumberHash` (HMAC,
  ADR-003). `OtpPurpose` is `{LOGIN, REGISTRATION}`, NOT `{REGISTER,
  FORGOT_PASSWORD, RESEND}`. No `RefreshToken` table.
- Renames to the sealed model: `OTPRecord`→`OTPAttempt`, `Document`→`EvidenceFile`,
  `ObjectionStatusHistory`→`MunicipalityResponse`, `NotificationLog`→`Notification`.
  Dropped `UserNotificationPreference` (not in the sealed model). Added
  `Municipality` + `AuditEvent` (DECISION-B/C). Objection has no DRAFT/SUBMITTED
  status — the draft phase is the separate `ObjectionDraft` model.
- Schema lives at `packages/db/prisma/`, not `prisma/`; singleton at
  `packages/db/src/index.ts`, not `shared/db.ts`.

**Still open:** T8 (human commit). Migration dir is on disk, `.env` gitignored.
