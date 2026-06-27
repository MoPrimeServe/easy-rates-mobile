import express, { type Express } from "express";
import { z } from "zod";
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
  parseOrValidationError,
  requireAuth,
} from "@easyrates/auth-core";
import {
  maskIdNumberDisplay,
  maskPhoneDisplay,
  type AccountPreferencesResponse,
  type LinkedPropertyResponse,
  type PreferenceLanguage,
} from "./logic.js";

const LANGUAGES = ["en", "zu", "af", "st"] as const;

// Partial update — any subset; omitted fields unchanged (account-service.md).
const preferencesUpdateSchema = z
  .object({
    smsEnabled: z.boolean().optional(),
    pushEnabled: z.boolean().optional(),
    emailEnabled: z.boolean().optional(),
    language: z.enum(LANGUAGES).optional(),
  })
  .strict();

function prefsOf(user: {
  smsEnabled: boolean;
  pushEnabled: boolean;
  emailEnabled: boolean;
  preferredLanguage: string;
}): AccountPreferencesResponse {
  return {
    smsEnabled: user.smsEnabled,
    pushEnabled: user.pushEnabled,
    emailEnabled: user.emailEnabled,
    language: user.preferredLanguage as PreferenceLanguage,
  };
}

export function createAccountApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  app.get("/health", makeHealthHandler({ serviceName: "account-service" }));

  // ---- GET /account/profile  (READ, masked, read-only) ---------------------
  app.get(
    "/account/profile",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const user = await prisma.user.findFirst({
        where: { id: req.userId, deletedAt: null },
      });
      if (!user) throw ApiError.unauthenticated("Session user not found.");
      res.status(200).json(
        ok({
          userId: user.id,
          displayName: user.displayName ?? "",
          email: user.email ?? "",
          phoneMasked: maskPhoneDisplay(user.phone),
          idNumberMasked: maskIdNumberDisplay(user.idNumberHash),
        }),
      );
    }),
  );

  // ---- GET /account/properties  (READ) -------------------------------------
  // Linked properties = the user's Account rows joined to Property by
  // accountNumber. `id` is the link (Account) id used by DELETE.
  app.get(
    "/account/properties",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const accounts = await prisma.account.findMany({
        where: { userId: req.userId, deletedAt: null },
        orderBy: { createdAt: "asc" },
      });
      const properties = await prisma.property.findMany({
        where: { accountNumber: { in: accounts.map((a) => a.accountNumber) } },
      });
      const byAcct = new Map(properties.map((p) => [p.accountNumber, p]));

      const items: LinkedPropertyResponse[] = accounts.map((a) => {
        const p = byAcct.get(a.accountNumber);
        const meta = (p?.metadata as Record<string, unknown> | null) ?? {};
        return {
          id: a.id,
          accountNumber: a.accountNumber,
          address: p?.address ?? "",
          erfNumber: p?.erfNumber ?? null,
          ward: typeof meta["ward"] === "string" ? (meta["ward"] as string) : "",
          status: a.status,
          linkedAt: a.createdAt.toISOString(),
        };
      });
      res.status(200).json(ok(items));
    }),
  );

  // ---- GET /account/preferences  (READ) ------------------------------------
  app.get(
    "/account/preferences",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const user = await prisma.user.findFirst({
        where: { id: req.userId, deletedAt: null },
      });
      if (!user) throw ApiError.unauthenticated("Session user not found.");
      res.status(200).json(ok(prefsOf(user)));
    }),
  );

  // ---- PUT /account/preferences  (WRITE, partial) --------------------------
  app.put(
    "/account/preferences",
    requireAuth(rt.tokens),
    rateLimit("WRITE"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const patch = parseOrValidationError(preferencesUpdateSchema, req.body);
      const data: Record<string, unknown> = {};
      if (patch.smsEnabled !== undefined) data.smsEnabled = patch.smsEnabled;
      if (patch.pushEnabled !== undefined) data.pushEnabled = patch.pushEnabled;
      if (patch.emailEnabled !== undefined) data.emailEnabled = patch.emailEnabled;
      if (patch.language !== undefined) data.preferredLanguage = patch.language;

      const user = await prisma.user.update({
        where: { id: req.userId },
        data,
      });
      res.status(200).json(ok(prefsOf(user)));
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
