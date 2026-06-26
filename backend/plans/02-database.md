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

- [ ] ⚠️ T1  Derive the entity-relationship model from the screen inventory and
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

- [ ] ⚠️ T2  Normalization check — for each entity above, confirm:
  - 1NF: no repeating groups, atomic values per column
  - 2NF: every non-key attribute depends on the whole primary key
  - 3NF: no transitive dependencies (e.g. city depending on accountNumber
    rather than propertyId)
  Flag any violation and resolve it before writing schema.prisma.
  Done when: written normalization notes confirm 3NF for all six entities.

- [ ] ⚠️ T3  Write `easy_rates/backend/prisma/schema.prisma`:
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

- [ ] ⚠️ T4  `pnpm prisma migrate dev --name init`
  Confirm `easy_rates/backend/prisma/migrations/[timestamp]_init/migration.sql`
  is created and applied.
  Done when: migration applies with zero errors on a fresh database
  (`podman-compose up postgres` → `pnpm prisma migrate dev` → exit 0).

- [ ] ⚠️ T5  Write `easy_rates/backend/prisma/seed.ts` covering all nine Figma
  decision-point outcomes:
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

- [ ] ⚠️ T6  `pnpm prisma db seed`
  Then `psql` the local database and confirm:
  `SELECT COUNT(*) FROM "User"` → ≥ 2 rows
  `SELECT COUNT(*) FROM "Property"` → ≥ 3 rows
  `SELECT COUNT(*) FROM "OTPRecord"` → ≥ 3 rows
  Done when: all three counts return expected minimums.

- [ ] ⚠️ T7  Export Prisma client singleton from `easy_rates/backend/shared/db.ts`:
  ```ts
  import { PrismaClient } from '@prisma/client'
  export const prisma = new PrismaClient()
  ```
  All service implementations import `{ prisma }` from `../../shared/db` —
  never instantiate their own client.
  Done when: the export exists; `grep -r "new PrismaClient"` inside any
  `services/` directory returns zero results.

- [ ] ⚠️ T8  `git commit -m "Database schema — Prisma models, migrations, seed data"`
  Done when: commit is clean; `prisma/migrations/` is included; no `.env` committed.
  This commit unblocks plans/03–06.

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
