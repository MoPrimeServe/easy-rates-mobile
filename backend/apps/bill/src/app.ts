import express, { type Express } from "express";
import {
  ApiError,
  asyncHandler,
  errorMiddleware,
  makeHealthHandler,
  notFoundMiddleware,
  ok,
  rateLimit,
} from "@easyrates/http";
import { prisma } from "@easyrates/db";
import {
  type AuthCoreRuntime,
  type AuthedRequest,
  requireAuth,
} from "@easyrates/auth-core";
import {
  toAiEstimate,
  toDetail,
  toLines,
  toListItem,
} from "./logic.js";

/** The set of service-account numbers the caller is entitled to (active links). */
async function callerAccountNumbers(req: AuthedRequest): Promise<Set<string>> {
  const accounts = await prisma.account.findMany({
    where: { userId: req.userId, deletedAt: null },
    select: { accountNumber: true },
  });
  return new Set(accounts.map((a) => a.accountNumber));
}

/** Display name of the caller (used as the bill accountHolder). */
async function callerName(req: AuthedRequest): Promise<string> {
  const user = await prisma.user.findFirst({
    where: { id: req.userId, deletedAt: null },
    select: { displayName: true },
  });
  return user?.displayName ?? "";
}

/**
 * Load a bill the caller is entitled to, or throw the right error:
 *   404 if no such bill id; 403 if it exists but isn't the caller's account.
 */
async function ownedBill(req: AuthedRequest) {
  const bill = await prisma.bill.findUnique({
    where: { id: req.params.id },
    include: { lineItems: true, aiCalculation: true },
  });
  if (!bill) throw ApiError.notFound("Bill not found.");
  const owned = await callerAccountNumbers(req);
  if (!owned.has(bill.accountNumber)) {
    throw ApiError.forbidden("Bill not available.");
  }
  return bill;
}

export function createBillApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  app.get("/health", makeHealthHandler({ serviceName: "bill-service" }));

  // ---- GET /bills ----------------------------------------------------------
  // Source-of-truth bill rows (per service account) the caller is entitled to.
  app.get(
    "/bills",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const owned = await callerAccountNumbers(req);
      const bills = await prisma.bill.findMany({
        where: { accountNumber: { in: [...owned] } },
        include: { lineItems: true, aiCalculation: true },
        orderBy: { period: "desc" },
      });
      res.status(200).json(ok(bills.map(toListItem)));
    }),
  );

  // ---- GET /bills/:id ------------------------------------------------------
  app.get(
    "/bills/:id",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const bill = await ownedBill(req);
      const holder = await callerName(req);
      res.status(200).json(ok(toDetail(bill, holder)));
    }),
  );

  // ---- GET /bills/:id/lines ------------------------------------------------
  app.get(
    "/bills/:id/lines",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const bill = await ownedBill(req);
      res.status(200).json(ok(toLines(bill, bill.lineItems)));
    }),
  );

  // ---- GET /bills/:id/ai-estimate ------------------------------------------
  // Reads AIAmountCalculation. confidence < 0.85 → estimatedAmount/variance
  // null (still 200). No calculation (AI backend unavailable) → 503
  // ai_unavailable. isStale surfaced for the "Recalculate" prompt.
  app.get(
    "/bills/:id/ai-estimate",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const bill = await ownedBill(req);
      if (!bill.aiCalculation) {
        throw new ApiError(
          "ai_unavailable",
          503,
          "The expected-amount estimate is temporarily unavailable. Please try again.",
        );
      }
      res.status(200).json(ok(toAiEstimate(bill, bill.aiCalculation)));
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
