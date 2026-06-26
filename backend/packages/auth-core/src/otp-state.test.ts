import { describe, it, expect, beforeEach } from "vitest";
import { ApiError } from "@easyrates/http";
import { MemoryKvStore } from "./store.js";
import { OtpStateMachine, type OtpConfig } from "./otp-state.js";

const PHONE = "+27821234567";

const CFG: OtpConfig = {
  ttlSeconds: 600,
  resendCooldownSeconds: 30,
  maxResends: 3,
  maxAttempts: 5,
  codePepper: "test-pepper",
  mock: true, // so send()/resend() return the plaintext code for assertions
};

function makeSM(now: { t: number }) {
  const store = new MemoryKvStore(() => now.t);
  const sm = new OtpStateMachine(store, CFG);
  return { store, sm };
}

describe("OtpStateMachine", () => {
  let now: { t: number };
  beforeEach(() => {
    now = { t: 1_700_000_000_000 };
  });

  it("send returns lifecycle params and a 6-digit mock code", async () => {
    const { sm } = makeSM(now);
    const res = await sm.send(PHONE, "REGISTRATION");
    expect(res.ttlSeconds).toBe(600);
    expect(res.resendCooldownSeconds).toBe(30);
    expect(res.maxResends).toBe(3);
    expect(res.maxAttempts).toBe(5);
    expect(res.mockCode).toMatch(/^\d{6}$/);
  });

  it("verify with the correct code succeeds and returns the purpose, then is single-use", async () => {
    const { sm } = makeSM(now);
    const { mockCode } = await sm.send(PHONE, "LOGIN");
    const out = await sm.verify(PHONE, mockCode!);
    expect(out.purpose).toBe("LOGIN");
    // Single-use: the record is gone → a second verify reads as expired.
    await expect(sm.verify(PHONE, mockCode!)).rejects.toMatchObject({
      code: "otp_expired",
      httpStatus: 410,
    });
  });

  it("wrong code → otp_invalid 422 with attemptsRemaining decrementing", async () => {
    const { sm } = makeSM(now);
    await sm.send(PHONE, "REGISTRATION");

    for (let expectedRemaining = 4; expectedRemaining >= 1; expectedRemaining--) {
      try {
        await sm.verify(PHONE, "000000");
        throw new Error("expected otp_invalid to throw");
      } catch (e) {
        const err = e as ApiError;
        expect(err.code).toBe("otp_invalid");
        expect(err.httpStatus).toBe(422);
        expect(err.details.attemptsRemaining).toBe(expectedRemaining);
        expect(err.details.maxAttempts).toBe(5);
      }
    }
  });

  it("the 5th wrong code → max_attempts_exceeded 429 (no lockout, ADR-002)", async () => {
    const { sm } = makeSM(now);
    await sm.send(PHONE, "REGISTRATION");
    // 4 invalids (attempts 1..4)
    for (let i = 0; i < 4; i++) {
      await expect(sm.verify(PHONE, "000000")).rejects.toMatchObject({
        code: "otp_invalid",
      });
    }
    // 5th invalid exhausts the session.
    await expect(sm.verify(PHONE, "000000")).rejects.toMatchObject({
      code: "max_attempts_exceeded",
      httpStatus: 429,
      details: { maxAttempts: 5 },
    });
    // Session cleared → further verify reads as expired.
    await expect(sm.verify(PHONE, "000000")).rejects.toMatchObject({
      code: "otp_expired",
    });
  });

  it("expired code (TTL elapsed) → otp_expired 410 with ttlSeconds 0", async () => {
    const { sm } = makeSM(now);
    const { mockCode } = await sm.send(PHONE, "LOGIN");
    now.t += 601 * 1000; // advance past the 600s TTL
    await expect(sm.verify(PHONE, mockCode!)).rejects.toMatchObject({
      code: "otp_expired",
      httpStatus: 410,
      details: { ttlSeconds: 0 },
    });
  });

  it("a resend supersedes the prior code: old code is no longer accepted, new code verifies", async () => {
    const { sm } = makeSM(now);
    const first = await sm.send(PHONE, "LOGIN");
    now.t += 31 * 1000; // past the 30s cooldown
    const second = await sm.resend(PHONE, "LOGIN");
    expect(second.mockCode).not.toBe(first.mockCode);
    // The resend replaced the live record, so the OLD code is now a wrong code
    // against the NEW record → otp_invalid (the record still exists). It is only
    // otp_expired once the record itself is gone (see the TTL-elapsed test).
    await expect(sm.verify(PHONE, first.mockCode!)).rejects.toMatchObject({
      code: "otp_invalid",
    });
    // New code verifies.
    const out = await sm.verify(PHONE, second.mockCode!);
    expect(out.purpose).toBe("LOGIN");
  });

  it("superseded-then-expired old code → otp_expired (record gone)", async () => {
    const { sm } = makeSM(now);
    const first = await sm.send(PHONE, "LOGIN");
    now.t += 31 * 1000;
    await sm.resend(PHONE, "LOGIN"); // new record, fresh 600s TTL
    now.t += 601 * 1000; // let the new record expire too
    // Record now gone entirely → otp_expired for any code.
    await expect(sm.verify(PHONE, first.mockCode!)).rejects.toMatchObject({
      code: "otp_expired",
      details: { ttlSeconds: 0 },
    });
  });

  it("resend within cooldown → resend_cooldown_active 429 with remaining seconds", async () => {
    const { sm } = makeSM(now);
    await sm.send(PHONE, "REGISTRATION");
    now.t += 10 * 1000; // only 10s elapsed of a 30s cooldown
    try {
      await sm.resend(PHONE, "REGISTRATION");
      throw new Error("expected resend_cooldown_active to throw");
    } catch (e) {
      const err = e as ApiError;
      expect(err.code).toBe("resend_cooldown_active");
      expect(err.httpStatus).toBe(429);
      expect(err.details.retryAfterSeconds).toBe(20); // 30 - 10
    }
  });

  it("resend decrements resendsRemaining and resets the attempt counter", async () => {
    const { sm } = makeSM(now);
    await sm.send(PHONE, "LOGIN");
    // Burn one attempt on the first code.
    await expect(sm.verify(PHONE, "000000")).rejects.toMatchObject({
      code: "otp_invalid",
      details: { attemptsRemaining: 4 },
    });
    now.t += 31 * 1000;
    const r1 = await sm.resend(PHONE, "LOGIN");
    expect(r1.resendsRemaining).toBe(2);
    // Fresh code → attempts reset: first wrong attempt shows 4 remaining again.
    await expect(sm.verify(PHONE, "000000")).rejects.toMatchObject({
      code: "otp_invalid",
      details: { attemptsRemaining: 4 },
    });
    now.t += 31 * 1000;
    const r2 = await sm.resend(PHONE, "LOGIN");
    expect(r2.resendsRemaining).toBe(1);
    now.t += 31 * 1000;
    const r3 = await sm.resend(PHONE, "LOGIN");
    expect(r3.resendsRemaining).toBe(0);
  });
});
