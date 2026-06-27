import { createHash } from "node:crypto";
import express, { type Express, type Response } from "express";
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
  passesIdentityGate,
  toDetail,
  toSummary,
  type PropertySummaryResponse,
} from "./mappers.js";

// ---- Validation (property-service.md "Central resolutions") ----------------

const searchAccountSchema = z.object({
  accountNumber: z
    .string()
    .regex(/^\d{8}$/, "Must be exactly 8 digits."),
});

// Exactly one of q | erfNumber, each ≥ 3 chars (ADR-005).
const searchAddressSchema = z
  .object({
    q: z.string().min(3, "Must be at least 3 characters.").optional(),
    erfNumber: z.string().min(3, "Must be at least 3 characters.").optional(),
  })
  .refine(
    (v) => (v.q == null) !== (v.erfNumber == null),
    "Provide exactly one of q or erfNumber.",
  );

/**
 * Property reads are identity reference data — cacheable, user-specific
 * (property-service.md "Caching"): private, 30-min TTL + strong ETag for
 * If-None-Match revalidation. Returns true (and ends the response 304) when the
 * client's validator already matches.
 */
function applyCache(req: AuthedRequest, res: Response, payload: unknown): boolean {
  const etag =
    '"' +
    createHash("sha256").update(JSON.stringify(payload)).digest("hex") +
    '"';
  res.setHeader("Cache-Control", "private, max-age=1800");
  res.setHeader("ETag", etag);
  if (req.header("if-none-match") === etag) {
    res.status(304).end();
    return true;
  }
  return false;
}

/** Resolve the caller's keyed ID hash — the left side of the identity gate. */
async function callerIdHash(req: AuthedRequest): Promise<string | null> {
  const user = await prisma.user.findFirst({
    where: { id: req.userId, deletedAt: null },
    select: { idNumberHash: true },
  });
  if (!user) throw ApiError.unauthenticated("Session user not found.");
  return user.idNumberHash;
}

export function createPropertyApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  app.get(
    "/health",
    makeHealthHandler({ serviceName: "property-service" }),
  );

  // ---- POST /property/search/account ---------------------------------------
  // 200 + { property } on hit; 200 + { property: null } on no-match OR
  // identity-gate miss (byte-identical, deliberately ambiguous — ADR-004).
  app.post(
    "/property/search/account",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const { accountNumber } = parseOrValidationError(
        searchAccountSchema,
        req.body,
      );
      const idHash = await callerIdHash(req);

      const property = await prisma.property.findUnique({
        where: { accountNumber },
      });

      let result: PropertySummaryResponse | null = null;
      if (
        property &&
        passesIdentityGate(idHash, property.holderIdNumberHashes)
      ) {
        result = toSummary(property);
      }
      const payload = { property: result };
      if (applyCache(req, res, payload)) return;
      res.status(200).json(ok(payload));
    }),
  );

  // ---- POST /property/search/address ---------------------------------------
  // Array result; identity-gate misses fold into [] (never 404). q = partial
  // case-insensitive LIKE across address; erfNumber = exact normalized match.
  app.post(
    "/property/search/address",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const body = parseOrValidationError(searchAddressSchema, req.body);
      const idHash = await callerIdHash(req);

      const candidates = body.q
        ? await prisma.property.findMany({
            where: { address: { contains: body.q, mode: "insensitive" } },
          })
        : await prisma.property.findMany({
            where: {
              erfNumber: {
                equals: body.erfNumber!.trim(),
                mode: "insensitive",
              },
            },
          });

      const results = candidates
        .filter((p) => passesIdentityGate(idHash, p.holderIdNumberHashes))
        .map(toSummary);

      if (applyCache(req, res, results)) return;
      res.status(200).json(ok(results));
    }),
  );

  // ---- GET /property/:id ---------------------------------------------------
  // Concrete id in hand → 403 on a gate miss (not the ambiguous null), 404 when
  // no such id (ADR-004).
  app.get(
    "/property/:id",
    requireAuth(rt.tokens),
    rateLimit("READ"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const idHash = await callerIdHash(req);
      const property = await prisma.property.findUnique({
        where: { id: req.params.id },
      });
      if (!property) throw ApiError.notFound("Property not found.");
      if (!passesIdentityGate(idHash, property.holderIdNumberHashes)) {
        throw ApiError.forbidden("Property not linked to this user.");
      }
      const payload = toDetail(property);
      if (applyCache(req, res, payload)) return;
      res.status(200).json(ok(payload));
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
