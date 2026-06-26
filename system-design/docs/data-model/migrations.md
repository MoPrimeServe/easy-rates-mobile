# EasyRates — Migration Strategy

**Date:** 2026-06-20  
**Downstream:** backend/plans/02 (schema), plan/07 (security — audit events on schema changes), plan/08 (container topology — deployment window coordination)

---

## Strategy

EasyRates runs a single `prisma migrate dev --name init` at project creation to establish the complete 14-model schema; because all nine Node.js services share one Azure SQL database (ADR-001 Decision F), there is one `prisma/migrations/` history for the entire project — not one per service — and every subsequent schema change goes through `prisma migrate deploy`, never `prisma migrate dev`, against any environment above local dev. The zero-downtime checklist below exists because Azure SQL's lock manager escalates row-level and page-level lock acquisitions to a table-level schema modification lock (Sch-M) when a single DDL statement touches too many rows; on the Bill table (1.08M projected rows) and BillLineItem table (5.4M projected rows), this escalation blocks all concurrent reads for the duration of the operation, which at peak load means 5,000 concurrent sessions receive timeout errors rather than 50ms responses. The four-step expand-contract pattern below prevents this by decomposing every risky schema change into individually safe migrations where no single file scans a large table.

---

## Zero-Downtime Checklist

### Step 1 — Generate SQL; do not apply

```bash
pnpm prisma migrate dev --create-only --name <descriptive_name>
```

This writes `prisma/migrations/<timestamp>_<name>/migration.sql` and stops. It does not touch the database. Read every line of the generated SQL before proceeding.

**Review checklist — abort if any of the following appear on a table with > 100k rows:**

| SQL pattern | Risk | Action |
| --- | --- | --- |
| `ALTER COLUMN … NOT NULL` (no DEFAULT) | Sch-M lock while SQL Server validates all existing rows | Use expand-contract: add nullable, backfill, then constrain |
| `DROP COLUMN` | Sch-M lock; data lost if code still writes the column | Confirm column unused in all deployed code versions first |
| `CREATE INDEX` (no `WITH (ONLINE = ON)`) | Sch-M lock for full index build duration | Add `WITH (ONLINE = ON)` manually before apply — see Azure SQL note below |
| `EXEC sp_rename` | Exclusive table lock | Replace with expand-contract: new column + `@map` alias + backfill + drop |
| Large `UPDATE` in the migration file | Lock escalation at ~5,000 row locks | Move backfill to a batched maintenance script outside the migration file |

**Azure SQL tier note:** `WITH (ONLINE = ON)` is available on Standard S2 and above (production tier). It is **not** available on Azure SQL Basic (pilot tier, 5 DTU). On the pilot tier, create indexes during off-hours and accept the brief Sch-M lock. On the production Standard S2 tier, always edit the generated SQL to add `WITH (ONLINE = ON)` before applying index creations on Bill or BillLineItem.

Example edit before applying:

```sql
-- Prisma generates:
CREATE INDEX "Bill_accountNumber_period_idx" ON "Bill"("accountNumber", "period");

-- Edit to before applying on production:
CREATE INDEX "Bill_accountNumber_period_idx" ON "Bill"("accountNumber", "period")
WITH (ONLINE = ON);
```

Commit the edited migration file — the edited SQL is what `prisma migrate deploy` will apply.

---

### Step 2 — Test against a production-equivalent snapshot

Apply the migration against a restored copy of the production database, not against an empty dev database. An empty database never catches lock escalation, index size, or constraint violations on existing data.

```bash
DATABASE_URL=<snapshot_url> pnpm prisma migrate deploy
```

Pass conditions before proceeding:
- Migration applies with zero errors and zero lock timeouts.
- `SELECT COUNT(*) FROM <changed_table>` returns the expected row count (no data loss).
- Integration smoke suite passes against the snapshot.
- Azure SQL DTU usage during apply stays below 80%. If DTU hits 100%, the migration is acquiring too many locks — revise to expand-contract before touching production.

---

### Step 3 — Apply to production in a low-traffic window

```bash
DATABASE_URL=<prod_url> pnpm prisma migrate deploy
```

`migrate deploy` (not `migrate dev`) — applies pending migrations in order without regenerating, resetting, or prompting. It is the only Prisma command that may run against production.

Coordinate the deployment window with plan/08 (container topology): confirm that the App Service autoscale is not in the middle of spinning up new instances during the migration window, as new instances will attempt to start services against a partially-migrated schema.

Monitor Azure Monitor → SQL → DTU percentage during the apply. If DTU sustains above 80% for more than 30 seconds, the migration is locking a large table — abort with Ctrl-C and diagnose before retrying.

