# EasyRates — Bill & Line Item Models

**Service ownership:** bill-service  
**Patches applied:** DECISION-C (municipalityId on Bill) · DECISION-D (cuid PKs)  
**Retention:** Bills are NEVER deleted — SA financial regulations require 5-year minimum retention.

---

## Enums

```prisma
enum BillStatus {
  CURRENT   // within payment period
  OVERDUE   // past due date, unpaid
  PAID
  DISPUTED  // an active Objection references this bill
}

enum LineItemCategory {
  WATER
  ELECTRICITY
  PROPERTY_RATES
  SANITATION
  REFUSE
  ARREARS
  LEVY
  VAT
  OTHER
}

// The four DisputeCategory values are locked from the Figma EVIDENCE & CHALLENGE flow.
// Do NOT add values without a formal design decision.
enum DisputeCategory {
  WRONG_METER_READING
  INCORRECT_TARIFF
  PROPERTY_NOT_OCCUPIED
  DUPLICATE_OTHER
}
```

---

## Model: Bill

```prisma
model Bill {
  id             String     @id @default(cuid())
  municipalityId String
  accountNumber  String     // soft reference to Account.accountNumber; no DB FK
  period         String     // "YYYY-MM" e.g. "2025-05"
  totalAmount    Decimal
  dueDate        DateTime
  status         BillStatus @default(CURRENT)
  fetchedAt      DateTime   @default(now())

  municipality  Municipality         @relation(fields: [municipalityId], references: [id], onDelete: Restrict)
  lineItems     BillLineItem[]
  aiCalculation AIAmountCalculation?

  @@index([accountNumber, period])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| municipalityId | String | No | — | — | — | DECISION-C FK |
| accountNumber | String | No | — | included | — | See @@index below |
| period | String | No | — | included | — | "2025-05" — composite with accountNumber |
| totalAmount | Decimal | No | — | — | — | |
| dueDate | DateTime | No | — | — | — | |
| status | BillStatus | No | — | — | CURRENT | |
| fetchedAt | DateTime | No | — | — | now() | When bill was synced from municipality |

**`@@index([accountNumber, period])`** — the two hot Bill queries:
- **Bill list:** `WHERE accountNumber = 'ACC001' ORDER BY period DESC` — fetches the history for the BILL REVIEW list screen. `accountNumber` is the equality filter (left column) and `period` is used for ordering (right column). The composite index covers both.
- **Single bill:** `WHERE accountNumber = 'ACC001' AND period = '2025-05'` — the most-recent-bill lookup used by the Home Dashboard. Equality on both columns → index covers it fully with no table scan.

At 1.08M rows, a full table scan on Bill is unacceptable at peak (5,000 concurrent sessions). This index makes both queries sub-millisecond.

**Why `period` is a String, not DateTime:**  
A billing period is a month, not a point in time. `"2025-05"` is lexicographically sortable and directly maps to the API parameter `?period=2025-05`. Using `DateTime` would require normalizing to `2025-05-01` and adding a DATEPART extraction on every query. String avoids the extraction and is clearer in the API contract.

**Why no FK to Account:**  
`accountNumber` is a soft reference — no DB FK. The municipality billing system is the authority for account numbers. A hard FK would break on resync (Property/Account rows may be replaced). Bill queries resolve the account number to a User's account list at the service layer.

### Retention policy

Bill rows are NEVER deleted. No `deletedAt` column. DECISION-A explicitly excludes Bill from soft-delete because SA financial regulations require 5-year minimum retention of billing records. The `fetchedAt` column records when EasyRates synced the bill; it is not a deletion marker.

---

## Model: BillLineItem

```prisma
model BillLineItem {
  id                String           @id @default(cuid())
  billId            String
  description       String
  amount            Decimal
  category          LineItemCategory
  anomalyFlag       Boolean          @default(false)
  historicalAverage Decimal?         // null = no historical data yet for this category

  bill       Bill             @relation(fields: [billId], references: [id], onDelete: Cascade)
  drafts     ObjectionDraft[]
  objections Objection[]

  @@index([billId])
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| billId | String | No | — | included | — | See @@index below |
| description | String | No | — | — | — | |
| amount | Decimal | No | — | — | — | |
| category | LineItemCategory | No | — | — | — | |
| anomalyFlag | Boolean | No | — | — | false | true = AI flagged this line item |
| historicalAverage | Decimal | Yes | — | — | — | For anomaly comparison in BILL REVIEW |

**`@@index([billId])`** — the usage breakdown query:
```
WHERE billId = 'clxxx'
```
This query fires on every BILL REVIEW detail screen load. At 5.4M rows (5 line items per bill × 1.08M bills), a full table scan would read 5.4M rows per request at peak load. The `@@index([billId])` reduces this to a ~5-row index seek. This is the most critical index in the schema — without it, the BILL REVIEW screen is unusable at production scale.

PostgreSQL does NOT auto-index FK columns. Azure SQL (SQL Server) also does not auto-index FK columns. The `@@index([billId])` must be explicitly defined.

**`onDelete: Cascade`** — if a Bill is deleted, all linked BillLineItems cascade-delete. In practice, Bills are never deleted (retention policy), so this policy governs dev/test teardown only.

### Relationship to ObjectionDraft and Objection

BillLineItem is the FK parent of both ObjectionDraft (optional, `onDelete: SetNull`) and Objection (required, `onDelete: Restrict`).

- **ObjectionDraft**: `lineItemId` is nullable. A user can start a draft without selecting a specific line item. On BillLineItem deletion (dev teardown only), drafts have their `lineItemId` set to null — not deleted.
- **Objection**: `lineItemId` is required. An Objection without a disputed line item is invalid. `onDelete: Restrict` prevents BillLineItem deletion while an Objection references it.
