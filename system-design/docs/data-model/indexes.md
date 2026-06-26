# EasyRates — Index Strategy & Query Analysis

**Source:** Socratic session (which query runs 10M times/year) + FIELDS session  
**Rule:** An index exists only when named in this document with a specific query justification.

---

## The 10M-per-Year Queries

Two queries together account for ~10M executions per year:

- **8M: balance / bill fetch** — every Home Dashboard load: `WHERE accountNumber = ? ORDER BY period DESC LIMIT 1`
- **2M: usage breakdown** — BILL REVIEW detail: `WHERE billId = ?` on BillLineItem

At 5,000 peak concurrent sessions, both run constantly during a WhatsApp social spike. Both are served by existing indexes with no sequential scan.

---

## Top-5 Queries by Frequency × Row-Scan Cost

### Q1 — Bill line item lookup (highest risk)

```sql
SELECT * FROM "BillLineItem" WHERE "billId" = 'clxxx'
```

**Frequency:** ~2M/year (every BILL REVIEW detail screen load)  
**Table size:** 5,400,000 rows  
**Without index:** full table scan, 5.4M rows per request × 2M requests = 10.8 trillion row-reads/year  
**With `@@index([billId])`:** index seek → ~5 rows returned. Zero sequential scan.  
**Index:** `@@index([billId])` on BillLineItem  
**Critical note:** Azure SQL (SQL Server) does NOT auto-index FK columns. This index must be explicitly declared. It is the most important index in the schema.

### Q2 — Latest bill fetch (balance check)

```sql
SELECT TOP 1 * FROM "Bill"
WHERE "accountNumber" = 'ACC001'
ORDER BY "period" DESC
```

**Frequency:** ~8M/year (Home Dashboard load, balance widget)  
**Table size:** 1,080,000 rows  
**Without index:** full table scan + sort, 1.08M rows per request × 8M requests  
**With `@@index([accountNumber, period])`:** composite index seek → 12 rows (12 months of bills per account) returned and sorted within the index. No separate sort step.  
**Index:** `@@index([accountNumber, period])` on Bill  
**Column order matters:** `accountNumber` is the equality filter (left) and `period` is used for ORDER BY (right). Reversing the columns would lose the ORDER BY benefit.

### Q3 — Bill history list

```sql
SELECT * FROM "Bill"
WHERE "accountNumber" = 'ACC001'
ORDER BY "period" DESC
```

**Frequency:** ~1M/year (BILL REVIEW list screen)  
**Table size:** 1,080,000 rows  
**With `@@index([accountNumber, period])`:** same composite index as Q2 covers this query — no additional index needed. The index can serve both the single-row and multi-row variants of this query.

### Q4 — OTP verification

```sql
SELECT * FROM "OTPAttempt"
WHERE "userId" = 'clyyy'
AND "expiresAt" > NOW()
AND "verifiedAt" IS NULL
```

**Frequency:** ~390,000/year (one per login × 25,000 users × 12 months × 1.3 retry factor)  
**Table size:** 33,000 active rows (30-day TTL purge)  
**Without index:** full scan, 33k rows per login. Acceptable at this scale but unpleasant at peak.  
**With `@@index([userId, expiresAt])`:** composite covers equality on userId (left) and range filter on expiresAt (right). Returns 1-3 rows per lookup.  
**Index:** `@@index([userId, expiresAt])` on OTPAttempt

### Q5 — Notification inbox

```sql
SELECT * FROM "Notification"
WHERE "userId" = 'clzzz'
ORDER BY "sentAt" DESC
LIMIT 20
```

**Frequency:** ~500,000/year (notification screen load per DAU per month)  
**Table size:** 225,000 active rows (90-day retention)  
**Without index:** full scan, 225k rows per load. At 5,000 peak concurrent: 1.125 billion row-reads/second.  
**With `@@index([userId, sentAt])`:** composite covers equality on userId (left) and DESC sort on sentAt (right). Returns 20 rows per load.  
**Index:** `@@index([userId, sentAt])` on Notification

