import express, { type Express } from "express";
import multer from "multer";
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
import { Prisma, prisma } from "@easyrates/db";
import { env } from "@easyrates/config";
import {
  type AuthCoreRuntime,
  hashIdNumber,
  idNumberSchema,
  maskPhone,
  parseOrValidationError,
  phoneSchema,
} from "@easyrates/auth-core";
import { sendOtp } from "./otp-client.js";
import { type AuthedRequest, requireAuth } from "./auth-middleware.js";

const ACCEPTED_MIME = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
]);
const MAX_KYC_BYTES = 10_485_760; // 10 MB

const registerStartSchema = z.object({ phone: phoneSchema });

const registerSchema = z.object({
  phone: phoneSchema,
  displayName: z.string().min(1, "Display name is required."),
  email: z.string().email("Must be a valid email.").optional(),
  idNumber: idNumberSchema,
  registrationToken: z.string().min(1, "Registration token is required."),
});

const loginSchema = z.object({ phone: phoneSchema });
const refreshSchema = z.object({
  refreshToken: z.string().min(1, "Refresh token is required."),
});
const logoutSchema = z.object({
  refreshToken: z.string().min(1, "Refresh token is required."),
});

export function createAuthApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());
  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_KYC_BYTES },
  });

  app.get(
    "/health",
    makeHealthHandler({
      serviceName: "auth-service",
      pingQueue: async () => rt.storeBackend === "redis",
    }),
  );

  // ---- POST /auth/register/start  [public] ---------------------------------
  app.post(
    "/auth/register/start",
    rateLimit("AUTH"),
    asyncHandler(async (req, res) => {
      const { phone } = parseOrValidationError(registerStartSchema, req.body);
      const existing = await prisma.user.findFirst({
        where: { phone, deletedAt: null },
      });
      if (existing) {
        throw ApiError.conflict("That phone number is already registered.");
      }
      const sent = await sendOtp(phone, "REGISTRATION");
      res.status(202).json(
        ok({
          ttlSeconds: sent.ttlSeconds,
          resendCooldownSeconds: sent.resendCooldownSeconds,
          maskedPhone: maskPhone(phone),
        }),
      );
    }),
  );

  // ---- POST /auth/register  [public] ---------------------------------------
  app.post(
    "/auth/register",
    rateLimit("AUTH"),
    asyncHandler(async (req, res) => {
      const body = parseOrValidationError(registerSchema, req.body);
      // Consume the single-use registrationToken (bound to the verified phone).
      await rt.registrationTokens.consume(body.registrationToken, body.phone);

      const idNumberHash = hashIdNumber(body.idNumber, env.ID_NUMBER_HMAC_PEPPER);
      // body.idNumber (plaintext) is now discarded — never persisted (ADR-003).

      let user;
      try {
        user = await prisma.user.create({
          data: {
            phone: body.phone,
            displayName: body.displayName,
            email: body.email ?? null,
            idNumberHash,
            kycStatus: "PENDING",
          },
        });
      } catch (e) {
        if (
          e instanceof Prisma.PrismaClientKnownRequestError &&
          e.code === "P2002"
        ) {
          // Unique violation (phone or email) — race after register/start.
          throw ApiError.conflict("That phone number is already registered.");
        }
        throw e;
      }

      const pair = await rt.tokens.issueSession(user.id);
      res.status(201).json(
        ok({
          userId: pair.userId,
          accessToken: pair.accessToken,
          refreshToken: pair.refreshToken,
          accessTokenExpiresInSeconds: pair.accessTokenExpiresInSeconds,
          refreshTokenTtlDays: pair.refreshTokenTtlDays,
        }),
      );
    }),
  );

  // ---- POST /auth/login  [public] — anti-enumeration, always 200 -----------
  app.post(
    "/auth/login",
    rateLimit("AUTH"),
    asyncHandler(async (req, res) => {
      const { phone } = parseOrValidationError(loginSchema, req.body);
      const user = await prisma.user.findFirst({
        where: { phone, deletedAt: null },
      });
      // Only dispatch a LOGIN OTP if the phone is actually registered; the body
      // is byte-identical regardless (no enumeration leak).
      if (user) {
        await sendOtp(phone, "LOGIN");
      }
      res.status(200).json(
        ok({
          message: "If that number is registered, an OTP has been sent.",
          ttlSeconds: env.OTP_TTL_SECONDS,
          resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
          maskedPhone: maskPhone(phone),
        }),
      );
    }),
  );

  // ---- POST /auth/refresh  [public] — rotate -------------------------------
  app.post(
    "/auth/refresh",
    rateLimit("AUTH"),
    asyncHandler(async (req, res) => {
      const { refreshToken } = parseOrValidationError(refreshSchema, req.body);
      const pair = await rt.tokens.refresh(refreshToken);
      res.status(200).json(
        ok({
          accessToken: pair.accessToken,
          refreshToken: pair.refreshToken,
          accessTokenExpiresInSeconds: pair.accessTokenExpiresInSeconds,
          refreshTokenTtlDays: pair.refreshTokenTtlDays,
        }),
      );
    }),
  );

  // ---- POST /auth/logout  [auth] -------------------------------------------
  app.post(
    "/auth/logout",
    requireAuth(rt.tokens),
    asyncHandler(async (req, res) => {
      const { refreshToken } = parseOrValidationError(logoutSchema, req.body);
      await rt.tokens.revoke(refreshToken);
      res.status(200).json(ok({ message: "Logged out." }));
    }),
  );

  // ---- GET /auth/session  [auth] -------------------------------------------
  app.get(
    "/auth/session",
    requireAuth(rt.tokens),
    asyncHandler(async (req: AuthedRequest, res) => {
      const user = await prisma.user.findFirst({
        where: { id: req.userId, deletedAt: null },
      });
      if (!user) throw ApiError.unauthenticated("Session user not found.");
      res.status(200).json(
        ok({
          userId: user.id,
          phone: user.phone,
          kycStatus: user.kycStatus,
        }),
      );
    }),
  );

  // ---- POST /auth/kyc  [auth] multipart/form-data --------------------------
  app.post(
    "/auth/kyc",
    requireAuth(rt.tokens),
    upload.single("file"),
    asyncHandler(async (req: AuthedRequest, res) => {
      const file = req.file;
      if (!file) {
        throw new ApiError("file_missing", 400, "No file was uploaded.");
      }
      if (!ACCEPTED_MIME.has(file.mimetype)) {
        throw new ApiError(
          "invalid_file_type",
          422,
          "File type not accepted. Use PDF, JPEG, or PNG.",
        );
      }
      // Stub storage: real impl uploads to Azure Blob and records the key only.
      const kycDocumentKey = `kyc/${req.userId}/${Date.now()}-${file.originalname}`;
      const user = await prisma.user.update({
        where: { id: req.userId },
        data: { kycStatus: "SUBMITTED", kycDocumentKey },
      });
      res.status(201).json(
        ok({
          kycStatus: user.kycStatus,
          uploadedAt: new Date().toISOString(),
        }),
      );
    }),
  );

  // multer's LIMIT_FILE_SIZE → 413 (conventions: payload too large).
  app.use(
    (
      err: unknown,
      _req: express.Request,
      res: express.Response,
      next: express.NextFunction,
    ) => {
      if (err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE") {
        res.status(413).json({
          data: null,
          error: {
            code: "rate_limit_exceeded",
            message: "File exceeds the 10 MB limit.",
            details: { maxFileSizeBytes: MAX_KYC_BYTES },
          },
        });
        return;
      }
      next(err);
    },
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
