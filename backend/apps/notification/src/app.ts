import express, { type Express } from "express";
import { z } from "zod";
import {
  ApiError,
  asyncHandler,
  errorMiddleware,
  makeHealthHandler,
  notFoundMiddleware,
  ok,
} from "@easyrates/http";
import { prisma } from "@easyrates/db";
import {
  type AuthCoreRuntime,
  type AuthedRequest,
  parseOrValidationError,
  requireAuth,
} from "@easyrates/auth-core";
import { pingQueue } from "@easyrates/queue";
import { inboxWhere, toInboxItem } from "./logic.js";

const listQuerySchema = z.object({
  page: z.coerce.number().int().min(1, "page must be ≥ 1.").default(1),
  pageSize: z.coerce
    .number()
    .int()
    .min(1, "pageSize must be ≥ 1.")
    .max(100, "pageSize must be ≤ 100.")
    .default(20),
  unreadOnly: z
    .union([z.literal("true"), z.literal("false"), z.boolean()])
    .optional()
    .transform((v) => v === true || v === "true"),
});

const deviceTokenSchema = z.object({
  deviceToken: z.string().min(1, "deviceToken is required."),
  platform: z.enum(["ANDROID", "IOS"], {
    errorMap: () => ({ message: "platform must be ANDROID or IOS." }),
  }),
});

export function createNotificationApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  app.get(
    "/health",
    makeHealthHandler({ serviceName: "notification-service", pingQueue }),
  );

  // ---- GET /notifications (paginated inbox, unreadOnly filter) --------------
  app.get(
    "/notifications",
    requireAuth(rt.tokens),
    asyncHandler(async (req: AuthedRequest, res) => {
      const { page, pageSize, unreadOnly } = parseOrValidationError(
        listQuerySchema,
        req.query,
      );

      const where = inboxWhere(req.userId!, unreadOnly);

      const [total, rows] = await Promise.all([
        prisma.notification.count({ where }),
        prisma.notification.findMany({
          where,
          orderBy: { sentAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: {
            objection: { select: { refNumber: true } },
          },
        }),
      ]);

      const items = rows.map((n) =>
        toInboxItem(n, n.objection?.refNumber ?? null),
      );

      res.status(200).json(
        ok({
          items,
          page,
          pageSize,
          total,
          totalPages: Math.ceil(total / pageSize),
        }),
      );
    }),
  );

  // ---- POST /notifications/read-all (must precede :id/read) ----------------
  app.post(
    "/notifications/read-all",
    requireAuth(rt.tokens),
    asyncHandler(async (req: AuthedRequest, res) => {
      const result = await prisma.notification.updateMany({
        where: { userId: req.userId, readAt: null },
        data: { readAt: new Date() },
      });
      res.status(200).json(ok({ updatedCount: result.count }));
    }),
  );

  // ---- POST /notifications/:id/read ----------------------------------------
  app.post(
    "/notifications/:id/read",
    requireAuth(rt.tokens),
    asyncHandler(async (req: AuthedRequest, res) => {
      const notification = await prisma.notification.findUnique({
        where: { id: req.params.id },
        select: { id: true, userId: true, readAt: true },
      });
      if (!notification) throw ApiError.notFound("Notification not found.");
      if (notification.userId !== req.userId) {
        throw ApiError.forbidden("Notification owned by another user.");
      }
      // Idempotent: marking an already-read notification still returns 200.
      if (!notification.readAt) {
        await prisma.notification.update({
          where: { id: notification.id },
          data: { readAt: new Date() },
        });
      }
      res.status(200).json(ok({ id: notification.id, read: true }));
    }),
  );

  // ---- POST /notifications/device-token ------------------------------------
  app.post(
    "/notifications/device-token",
    requireAuth(rt.tokens),
    asyncHandler(async (req: AuthedRequest, res) => {
      const body = parseOrValidationError(deviceTokenSchema, req.body);
      await prisma.user.update({
        where: { id: req.userId },
        data: { deviceToken: body.deviceToken },
      });
      res.status(200).json(ok({ registered: true }));
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
