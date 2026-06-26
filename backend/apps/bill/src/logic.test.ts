import { describe, expect, it } from "vitest";
import { Prisma } from "@easyrates/db";
import type { AIAmountCalculation, Bill, BillLineItem } from "@easyrates/db";
import {
  AI_CURRENT_MODEL_VERSION,
  aiExpectedAmount,
  dominantCategory,
  isStale,
  periodBounds,
  toAiEstimate,
  toLines,
} from "./logic.js";

const line = (
  over: Partial<BillLineItem> = {},
): BillLineItem =>
  ({
    id: "l1",
    billId: "b1",
    description: "x",
    amount: new Prisma.Decimal("100.00"),
    category: "WATER",
    anomalyFlag: false,
    historicalAverage: null,
    ...over,
  }) as BillLineItem;

const calc = (
  over: Partial<AIAmountCalculation> = {},
): AIAmountCalculation =>
  ({
    id: "c1",
    billId: "b1",
    estimatedAmount: new Prisma.Decimal("430.00"),
    confidence: 0.91,
    reasoning: "high vs average",
    modelVersion: AI_CURRENT_MODEL_VERSION,
    calculatedAt: new Date("2026-06-15T09:23:00.000Z"),
    ...over,
  }) as AIAmountCalculation;

describe("aiExpectedAmount confidence gate", () => {
  it("returns the estimate at/above 0.85", () => {
    expect(aiExpectedAmount(calc({ confidence: 0.85 }))).toBe("430.00");
  });
  it("returns null below 0.85", () => {
    expect(aiExpectedAmount(calc({ confidence: 0.84 }))).toBeNull();
  });
  it("returns null when there is no calculation", () => {
    expect(aiExpectedAmount(null)).toBeNull();
  });
});

describe("toAiEstimate confidence gate", () => {
  const bill = {
    id: "b1",
    totalAmount: new Prisma.Decimal("612.40"),
    fetchedAt: new Date("2026-06-14T00:00:00.000Z"),
  } as Pick<Bill, "id" | "totalAmount" | "fetchedAt">;

  it("emits estimate + variance when confident", () => {
    const r = toAiEstimate(bill, calc({ confidence: 0.91 }));
    expect(r.estimatedAmount).toBe("430.00");
    expect(r.variance).toBe("182.40"); // 612.40 - 430.00
  });

  it("nulls estimate AND variance below threshold", () => {
    const r = toAiEstimate(bill, calc({ confidence: 0.72 }));
    expect(r.estimatedAmount).toBeNull();
    expect(r.variance).toBeNull();
    expect(r.confidence).toBe(0.72);
  });
});

describe("isStale", () => {
  const fresh = calc();
  it("not stale on current model + calc after fetch", () => {
    expect(isStale(fresh, new Date("2026-06-14T00:00:00.000Z"))).toBe(false);
  });
  it("stale when the model version changed", () => {
    expect(
      isStale(calc({ modelVersion: "old-v" }), new Date("2026-06-14")),
    ).toBe(true);
  });
  it("stale when the bill was re-fetched after the calc", () => {
    expect(isStale(fresh, new Date("2026-06-20T00:00:00.000Z"))).toBe(true);
  });
});

describe("dominantCategory", () => {
  it("picks the category with the largest total", () => {
    expect(
      dominantCategory([
        line({ category: "WATER", amount: new Prisma.Decimal("100") }),
        line({ category: "ELECTRICITY", amount: new Prisma.Decimal("300") }),
      ]),
    ).toBe("ELECTRICITY");
  });
  it("defaults to OTHER for an empty bill", () => {
    expect(dominantCategory([])).toBe("OTHER");
  });
});

describe("periodBounds", () => {
  it("derives first/last day of the month", () => {
    expect(periodBounds("2026-06")).toEqual({
      validFrom: "2026-06-01",
      validTo: "2026-06-30",
    });
    expect(periodBounds("2026-02").validTo).toBe("2026-02-28");
  });
});

describe("toLines reconciliation", () => {
  it("VAT is the remainder when lines are VAT-exclusive", () => {
    const r = toLines(
      { id: "b1", period: "2026-06", totalAmount: new Prisma.Decimal("612.40") },
      [
        line({ amount: new Prisma.Decimal("498.40") }),
        line({ id: "l2", amount: new Prisma.Decimal("34.20"), category: "SANITATION" }),
      ],
    );
    expect(r.subtotal).toBe("532.60");
    expect(r.vatAmount).toBe("79.80");
    expect(r.totalAmount).toBe("612.40");
  });
});
