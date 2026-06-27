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
  writeAudit,
} from "@easyrates/http";
import { prisma } from "@easyrates/db";
import { env } from "@easyrates/config";
import {
  type AuthCoreRuntime,
  maskPhone,
  parseOrValidationError,
  phoneSchema,
} from "@easyrates/auth-core";

const sendSchema = z.object({
  phone: phoneSchema,
  purpose: z.enum(["REGISTRATION", "LOGIN"]),
});

const verifySchema = z.object({
  phone: phoneSchema,
  code: z.string().regex(/^\d{6}$/, "Must be a 6-digit code."),
});

const resendSchema = z.object({
  phone: phoneSchema,
  purpose: z.enum(["REGISTRATION", "LOGIN"]),
});

/**
 * Best-effort LOGIN audit mirror into the live OTPAttempt table. Only possible
 * once a User exists (the table's userId FK). Never blocks the response.
 */
async function mirrorLoginAttempt(userId: string): Promise<void> {
  try {
    await prisma.oTPAttempt.create({
      data: {
        userId,
        code: "verified", // authoritative hash lives in the phone-keyed store
        purpose: "LOGIN",
        attempts: 0,
        maxAttempts: env.OTP_MAX_INVALID_ATTEMPTS,
        expiresAt: new Date(Date.now() + env.OTP_TTL_SECONDS * 1000),
        verifiedAt: new Date(),
      },
    });
  } catch (e) {
    console.warn("[otp] OTPAttempt mirror failed (non-fatal):", e);
  }
}

export function createOtpApp(rt: AuthCoreRuntime): Express {
  const app = express();
  app.use(express.json());

  app.get(
    "/health",
    makeHealthHandler({
      serviceName: "otp-service",
      pingQueue: async () => rt.storeBackend === "redis",
    }),
  );

  // ---- POST /otp/send  [internal] — server-to-server from auth-service ------
  app.post(
    "/otp/send",
    rateLimit("OTP-SEND"),
    asyncHandler(async (req, res) => {
      const provided = req.header("x-internal-secret");
      if (provided !== env.INTERNAL_API_SECRET) {
        throw ApiError.unauthenticated("Internal endpoint.");
      }
      const { phone, purpose } = parseOrValidationError(sendSchema, req.body);
      const result = await rt.otp.send(phone, purpose);
      if (result.mockCode) {
        console.log(`[otp][mock] code for ${phone} (${purpose}): ${result.mockCode}`);
      }
      res.status(202).json(
        ok({
          ttlSeconds: result.ttlSeconds,
          resendCooldownSeconds: result.resendCooldownSeconds,
          maxResends: result.maxResends,
          maxAttempts: result.maxAttempts,
          // mockCode is surfaced ONLY in mock mode so the auth flow / smoke test
          // can read it without SMS. Never present when OTP_MOCK=false.
          ...(result.mockCode ? { mockCode: result.mockCode } : {}),
        }),
      );
    }),
  );

  // ---- POST /otp/verify  [public] ------------------------------------------
  app.post(
    "/otp/verify",
    rateLimit("OTP-VERIFY"),
    asyncHandler(async (req, res) => {
      const { phone, code } = parseOrValidationError(verifySchema, req.body);

      let purpose: "REGISTRATION" | "LOGIN";
      try {
        ({ purpose } = await rt.otp.verify(phone, code));
      } catch (err) {
        // Wrong / expired / missing OTP. POPIA security event — no userId yet,
        // no raw phone (masked only), no code persisted.
        await writeAudit({
          event: "LOGIN_FAILED",
          ip: req.ip,
          metadata: { maskedPhone: maskPhone(phone) },
        });
        throw err;
      }

      if (purpose === "REGISTRATION") {
        // No User yet — return a single-use registrationToken.
        const registrationToken = await rt.registrationTokens.mint(phone);
        res.status(200).json(
          ok({ registrationToken, ttlSeconds: env.REGISTRATION_TOKEN_TTL_SECONDS }),
        );
        return;
      }

      // LOGIN — the User must already exist; issue the session token pair.
      const user = await prisma.user.findFirst({
        where: { phone, deletedAt: null },
      });
      if (!user) {
        // A LOGIN OTP is only ever dispatched for a registered phone, so this
        // is an unexpected state. Treat as expired (no enumeration leak).
        throw ApiError.unauthenticated("No active account for this phone.");
      }
      const pair = await rt.tokens.issueSession(user.id);
      await mirrorLoginAttempt(user.id);
      // POPIA audit: a successful login (session minted) for this user.
      await writeAudit({
        event: "LOGIN_SUCCESS",
        userId: user.id,
        entityId: user.id,
        entityType: "User",
        ip: req.ip,
      });
      res.status(200).json(
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

  // ---- POST /otp/resend  [public] ------------------------------------------
  app.post(
    "/otp/resend",
    rateLimit("OTP-SEND"),
    asyncHandler(async (req, res) => {
      const { phone, purpose } = parseOrValidationError(resendSchema, req.body);
      const result = await rt.otp.resend(phone, purpose);
      if (result.mockCode) {
        console.log(`[otp][mock] resent code for ${phone} (${purpose}): ${result.mockCode}`);
      }
      res.status(202).json(
        ok({
          ttlSeconds: result.ttlSeconds,
          resendCooldownSeconds: result.resendCooldownSeconds,
          resendsRemaining: result.resendsRemaining,
          ...(result.mockCode ? { mockCode: result.mockCode } : {}),
        }),
      );
    }),
  );

  app.use(notFoundMiddleware);
  app.use(errorMiddleware);
  return app;
}
