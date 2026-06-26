import { Prisma } from "@easyrates/db";
import type {
  AIAmountCalculation,
  Bill,
  BillLineItem,
  LineItemCategory,
} from "@easyrates/db";

/**
 * bill-service.md "TypeScript interfaces". `data` payloads only.
 */
export type BillStatus = "CURRENT" | "OVERDUE" | "PAID" | "DISPUTED";

export interface BillListItemResponse {
  id: string;
  accountNumber: string;
  category: LineItemCategory;
  billingPeriod: string;
  dueDate: string;
  amount: string;
  status: BillStatus;
  hasAnomaly: boolean;
  aiExpectedAmount: string | null;
}

export interface BillDetailResponse {
  id: string;
  accountNumber: string;
  accountHolder: string;
  billingPeriod: string;
  validFrom: string;
  validTo: string;
  totalAmount: string;
  status: BillStatus;
  dataAsOf: string;
}

export interface BillLineItemResponse {
  id: string;
  description: string;
  category: LineItemCategory;
  amount: string;
  anomalyFlag: boolean;
  historicalAverage: string | null;
}

export interface BillLinesResponse {
  billId: string;
  billingPeriod: string;
  lineItems: BillLineItemResponse[];
  subtotal: string;
  vatAmount: string;
  totalAmount: string;
}

export interface BillAiEstimateResponse {
  billId: string;
  actualAmount: string;
  estimatedAmount: string | null;
  variance: string | null;
  confidence: number;
  reasoning: string;
  basis: string;
  calculatedAt: string;
  isStale: boolean;
}

/** AI estimate display threshold (bill-service.md): below this, no number shown. */
export const AI_CONFIDENCE_THRESHOLD = 0.85;

/** The model version the deployment currently serves; a calc on an older
 *  version is stale and the app shows "Recalculate". */
export const AI_CURRENT_MODEL_VERSION = "seed-v0";

function money(d: Prisma.Decimal | number | string): string {
  return new Prisma.Decimal(d).toFixed(2);
}

/**
 * A per-service-account bill's headline category. Bills carry mixed line items
 * but the list row shows one category; pick the category with the largest total
 * amount (the dominant charge), falling back to OTHER for an empty bill.
 */
export function dominantCategory(
  lineItems: Pick<BillLineItem, "category" | "amount">[],
): LineItemCategory {
  if (lineItems.length === 0) return "OTHER";
  const totals = new Map<LineItemCategory, Prisma.Decimal>();
  for (const li of lineItems) {
    const prev = totals.get(li.category) ?? new Prisma.Decimal(0);
    totals.set(li.category, prev.plus(li.amount));
  }
  let best: LineItemCategory = lineItems[0]!.category;
  let bestVal = new Prisma.Decimal(-1);
  for (const [cat, val] of totals) {
    if (val.greaterThan(bestVal)) {
      best = cat;
      bestVal = val;
    }
  }
  return best;
}

type BillWithChildren = Bill & {
  lineItems: BillLineItem[];
  aiCalculation: AIAmountCalculation | null;
};

/**
 * `aiExpectedAmount` on the LIST row: the AI expected total only when a
 * confident calculation exists (confidence ≥ 0.85); null otherwise (below
 * threshold, or no calculation).
 */
export function aiExpectedAmount(
  calc: Pick<AIAmountCalculation, "estimatedAmount" | "confidence"> | null,
): string | null {
  if (!calc) return null;
  if (calc.confidence < AI_CONFIDENCE_THRESHOLD) return null;
  return money(calc.estimatedAmount);
}

export function toListItem(bill: BillWithChildren): BillListItemResponse {
  return {
    id: bill.id,
    accountNumber: bill.accountNumber,
    category: dominantCategory(bill.lineItems),
    billingPeriod: bill.period,
    dueDate: bill.dueDate.toISOString().slice(0, 10),
    amount: money(bill.totalAmount),
    status: bill.status as BillStatus,
    hasAnomaly: bill.lineItems.some((li) => li.anomalyFlag),
    aiExpectedAmount: aiExpectedAmount(bill.aiCalculation),
  };
}

