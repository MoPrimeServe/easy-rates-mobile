import express, { type Express, type NextFunction, type Request, type Response } from "express";
import { z } from "zod";
import {
  ApiError,
  asyncHandler,
  errorMiddleware,
  makeHealthHandler,
  notFoundMiddleware,
  ok,
  writeAudit,
} from "@easyrates/http";
import { env } from "@easyrates/config";
import { prisma, Prisma } from "@easyrates/db";
import { getRedis } from "@easyrates/auth-core";
import { getMunicipalityResponseAdapter } from "@easyrates/adapters";
import { enqueueNotification, pingQueue } from "@easyrates/queue";
import { decideIdempotency, secretMatches } from "./logic.js";

const IDEMPOTENCY_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days

const webhookSchema = z.object({
  status: z.enum(["UNDER_REVIEW", "MORE_INFO_REQUESTED", "UPHELD", "REJECTED"], {
    errorMap: () => ({ message: "Must be a valid ObjectionStatus." }),
  }),
  note: z
    .string()
    .min(10, "Must be 10–1000 characters.")
    .max(1000, "Must be 10–1000 characters."),
  adjustedAmount: z
    .string()
    .regex(/^\d+(\.\d{1,2})?$/, "Must be a decimal string with up to 2 fraction digits.")
    .optional(),
  resolvedBy: z.string().min(1, "resolvedBy is required."),
  idempotencyKey: z.string().min(1, "idempotencyKey is required."),
});

/** Shared-secret middleware. `X-Municipal-Webhook-Secret`, constant-time compare. */
function requireWebhookSecret(req: Request, _res: Response, next: NextFunction): void {
  const provided = req.header("x-municipal-webhook-secret");
  if (!secretMatches(provided ?? undefined, env.MUNICIPAL_WEBHOOK_SECRET)) {
    next(ApiError.unauthenticated("Missing or invalid webhook secret."));
    return;
  }
  next();
}

/** Maps the validation error so details.fields carries the field paths (§4). */
function parseWebhook(body: unknown): z.infer<typeof webhookSchema> {
  const result = webhookSchema.safeParse(body);
  if (result.success) return result.data;
  const fields: Record<string, string> = {};
  for (const issue of result.error.issues) {
    const path = issue.path.join(".") || "(root)";
    if (!(path in fields)) fields[path] = issue.message;
  }
  throw ApiError.validation(fields);
}

export function createMunicipalityApp(): Express {
  const app = express();
  app.use(express.json());

  app.get(
    "/health",
    makeHealthHandler({ serviceName: "municipality-service", pingQueue }),
  );

  // ---- POST /municipality/objections/:ref/response  [webhook] --------------
  app.post(
    "/municipality/objections/:ref/response",
    requireWebhookSecret,
    asyncHandler(async (req: Request, res: Response) => {
      const body = parseWebhook(req.body);
      const ref = req.params.ref!; // route param — always present
      const redis = getRedis(env.REDIS_URL);
      const dedupKey = `muni:idem:${body.idempotencyKey}`;

      // Idempotency replay: a seen key returns the ORIGINAL 200 with no side
      // effects. Graceful if Redis is down (dedup skipped — noted).
      if (redis) {
        const prior = await redis.get(dedupKey).catch(() => null);
        const idem = decideIdempotency(prior);
        if (idem.kind === "replay") {
          res.status(200).json(ok(idem.payload));
          return;
        }
      }

      const objection = await prisma.objection.findUnique({
        where: { refNumber: ref },
      });
      if (!objection) {
        throw ApiError.notFound("No objection matches that refNumber.");
      }

      // POPIA audit: an inbound municipal response was received for this
      // objection (recorded regardless of whether the transition is applied).
      await writeAudit({
        event: "MUNICIPALITY_RESPONSE_RECEIVED",
        userId: objection.userId,
        entityId: objection.id,
        entityType: "Objection",
        metadata: { refNumber: ref, requestedStatus: body.status },
      });

      // Ingest the response through the swappable MunicipalityResponseAdapter
      // (default impl applies the locked four-value state machine).
      const decision = getMunicipalityResponseAdapter().classify(
        objection.status,
        {
          refNumber: ref,
          status: body.status,
          note: body.note,
          adjustedAmount: body.adjustedAmount ?? null,
        },
      );

      // Step 1 — INSERT MunicipalityResponse for audit on EVERY call (even 409).
      const responseRow = {
        objectionId: objection.id,
        status: body.status,
        note: body.note,
        adjustedAmount:
          body.adjustedAmount != null
            ? new Prisma.Decimal(body.adjustedAmount)
            : null,
      };

      if (decision.kind === "terminal") {
        await prisma.municipalityResponse.create({ data: responseRow });
        throw new ApiError(
          "conflict",
          409,
          `Objection ${ref} is terminal and cannot be re-opened.`,
          { currentStatus: objection.status, requestedStatus: body.status },
        );
      }

      if (decision.kind === "illegal") {
        await prisma.municipalityResponse.create({ data: responseRow });
        throw ApiError.unprocessable(
          `Illegal state transition for objection ${ref}.`,
          { currentStatus: objection.status, requestedStatus: body.status },
        );
      }

      // Steps 1–2 in a single transaction (apply path).
      await prisma.$transaction([
        prisma.municipalityResponse.create({ data: responseRow }),
        prisma.objection.update({
          where: { id: objection.id },
          data: { status: body.status },
        }),
      ]);

      // Step 3 (async) — persist a Notification row + enqueue dispatch.
      const notificationType =
        body.status === "MORE_INFO_REQUESTED"
          ? "MORE_INFO_REQUESTED"
          : "OBJECTION_STATUS";
      const notification = await prisma.notification.create({
        data: {
          userId: objection.userId,
          objectionId: objection.id,
          type: notificationType,
          channel: "PUSH",
          status: "PENDING",
        },
      });
      await enqueueNotification({ notificationId: notification.id });

      const payload = {
        refNumber: ref,
        status: body.status,
        notificationQueued: true as const,
      };

      // Record the original result against the idempotency key (30-day TTL).
      if (redis) {
        await redis
          .set(dedupKey, JSON.stringify(payload), "EX", IDEMPOTENCY_TTL_SECONDS)
          .catch(() => undefined);
      }

      res.status(200).json(ok(payload));
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
