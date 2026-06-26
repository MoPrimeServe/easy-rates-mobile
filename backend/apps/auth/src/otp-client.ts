import { env } from "@easyrates/config";
import { ApiError } from "@easyrates/http";
import type { OtpPurpose } from "@easyrates/auth-core";

/**
 * Server-to-server client for otp-service `POST /otp/send` `[internal]`. The
 * Flutter client never calls this (ADR-002 §2) — auth-service is the only
 * caller, authenticating with the shared INTERNAL_API_SECRET.
 */
export interface OtpSendResult {
  ttlSeconds: number;
  resendCooldownSeconds: number;
  maxResends: number;
  maxAttempts: number;
}

export async function sendOtp(
  phone: string,
  purpose: OtpPurpose,
): Promise<OtpSendResult> {
  let resp: Response;
  try {
    resp = await fetch(`${env.OTP_SERVICE_URL}/otp/send`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-internal-secret": env.INTERNAL_API_SECRET,
      },
      body: JSON.stringify({ phone, purpose }),
    });
  } catch (e) {
    console.error("[auth] otp-service unreachable:", e);
    throw ApiError.internal("OTP dispatch failed.");
  }

  const json = (await resp.json()) as {
    data: OtpSendResult | null;
    error: { code: string; message: string } | null;
  };
  if (!resp.ok || !json.data) {
    console.error("[auth] otp/send error:", resp.status, json.error);
    throw ApiError.internal("OTP dispatch failed.");
  }
  return json.data;
}