---

## Consolidated Index Table

All indexes across all 14 models. Every index must appear here; any not listed is speculative and must be removed.

| Model | Rows (12mo) | Index | Type | Query it serves |
| --- | --- | --- | --- | --- |
| User | 25,000 | `phone` | `@unique` | `WHERE phone = ?` — login |
| User | 25,000 | `email` | `@unique` | `WHERE email = ?` — optional login |
| OTPAttempt | 33,000 | `(userId, expiresAt)` | `@@index` | Q4: OTP verify lookup |
| AuditEvent | 300,000+ | `(userId, createdAt)` | `@@index` | Per-user audit history |
| AuditEvent | 300,000+ | `(entityId, entityType)` | `@@index` | Per-record audit history |
| Property | 30,000 | `accountNumber` | `@unique` | Authority key for soft references |
| Property | 30,000 | `erfNumber` | `@@index` | Property search by ERF number |
| Account | 90,000 | `accountNumber` | `@unique` | `WHERE accountNumber = ?` — account lookup |
| Account | 90,000 | `userId` | `@@index` | GET /account/me — VERIFY found seq scan at 90k rows without it |
| Bill | 1,080,000 | `(accountNumber, period)` | `@@index` | Q2, Q3: balance check + bill history |
| BillLineItem | 5,400,000 | `billId` | `@@index` | Q1: usage breakdown — critical |
| AIAmountCalculation | ≤1,080,000 | `billId` | `@unique` | `WHERE billId = ?` — AI estimate lookup |
| Objection | 2,500 | `refNumber` | `@unique` | `WHERE refNumber = ?` — tracking screen |
| EvidenceFile | 7,500 | `storageKey` | `@unique` | Prevent duplicate uploads |
| Notification | 225,000 | `(userId, sentAt)` | `@@index` | Q5: notification inbox |
| Municipality | 1 | `name` | `@unique` | Seed lookup |
| Municipality | 1 | `code` | `@unique` | Seed lookup |

Models with no explicit indexes (besides PK):
- ObjectionDraft — < 1,000 rows; full scan is irrelevant
- MunicipalityResponse — < 2,500 rows; full scan is irrelevant
- EvidenceFile — 7,500 rows; `@unique storageKey` covers the insert-duplicate check; per-objection lookup scans ≤ 3 rows in practice

**⚠️ Schema correction (verified 2026-06-20):** `Account.userId` requires `@@index([userId])`. See VERIFY section below.

---

## VERIFY — EXPLAIN ANALYZE Results

**Method:** PostgreSQL 15, seeded at 1/10 production scale. Row counts in parentheses are 1/10 scale. Costs are extrapolated ×10 for production in the rightmost column. Azure SQL produces equivalent plans; PostgreSQL was used because it was available locally. The key output is the plan type (index scan vs seq scan), not the exact millisecond figures.

**Seed:** 2,500 Users · 7,500 Accounts · 108,000 Bills · 540,000 BillLineItems · 3,300 OTPAttempts · 22,500 Notifications. `ANALYZE` run after seeding.

---

### Q1 — BillLineItem WHERE billId = ?

```text
-- WITH @@index([billId]):
Bitmap Index Scan on BillLineItem_billId_idx
  actual time=0.017..0.018 rows=5   Buffers: shared hit=3 (index) + 5 (heap) = 8
Total execution time: 0.081 ms

-- WITHOUT index:
Parallel Seq Scan on BillLineItem
  Rows Removed by Filter: 179,998 per worker (×3 workers)
  Buffers: shared hit=5,444
Total execution time: 10.788 ms
```

**Production extrapolation (5.4M rows = 10× test):**

- With index: ~0.08 ms (8 buffer hits regardless of table size — index seek scales with log n)
- Without index: ~107 ms — **EXCEEDS 50ms SLA** at production scale

**Verdict:** ✅ index required. Without it, every BILL REVIEW detail screen load fails the latency target at production row counts. This is the most critical index in the schema.