---

### Step 4 — Verify

```bash
pnpm prisma migrate status
```

Expected output: `"All migrations have been applied."` Any `"migration not applied"` or `"migration failed"` line requires immediate investigation — do not deploy application code until the migration status is clean.

Run the full integration smoke suite against production. Check:
- AuditEvent row count has not decreased (audit log is append-only).
- Notification and OTPAttempt counts are consistent with pre-migration values.
- `GET /bill?accountNumber=ACC001` returns in < 200ms (index on Bill is intact).

---

## The Expand-Contract Pattern

For any change to a column that already holds data on a table with > 100k rows, use three separate migrations rather than one. The order below is the only safe order — **never reverse it**.

### Migration 1 — Expand (add nullable column, no backfill)

```sql
-- Safe: metadata-only in SQL Server 2012+. No table scan. Brief Sch-M.
ALTER TABLE "Bill" ADD "newColumn" NVARCHAR(MAX) NULL;
```

Adding a nullable column with no DEFAULT is a metadata-only operation in SQL Server 2012+ — the engine does not scan existing rows or fill any values. The Sch-M lock is held for milliseconds. Safe at 1.08M rows. Deploy this migration and the application code that dual-writes both old and new columns.

### Migration 2 — Backfill (outside the migration file, in batches)

Do not put a large UPDATE in a migration file. A single `UPDATE "Bill" SET "newColumn" = …` across 1.08M rows will acquire 1.08M row locks, hit SQL Server's ~5,000-lock escalation threshold, escalate to a table lock, and block the entire Bill table for minutes.

Run the backfill as a standalone maintenance script in batches of ≤ 2,000 rows:

```sql
WHILE EXISTS (SELECT 1 FROM "Bill" WHERE "newColumn" IS NULL)
BEGIN
  UPDATE TOP (2000) "Bill"
  SET    "newColumn" = <derivation from existing columns>
  WHERE  "newColumn" IS NULL;
  WAITFOR DELAY '00:00:00.100'; -- 100ms pause between batches
END
```

The 100ms pause between batches releases row locks and allows concurrent reads to proceed between batch commits. At 2,000 rows per batch with a 100ms pause, 1.08M rows completes in ~90 seconds elapsed with zero table-lock escalation.

Confirm completion before Migration 3:

```sql
SELECT COUNT(*) FROM "Bill" WHERE "newColumn" IS NULL;
-- Expected: 0
```

### Migration 3 — Contract (add constraint; drop old column)

Only run Migration 3 after: (a) the backfill confirms zero nulls in `newColumn`, and (b) all deployed application versions have stopped reading or writing `oldColumn`.

```sql
-- Add NOT NULL constraint. Safe in SQL Server 2012+ if no nulls exist:
-- SQL Server validates existing rows but does not rewrite them. Brief Sch-M.
ALTER TABLE "Bill" ALTER COLUMN "newColumn" NVARCHAR(MAX) NOT NULL;

-- Drop old column only after code no longer references it:
ALTER TABLE "Bill" DROP COLUMN "oldColumn";
```

**Why this order is mandatory:**
- Dropping `oldColumn` before all code versions stop writing to it corrupts data on the rows written between deploy and drop.
- Adding the NOT NULL constraint before the backfill completes fails on any null row with a constraint violation error that rolls back the migration.
- Backfilling before the new column exists has nowhere to write.

---

## Safe vs Unsafe Operations at a Glance

| Operation | Safe at 1M rows? | Azure SQL behaviour | Pattern |
| --- | --- | --- | --- |
| Add nullable column, no DEFAULT | Yes | Metadata-only, brief Sch-M | Single migration |
| Add NOT NULL column with constant DEFAULT | Yes | Metadata-only in SQL Server 2012+ | Single migration |
| Add NOT NULL column, backfill required | No (as one step) | Table scan for validation | Expand → backfill → contract (3 migrations) |
| Drop column | Only after code is updated | Sch-M lock; permanent data loss | Two-phase deploy: stop using in code, then drop |
| Rename column (`sp_rename`) | No | Exclusive table lock | Expand-contract with `@map` alias; never `sp_rename` on large tables |
| Add index (Basic tier — pilot) | Blocking | Sch-M for full index build | Off-hours only; accept brief downtime |
| Add index (Standard S2+ — production) | Yes with `ONLINE = ON` | Concurrent reads/writes allowed | Edit generated SQL to add `WITH (ONLINE = ON)` before apply |
| Change column type | No | Requires rewrite | Treat as rename: new column + backfill + drop |
| Add foreign key constraint | Conditional | Table scan to validate existing rows | Backfill to ensure no orphans before adding FK |
