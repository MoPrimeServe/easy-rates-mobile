import { describe, it, expect, beforeEach } from "vitest";
import { ApiError } from "@easyrates/http";
import { MemoryKvStore } from "./store.js";
import {
  TwilioVerifyProvider,
  mapVerifyOutcome,
  type TwilioVerifyApi,
  type TwilioVerifyConfig,
} from "./twilio-verify.js";

const PHONE = "+27821234567";
const CFG: TwilioVerifyConfig = {
  ttlSeconds: 600,
  resendCooldownSeconds: 30,
  maxResends: 3,
  maxAttempts: 5,
};

/** A scriptable Twilio Verify double — records calls, returns scripted outcomes. */
function makeApi(script: {
  verifyResult?: { status: string };
  verifyError?: { code?: number };
}): { api: TwilioVerifyApi; calls: { verifications: number; checks: number } } {
  const calls = { verifications: 0, checks: 0 };
  const api: TwilioVerifyApi = {
    verifications: {
      async create() {
        calls.verifications += 1;
        return { status: "pending", sid: "VExxxx" };
      },
    },
    verificationChecks: {
      async create() {
        calls.checks += 1;
        if (script.verifyError) throw script.verifyError;
        return script.verifyResult ?? { status: "pending" };
      },
    },
  };
  return { api, calls };
}

describe("mapVerifyOutcome (Twilio → canonical)", () => {
  it("approved → success (no throw)", () => {
    expect(mapVerifyOutcome({ status: "approved" }, null, 5)).toEqual({
      approved: true,
    });
  });

  it("pending → otp_invalid (422)", () => {
    try {
      mapVerifyOutcome({ status: "pending" }, null, 5);
      throw new Error("should have thrown");
    } catch (e) {
      expect(e).toBeInstanceOf(ApiError);
      expect((e as ApiError).code).toBe("otp_invalid");
      expect((e as ApiError).httpStatus).toBe(422);
    }
  });

  it("error 60200 → otp_expired (410)", () => {
    try {
      mapVerifyOutcome(null, { code: 60200 }, 5);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as ApiError).code).toBe("otp_expired");
      expect((e as ApiError).httpStatus).toBe(410);
    }
  });

  it("error 60202 → max_attempts_exceeded (429)", () => {
    try {
      mapVerifyOutcome(null, { code: 60202 }, 5);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as ApiError).code).toBe("max_attempts_exceeded");
      expect((e as ApiError).httpStatus).toBe(429);
    }
  });

  it("error 20404 (verification not found) → otp_expired (410)", () => {
    try {
      mapVerifyOutcome(null, { code: 20404 }, 5);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as ApiError).code).toBe("otp_expired");
    }
  });

  it("unknown Twilio error → otp_invalid (422)", () => {
    try {
      mapVerifyOutcome(null, { code: 99999 }, 5);
      throw new Error("should have thrown");
    } catch (e) {
      expect((e as ApiError).code).toBe("otp_invalid");
    }
  });
});

describe("TwilioVerifyProvider", () => {
  let store: MemoryKvStore;
  beforeEach(() => {
    store = new MemoryKvStore();
  });

  it("send creates a verification, persists purpose, returns lifecycle params (no mockCode)", async () => {
    const { api, calls } = makeApi({});
    const provider = new TwilioVerifyProvider(api, store, CFG);
    const res = await provider.send(PHONE, "REGISTRATION");
    expect(calls.verifications).toBe(1);
    expect(res.ttlSeconds).toBe(600);
    expect(res.maxAttempts).toBe(5);
    expect(res).not.toHaveProperty("mockCode");
  });

  it("verify approved → returns the stored purpose and clears the record (single-use)", async () => {
    const { api } = makeApi({ verifyResult: { status: "approved" } });
    const provider = new TwilioVerifyProvider(api, store, CFG);
    await provider.send(PHONE, "LOGIN");
    const out = await provider.verify(PHONE, "123456");
    expect(out.purpose).toBe("LOGIN");
    // record cleared — a second verify has no live side record → otp_expired
    await expect(provider.verify(PHONE, "123456")).rejects.toMatchObject({
      code: "otp_expired",
    });
  });

  it("verify with no prior send → otp_expired (410)", async () => {
    const { api, calls } = makeApi({ verifyResult: { status: "approved" } });
    const provider = new TwilioVerifyProvider(api, store, CFG);
    await expect(provider.verify(PHONE, "123456")).rejects.toMatchObject({
      code: "otp_expired",
    });
    expect(calls.checks).toBe(0); // short-circuits before calling Twilio
  });

  it("verify pending (wrong code) → otp_invalid, record retained", async () => {
    const { api } = makeApi({ verifyResult: { status: "pending" } });
    const provider = new TwilioVerifyProvider(api, store, CFG);
    await provider.send(PHONE, "REGISTRATION");
    await expect(provider.verify(PHONE, "000000")).rejects.toMatchObject({
      code: "otp_invalid",
    });
  });

  it("resend creates a new verification and decrements resendsRemaining", async () => {
    const { api, calls } = makeApi({});
    const provider = new TwilioVerifyProvider(api, store, CFG);
    await provider.send(PHONE, "REGISTRATION");
    const r1 = await provider.resend(PHONE, "REGISTRATION");
    expect(r1.resendsRemaining).toBe(2);
    const r2 = await provider.resend(PHONE, "REGISTRATION");
    expect(r2.resendsRemaining).toBe(1);
    expect(calls.verifications).toBe(3); // 1 send + 2 resends
  });
});