---

### Q2 — Bill WHERE accountNumber = ? ORDER BY period DESC LIMIT 1

```text
-- WITH @@index([accountNumber, period]):
Index Scan Backward using Bill_accountNumber_period_idx
  actual time=0.018..0.019 rows=1   Buffers: shared hit=4
Total execution time: 0.036 ms

-- WITHOUT index:
Seq Scan on Bill + Sort (top-N heapsort)
  Rows Removed by Filter: 107,988
  Buffers: shared hit=1,231
Total execution time: 4.165 ms
```

**Production extrapolation (1.08M rows = 10× test):**

- With index: ~0.04 ms (4 buffer hits; B-tree height is log(1.08M) ≈ 3 levels)
- Without index: ~42 ms — approaches the 50ms SLA at peak; at 8M/year frequency this is dangerous

**Column order note confirmed:** PostgreSQL used `Index Scan Backward` — it traversed the index in descending `period` order without a separate sort step. Reversing the column order (`period, accountNumber`) would break this and force a post-sort.

**Verdict:** ✅ index required. Near-SLA risk without it at production scale, at 8M executions/year.

---

### Q3 — Bill WHERE accountNumber = ? ORDER BY period DESC

```text
-- WITH @@index([accountNumber, period]):
Bitmap Heap Scan on Bill (via Bitmap Index Scan)
  actual time=0.009..0.009 rows=12   Buffers: shared hit=15
Total execution time: 0.100 ms
```

Same composite index as Q2 serves Q3. No additional index needed. Confirmed: the index covers both the single-row LIMIT 1 variant (Q2) and the full history list (Q3).

**Verdict:** ✅ covered by existing `@@index([accountNumber, period])`. No change needed.

---

### Q4 — OTPAttempt WHERE userId = ? AND expiresAt > NOW() AND verifiedAt IS NULL

```text
-- WITH @@index([userId, expiresAt]):
Index Scan using OTPAttempt_userId_expiresAt_idx
  actual time=0.013..0.014 rows=2   Buffers: shared hit=4
Total execution time: 0.023 ms

-- WITHOUT index:
Seq Scan on OTPAttempt
  Rows Removed by Filter: 3,298
  Buffers: shared hit=45
Total execution time: 0.187 ms
```

**Production extrapolation (33k rows = 10× test):**

- With index: ~0.02 ms
- Without index: ~1.87 ms — still under 50ms even without an index

**Observation:** At 33k active rows, this table is small enough that the seq scan is not catastrophic (~2ms). However: (a) the index is cheap to add, (b) the composite covers the `expiresAt > NOW()` range filter correctly, (c) without the index, the planner cannot use the `expiresAt` filter to short-circuit — it reads all 33k rows and then filters.

**Verdict:** ✅ index justified. Not a correctness risk at current scale, but the composite is the right design and costs nothing.

---

### Q5 — Notification WHERE userId = ? ORDER BY sentAt DESC LIMIT 20

```text
-- WITH @@index([userId, sentAt]):
Bitmap Heap Scan on Notification (via Bitmap Index Scan)
  actual time=0.011..0.011 rows=9   Buffers: shared hit=14
Total execution time: 0.064 ms

-- WITHOUT index:
Seq Scan on Notification + Sort (quicksort)
  Rows Removed by Filter: 22,491
  Buffers: shared hit=219
Total execution time: 0.761 ms
```

**Production extrapolation (225k rows = 10× test):**

- With index: ~0.06 ms (14 buffer hits)
- Without index: ~7.6 ms — under 50ms, but 219 → 2,190 buffer hits per query × 5,000 peak concurrent sessions = enormous buffer pressure on Azure SQL S2 (50 DTU)

**Verdict:** ✅ index required for peak buffer-pressure reasons, not just raw latency. At 5,000 concurrent notification inbox loads, without the index the buffer cache is overwhelmed regardless of per-query latency.

---

### ⚠️ FLAG: Account.userId — Schema Bug Found

