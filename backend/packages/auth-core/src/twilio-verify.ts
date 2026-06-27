import {
  maxAttemptsExceeded,
  otpExpired,
  otpInvalid,
} from "./otp-errors.js";
import type { KvStore } from "./store.js";
import type { OtpProvider } from "./otp-provider.js";
import type { OtpPurpose, ResendResult, SendResult } from "./otp-state.js";

/**
 * TwilioVerifyProvider — real OTP delivery via Twilio Verify v2.
 *
 *  send/resend → `verify.v2.services(SID).verifications.create({ to, channel:'sms' })`
 *  verify      → `verify.v2.services(SID).verificationChecks.create({ to, code })`
 *
 * Twilio owns the code, its TTL, and the attempt counter — so this provider does
 * NOT generate or hash a code. It keeps a tiny side record (purpose + resend
 * count) in the KvStore so the route can branch REGISTRATION vs LOGIN and so
 * `resendsRemaining` is reportable; Twilio is the authority for everything else.
 *
 * Outcome → canonical OTP error mapping (the seam tested with a double):
 *   - check status "approved"        → success
 *   - check status "pending" / other → otp_invalid (422)
 *   - Twilio error 60200             → otp_expired (410)  (invalid/expired params)
 *   - Twilio error 60202             → max_attempts_exceeded (429)
 *   - Twilio error 20404             → otp_expired (410)  (verification not found = expired/consumed)
 */

/** Minimal slice of the Twilio SDK surface this provider uses (keeps it injectable). */
export interface TwilioVerifyApi {
  verifications: {
    create(args: { to: string; channel: "sms" }): Promise<{ status: string; sid?: string }>;
  };
  verificationChecks: {
    create(args: { to: string; code: string }): Promise<{ status: string }>;
  };
}

/** A Twilio API error carries a numeric `code` (e.g. 60200). */
export interface TwilioLikeError {
  code?: number;
  status?: number;
  message?: string;
}

export interface TwilioVerifyConfig {
  ttlSeconds: number;
  resendCooldownSeconds: number;
  maxResends: number;
  maxAttempts: number;
}

interface PurposeRecord {
  purpose: OtpPurpose;
  resendCount: number;
}

function purposeKey(phone: string): string {
  return `otp:purpose:${phone}`;
}

function isTwilioError(e: unknown): e is TwilioLikeError {
  return typeof e === "object" && e !== null && "code" in e;
}

/**
 * Map a Twilio verificationChecks outcome (or thrown Twilio error) to the
 * canonical result. PURE — the unit tests drive every branch with plain objects,
 * no network. Returns `{ approved: true }` on success; otherwise THROWS the
 * canonical ApiError.
 */
export function mapVerifyOutcome(
  result: { status: string } | null,
  error: TwilioLikeError | null,
  maxAttempts: number,
): { approved: true } {
  if (error) {
    switch (error.code) {
      case 60200: // invalid parameter — Twilio treats an expired/invalid code here
        throw otpExpired();
      case 60202: // max check attempts reached
        throw maxAttemptsExceeded(maxAttempts);
      case 20404: // verification resource not found (expired or already consumed)
        throw otpExpired();
      default:
        // Unknown Twilio failure on a check → treat as an invalid attempt.
        throw otpInvalid(maxAttempts, maxAttempts);
    }
  }
  if (result && result.status === "approved") {
    return { approved: true };
  }
  // "pending" (or anything not approved) = wrong code still outstanding.
  throw otpInvalid(maxAttempts, maxAttempts);
}

export class TwilioVerifyProvider implements OtpProvider {
  constructor(
    private readonly api: TwilioVerifyApi,
    private readonly store: KvStore,
    private readonly cfg: TwilioVerifyConfig,
  ) {}

  private async loadPurpose(phone: string): Promise<PurposeRecord | null> {
    const raw = await this.store.get(purposeKey(phone));
    return raw ? (JSON.parse(raw) as PurposeRecord) : null;
  }

  async send(phone: string, purpose: OtpPurpose): Promise<SendResult> {
    await this.api.verifications.create({ to: phone, channel: "sms" });
    const rec: PurposeRecord = { purpose, resendCount: 0 };
    await this.store.set(purposeKey(phone), JSON.stringify(rec), this.cfg.ttlSeconds);
    // No mockCode — real SMS is in flight.
    return {
      ttlSeconds: this.cfg.ttlSeconds,
      resendCooldownSeconds: this.cfg.resendCooldownSeconds,
      maxResends: this.cfg.maxResends,
      maxAttempts: this.cfg.maxAttempts,
    };
  }

  async verify(phone: string, code: string): Promise<{ purpose: OtpPurpose }> {
    const rec = await this.loadPurpose(phone);
    // No live side record → the verification has expired/been consumed.
    if (!rec) throw otpExpired();

    let result: { status: string } | null = null;
    let error: TwilioLikeError | null = null;
    try {
      result = await this.api.verificationChecks.create({ to: phone, code });
    } catch (e) {
      if (isTwilioError(e)) error = e;
      else throw e;
    }
    mapVerifyOutcome(result, error, this.cfg.maxAttempts);
    // Approved — single-use: clear the side record.
    await this.store.del(purposeKey(phone));
    return { purpose: rec.purpose };
  }

  async resend(phone: string, purpose: OtpPurpose): Promise<ResendResult> {
    const existing = await this.loadPurpose(phone);
    await this.api.verifications.create({ to: phone, channel: "sms" });
    const priorResends = existing?.resendCount ?? 0;
    const newResendCount = Math.min(priorResends + 1, this.cfg.maxResends);
    const resendsRemaining = Math.max(this.cfg.maxResends - newResendCount, 0);
    const rec: PurposeRecord = { purpose, resendCount: newResendCount };
    await this.store.set(purposeKey(phone), JSON.stringify(rec), this.cfg.ttlSeconds);
    return {
      ttlSeconds: this.cfg.ttlSeconds,
      resendCooldownSeconds: this.cfg.resendCooldownSeconds,
      resendsRemaining,
    };
  }
}
