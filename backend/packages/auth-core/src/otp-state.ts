import { createHmac, randomInt, timingSafeEqual } from "node:crypto";
import type { KvStore } from "./store.js";
import {
  maxAttemptsExceeded,
  otpExpired,
  otpInvalid,
  resendCooldownActive,
} from "./otp-errors.js";

export type OtpPurpose = "REGISTRATION" | "LOGIN";

/** Per-phone OTP session persisted as JSON in the KvStore at `otp:{phone}`. */
interface OtpRecord {
  codeHash: string;
  purpose: OtpPurpose;
  maxAttempts: number;
  attempts: number;
  resendCount: number; // resends used this session (initial send = 0)
  lastSentAtMs: number; // for resend cooldown
}

export interface OtpConfig {
  ttlSeconds: number; // OTP_TTL_SECONDS (600)
  resendCooldownSeconds: number; // OTP_RESEND_COOLDOWN_SECONDS (30)
  maxResends: number; // OTP_MAX_RESENDS_PER_SESSION (3)
  maxAttempts: number; // OTP_MAX_INVALID_ATTEMPTS (5)
  /** HMAC pepper for hashing the 6-digit code (never store/compare plaintext). */
  codePepper: string;
  /** OTP_MOCK: when true, send() returns the plaintext code (dev only). */
  mock: boolean;
}

function key(phone: string): string {
  return `otp:${phone}`;
}

function hashCode(code: string, pepper: string): string {
  return createHmac("sha256", pepper).update(code).digest("hex");
}

function constantTimeEqualHex(a: string, b: string): boolean {
  const ab = Buffer.from(a, "hex");
  const bb = Buffer.from(b, "hex");
  if (ab.length !== bb.length || ab.length === 0) return false;
  return timingSafeEqual(ab, bb);
}

/** Generate a uniformly-random 6-digit code (CSPRNG), zero-padded. */
export function generateCode(): string {
  return String(randomInt(0, 1_000_000)).padStart(6, "0");
}

export interface SendResult {
  ttlSeconds: number;
  resendCooldownSeconds: number;
  maxResends: number;
  maxAttempts: number;
  /** Present only when mock=true (dev): the plaintext code, for the smoke flow. */
  mockCode?: string;
}

export interface ResendResult {
  ttlSeconds: number;
  resendCooldownSeconds: number;
  resendsRemaining: number;
  mockCode?: string;
}

/**
 * The OTP state machine — store-agnostic, fully unit-testable. Owns code
 * generation, hashing, TTL/expiry, attempt counting, and resend cooldown.
 * Errors thrown are `ApiError`s carrying the canonical otp-service codes.
 */
export class OtpStateMachine {
  constructor(
    private readonly store: KvStore,
    private readonly cfg: OtpConfig,
  ) {}

  /** Start (or restart) a verification: generate a code, persist a fresh record. */
  async send(phone: string, purpose: OtpPurpose): Promise<SendResult> {
    const code = generateCode();
    const record: OtpRecord = {
      codeHash: hashCode(code, this.cfg.codePepper),
      purpose,
      maxAttempts: this.cfg.maxAttempts,
      attempts: 0,
      resendCount: 0,
      lastSentAtMs: this.store.now(),
    };
    await this.store.set(key(phone), JSON.stringify(record), this.cfg.ttlSeconds);
    return {
      ttlSeconds: this.cfg.ttlSeconds,
      resendCooldownSeconds: this.cfg.resendCooldownSeconds,
      maxResends: this.cfg.maxResends,
      maxAttempts: this.cfg.maxAttempts,
      ...(this.cfg.mock ? { mockCode: code } : {}),
    };
  }

  private async load(phone: string): Promise<OtpRecord | null> {
    const raw = await this.store.get(key(phone));
    if (!raw) return null;
    return JSON.parse(raw) as OtpRecord;
  }

  /**
   * Verify a submitted code. On success the record is cleared and the verified
   * purpose returned (caller mints registrationToken or the session). On
   * failure throws the canonical OTP error:
   *   - no live record (expired / superseded) → otp_expired (410)
   *   - already at max attempts              → max_attempts_exceeded (429)
   *   - wrong code                           → otp_invalid (422, attemptsRemaining)
   */
  async verify(
    phone: string,
    code: string,
  ): Promise<{ purpose: OtpPurpose }> {
    const record = await this.load(phone);
    // Missing key = expired OR superseded by a resend that has itself expired.
    if (!record) throw otpExpired();

    // Already exhausted (defensive — exhausted records are deleted below).
    if (record.attempts >= record.maxAttempts) {
      await this.store.del(key(phone));
      throw maxAttemptsExceeded(record.maxAttempts);
    }

    const submittedHash = hashCode(code, this.cfg.codePepper);
    if (constantTimeEqualHex(submittedHash, record.codeHash)) {
      await this.store.del(key(phone)); // single-use: clear on approval
      return { purpose: record.purpose };
    }

    // Wrong code — count the attempt, preserving the remaining TTL.
    record.attempts += 1;
    const remainingTtl = await this.store.ttl(key(phone));
    const ttl = remainingTtl > 0 ? remainingTtl : this.cfg.ttlSeconds;

    if (record.attempts >= record.maxAttempts) {
      // Final wrong attempt exhausts the session — no lockout, just resend (ADR-002).
      await this.store.del(key(phone));
      throw maxAttemptsExceeded(record.maxAttempts);
    }

    await this.store.set(key(phone), JSON.stringify(record), ttl);
    throw otpInvalid(record.maxAttempts - record.attempts, record.maxAttempts);
  }

  /**
   * Resend: cancel the live code and mint a new one. Enforces the resend
   * cooldown (resend_cooldown_active with the REMAINING seconds) and the
   * per-session resend cap (surfaced via resendsRemaining, not an error).
   */
  async resend(phone: string, purpose: OtpPurpose): Promise<ResendResult> {
    const existing = await this.load(phone);

    // Cooldown is measured from the last send of the live session, if any.
    if (existing) {
      const elapsed = Math.floor(
        (this.store.now() - existing.lastSentAtMs) / 1000,
      );
      const remaining = this.cfg.resendCooldownSeconds - elapsed;
      if (remaining > 0) throw resendCooldownActive(remaining);
    }

    const priorResends = existing?.resendCount ?? 0;
    const newResendCount = Math.min(priorResends + 1, this.cfg.maxResends);
    const resendsRemaining = Math.max(this.cfg.maxResends - newResendCount, 0);

    const code = generateCode();
    const record: OtpRecord = {
      codeHash: hashCode(code, this.cfg.codePepper),
      purpose,
      maxAttempts: this.cfg.maxAttempts,
      attempts: 0, // a fresh code resets the attempt counter
      resendCount: newResendCount,
      lastSentAtMs: this.store.now(),
    };
    await this.store.set(key(phone), JSON.stringify(record), this.cfg.ttlSeconds);

    return {
      ttlSeconds: this.cfg.ttlSeconds,
      resendCooldownSeconds: this.cfg.resendCooldownSeconds,
      resendsRemaining,
      ...(this.cfg.mock ? { mockCode: code } : {}),
    };
  }
}