```text
-- WITH @@index([userId]) (tested for comparison):
Bitmap Heap Scan on Account (via Bitmap Index Scan on Account_userId_idx)
  actual time=0.012..0.012 rows=3   Buffers: shared hit=5
Total execution time: 0.047 ms

-- WITHOUT @@index([userId]) — matches current schema docs:
Seq Scan on Account
  Rows Removed by Filter: 7,497   <-- reads every row
  Buffers: shared hit=60
Total execution time: 0.313 ms
```

**Query that fires this path:** `GET /account/me` → `findMany({ where: { userId: <jwt.sub>, deletedAt: null } })`

**Production extrapolation (90k rows = 12× test):**

- With index: ~0.05 ms (5 buffer hits)
- Without index: ~3.76 ms, **720 buffer hits per query**

At 5,000 peak concurrent sessions loading the home screen (which includes account data):  
`5,000 × 720 buffer hits = 3.6M buffer reads in one request wave`  
Azure SQL S2 (50 DTU) is approximately equivalent to 50 MB/s of I/O throughput. At 8KB pages: 3.6M × 8KB = 28.8 GB — several seconds of I/O just from this one query type. This would saturate S2 DTU and cause timeouts.

**Root cause of the bug:** `property-account.md` incorrectly stated that `accountNumber @unique` makes a `userId` index unnecessary. The `@unique` on `accountNumber` does not help a query filtering by `userId`. These are two independent lookup paths.

**Fix:** Add `@@index([userId])` to Account. See corrected schema in [property-account.md](property-account.md).

---

## Sequential Scan Risk Table (updated after VERIFY)

| Query | Table rows | Without index | With index | SLA risk |
| --- | --- | --- | --- | --- |
| BillLineItem WHERE billId = ? | 5.4M | Seq scan ~107ms | Index seek 0.08ms | FAIL: exceeds 50ms SLA |
| Bill WHERE accountNumber = ? ORDER BY period DESC | 1.08M | Seq scan + sort ~42ms | Index backward 0.04ms | WARN: near SLA at 8M/year |
| Account WHERE userId = ? | 90k | Seq scan ~3.76ms, 720 buffers | Index seek 0.05ms, 5 buffers | WARN: DTU saturation at peak |
| Notification WHERE userId = ? ORDER BY sentAt DESC | 225k | Seq scan ~7.6ms, 2,190 buffers | Index seek 0.06ms, 14 buffers | WARN: DTU pressure at 5k concurrent |
| AuditEvent WHERE userId = ? AND createdAt > X | 300k+ | Full scan (analytical) | Index seek | WARN: admin queries only |
| OTPAttempt WHERE userId = ? AND expiresAt > NOW() | 33k | Seq scan ~1.87ms | Index scan 0.02ms | OK: acceptable at current scale |

### FK auto-index reminder (Azure SQL / SQL Server)

Azure SQL does NOT auto-index FK columns. Explicit `@@index` declarations required for all FK lookup paths:

- `BillLineItem.billId` — ✅ `@@index([billId])`
- `OTPAttempt.userId` — ✅ covered by `@@index([userId, expiresAt])`
- `Notification.userId` — ✅ covered by `@@index([userId, sentAt])`
- `AuditEvent.userId` — ✅ covered by `@@index([userId, createdAt])`
- `Account.userId` — ✅ **`@@index([userId])` ADDED** (bug found by VERIFY; was missing)

---

## Index Creation on Azure SQL (migration note)

For indexes on large tables (Bill ≥1.08M, BillLineItem ≥5.4M, Notification ≥225k):

- **Production (Standard S2+):** edit the generated migration SQL to add `WITH (ONLINE = ON)` before applying. Without it, index creation takes a Sch-M lock for the full build duration.
- **Pilot (Basic tier):** `WITH (ONLINE = ON)` is not available on Azure SQL Basic. Create large indexes during off-hours; accept a brief read block.

See [migrations.md](migrations.md) for the full zero-downtime migration checklist.