/** "YYYY-MM" → first and last calendar day, as YYYY-MM-DD (UTC). */
export function periodBounds(period: string): {
  validFrom: string;
  validTo: string;
} {
  const [y, m] = period.split("-").map((n) => Number(n));
  const first = new Date(Date.UTC(y!, m! - 1, 1));
  const last = new Date(Date.UTC(y!, m!, 0)); // day 0 of next month = last day
  return {
    validFrom: first.toISOString().slice(0, 10),
    validTo: last.toISOString().slice(0, 10),
  };
}

export function toDetail(
  bill: Bill,
  accountHolder: string,
): BillDetailResponse {
  const { validFrom, validTo } = periodBounds(bill.period);
  return {
    id: bill.id,
    accountNumber: bill.accountNumber,
    accountHolder,
    billingPeriod: bill.period,
    validFrom,
    validTo,
    totalAmount: money(bill.totalAmount),
    status: bill.status as BillStatus,
    dataAsOf: bill.fetchedAt.toISOString(),
  };
}

const VAT_RATE = new Prisma.Decimal("0.15"); // ZA VAT 15%

/**
 * Lines breakdown. The stored totalAmount is authoritative; subtotal is the sum
 * of line amounts and vatAmount is the remainder (totalAmount − subtotal) so
 * the three always reconcile to the source-of-truth total. When the stored
 * total equals the line sum (VAT already folded into lines) we still surface an
 * implied 15% split for the UI.
 */
export function toLines(
  bill: Pick<Bill, "id" | "period" | "totalAmount">,
  lineItems: BillLineItem[],
): BillLinesResponse {
  const lineSum = lineItems.reduce(
    (acc, li) => acc.plus(li.amount),
    new Prisma.Decimal(0),
  );
  const total = new Prisma.Decimal(bill.totalAmount);

  let subtotal: Prisma.Decimal;
  let vat: Prisma.Decimal;
  if (total.greaterThan(lineSum)) {
    // Lines are VAT-exclusive; VAT is the documented remainder.
    subtotal = lineSum;
    vat = total.minus(lineSum);
  } else {
    // Lines already include VAT — back it out at 15% for display.
    subtotal = total.dividedBy(VAT_RATE.plus(1));
    vat = total.minus(subtotal);
  }

  return {
    billId: bill.id,
    billingPeriod: bill.period,
    lineItems: lineItems.map((li) => ({
      id: li.id,
      description: li.description,
      category: li.category,
      amount: money(li.amount),
      anomalyFlag: li.anomalyFlag,
      historicalAverage:
        li.historicalAverage == null ? null : money(li.historicalAverage),
    })),
    subtotal: subtotal.toFixed(2),
    vatAmount: vat.toFixed(2),
    totalAmount: total.toFixed(2),
  };
}

/**
 * A calculation is stale if it was produced on a model version other than the
 * one currently deployed, OR the bill was re-fetched after the calculation ran
 * (bill-service.md "Sync timeout / availability").
 */
export function isStale(
  calc: Pick<AIAmountCalculation, "modelVersion" | "calculatedAt">,
  billFetchedAt: Date,
): boolean {
  if (calc.modelVersion !== AI_CURRENT_MODEL_VERSION) return true;
  return billFetchedAt.getTime() > calc.calculatedAt.getTime();
}

export function toAiEstimate(
  bill: Pick<Bill, "id" | "totalAmount" | "fetchedAt">,
  calc: AIAmountCalculation,
): BillAiEstimateResponse {
  const actual = new Prisma.Decimal(bill.totalAmount);
  const confident = calc.confidence >= AI_CONFIDENCE_THRESHOLD;
  const estimated = confident ? new Prisma.Decimal(calc.estimatedAmount) : null;
  const variance = estimated ? actual.minus(estimated) : null;
  return {
    billId: bill.id,
    actualAmount: actual.toFixed(2),
    estimatedAmount: estimated ? estimated.toFixed(2) : null,
    variance: variance ? variance.toFixed(2) : null,
    confidence: calc.confidence,
    reasoning:
      calc.reasoning ??
      (confident
        ? "Estimate produced from recent consumption history."
        : "Not enough consistent history to produce a confident estimate."),
    basis: confident
      ? `Consumption history + tariff schedule (model ${calc.modelVersion ?? "unknown"})`
      : "Insufficient historical data",
    calculatedAt: calc.calculatedAt.toISOString(),
    isStale: isStale(calc, bill.fetchedAt),
  };
}
