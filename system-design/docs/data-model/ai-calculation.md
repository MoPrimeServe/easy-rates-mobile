# EasyRates — AI Amount Calculation Model

**Service ownership:** bill-service  
**Patches applied:** DECISION-D (cuid PKs)  
**Correction vs FIELDS session:** `billId → Bill` (not `lineItemId → BillLineItem`). The AI estimate is a per-bill total, matching the `GET /bills/:id/ai-estimate` endpoint in service-map.md.

---

## Model: AIAmountCalculation

```prisma
model AIAmountCalculation {
  id              String   @id @default(cuid())
  billId          String   @unique // one calculation per bill; @unique creates the index
  estimatedAmount Decimal            // AI model's expected correct amount for the full bill
  confidence      Float              // 0.0–1.0 confidence score from the model
  reasoning       String?            // AI-generated explanation shown on BILL REVIEW screen
  modelVersion    String?            // which model version produced this result
  calculatedAt    DateTime @default(now())

  bill Bill @relation(fields: [billId], references: [id], onDelete: Cascade)
}
```

### Field table

| Field | Prisma type | Optional? | @unique | @@index | @default | Index justification |
| --- | --- | --- | --- | --- | --- | --- |
| id | String | No | — | — | cuid() | |
| billId | String | No | Yes | — | — | @unique creates the index; one estimate per bill |
| estimatedAmount | Decimal | No | — | — | — | |
| confidence | Float | No | — | — | — | 0.0 = uncertain, 1.0 = high confidence |
| reasoning | String | Yes | — | — | — | Displayed on "View AI-Generated Expected Amount" |
| modelVersion | String | Yes | — | — | — | For staleness detection after model retraining |
| calculatedAt | DateTime | No | — | — | now() | For staleness indicator in API response |

**`@unique` on billId** — enforces one calculation per bill. If the model is re-run, the existing row is replaced (`upsert`), not a new row added. This keeps the table simple: the latest calculation is always the single row for a given bill. `@unique` creates an index automatically — no `@@index` is needed.

### Row count and index decision

Projected rows: up to 1,080,000 (one per bill if all bills are estimated). The `@unique` on `billId` provides the necessary index for the `WHERE billId = ?` lookup. No additional indexes are needed.

### Staleness policy

The API response from `GET /bills/:id/ai-estimate` includes:
```json
{
  "estimatedAmount": "1450.00",
  "confidence": 0.82,
  "reasoning": "Your meter reading appears incorrect based on 6-month average consumption.",
  "calculatedAt": "2025-05-15T09:23:00Z",
  "isStale": false
}
```

`isStale` is derived at the service layer:
- If `modelVersion` in the database differs from the current deployed model version, `isStale = true`.
- If `calculatedAt < bill.fetchedAt` (the bill was refreshed from the municipality after the AI ran), `isStale = true`.

The Flutter app shows a "Recalculate" prompt when `isStale = true`. The bill-service triggers an async recalculation job via BullMQ when the user taps it.

### Recalculation behavior

On recalculation, bill-service runs:
```typescript
await prisma.aIAmountCalculation.upsert({
  where: { billId },
  update: { estimatedAmount, confidence, reasoning, modelVersion, calculatedAt: new Date() },
  create: { billId, estimatedAmount, confidence, reasoning, modelVersion },
})
```

This replaces the existing row. History of prior calculations is not preserved in the database — the municipality adapter's calculation logs (Databricks) are the source of history if it is ever needed.

### onDelete: Cascade

`billId → Bill`: Cascade. If a Bill is deleted (dev teardown only — retention policy prevents production deletion), the AIAmountCalculation row cascade-deletes. This is correct: a calculation without a bill is meaningless.

### Why bill-level, not line-item-level

The Figma BILL REVIEW flow has a single "View AI-Generated Expected Amount" screen that shows the total corrected amount for the bill as a whole. The AI model receives the full bill and account history and outputs a single expected amount. Line-item-level AI estimates are not shown in the Figma flow and are out of scope for Phase 1.

The `GET /bills/:id/ai-estimate` endpoint (service-map.md) confirms this: the route is at the bill level, not the line item level.
