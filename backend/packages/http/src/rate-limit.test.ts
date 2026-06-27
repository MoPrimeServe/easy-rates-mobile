import { describe, it, expect, beforeEach } from "vitest";
import type { NextFunction, Request, Response } from "express";
import { ApiError } from "./api-error.js";
import {
  rateLimit,
  computeHeaders,
  RATE_LIMIT_RULES,
  MemoryCounterStore,
} from "./rate-limit.js";

describe("computeHeaders", () => {
  const rule = RATE_LIMIT_RULES["OTP-SEND"]; // limit 3

  it("counts down remaining and is not exceeded up to the limit", () => {
    expect(computeHeaders(rule, 1, 600)).toEqual({ remaining: 2, exceeded: false, retryAfter: 600 });
    expect(computeHeaders(rule, 3, 540)).toEqual({ remaining: 0, exceeded: false, retryAfter: 540 });
  });

  it("marks exceeded once count passes the limit, remaining clamped at 0", () => {
    const h = computeHeaders(rule, 4, 500);
    expect(h.exceeded).toBe(true);
    expect(h.remaining).toBe(0);
    expect(h.retryAfter).toBe(500);
  });
});

describe("RATE_LIMIT_RULES (conventions §5)", () => {
  it("matches the specified category limits/windows/dimensions", () => {
    expect(RATE_LIMIT_RULES["OTP-SEND"]).toMatchObject({ limit: 3, windowSeconds: 600, dimension: "phone" });
    expect(RATE_LIMIT_RULES["OTP-VERIFY"]).toMatchObject({ limit: 10, windowSeconds: 600, dimension: "phone" });
    expect(RATE_LIMIT_RULES.AUTH).toMatchObject({ limit: 10, windowSeconds: 900, dimension: "ip" });
    expect(RATE_LIMIT_RULES.READ).toMatchObject({ limit: 60, windowSeconds: 60, dimension: "user" });
    expect(RATE_LIMIT_RULES.WRITE).toMatchObject({ limit: 20, windowSeconds: 3600, dimension: "user" });
    expect(RATE_LIMIT_RULES.SUBMIT).toMatchObject({ limit: 5, windowSeconds: 86400, dimension: "user" });
  });
});

// ---- middleware behaviour with an injected in-memory counter ----------------

interface FakeRes {
  headers: Record<string, string>;
  setHeader(k: string, v: string): void;
}

function makeRes(): FakeRes & Response {
  const headers: Record<string, string> = {};
  return {
    headers,
    setHeader(k: string, v: string) {
      headers[k] = v;
    },
  } as unknown as FakeRes & Response;
}

function runOnce(
  mw: (req: Request, res: Response, next: NextFunction) => Promise<void>,
  req: Partial<Request> & { userId?: string },
): Promise<{ res: FakeRes & Response; err: unknown }> {
  const res = makeRes();
  return new Promise((resolve) => {
    void mw(req as Request, res, (err?: unknown) => resolve({ res, err }));
  });
}

describe("rateLimit middleware (MemoryCounterStore)", () => {
  let store: MemoryCounterStore;
  beforeEach(() => {
    store = new MemoryCounterStore();
  });

  it("emits standard headers and allows up to the limit, then 429 with Retry-After", async () => {
    const mw = rateLimit("OTP-SEND", { store }); // limit 3, phone-keyed
    const req = { body: { phone: "+27820000000" } } as Partial<Request>;

    const r1 = await runOnce(mw, req);
    expect(r1.err).toBeUndefined();
    expect(r1.res.headers["RateLimit-Limit"]).toBe("3");
    expect(r1.res.headers["RateLimit-Remaining"]).toBe("2");
    expect(r1.res.headers["RateLimit-Reset"]).toBeDefined();

    await runOnce(mw, req); // 2
    const r3 = await runOnce(mw, req); // 3 — still allowed, remaining 0
    expect(r3.err).toBeUndefined();
    expect(r3.res.headers["RateLimit-Remaining"]).toBe("0");

    const r4 = await runOnce(mw, req); // 4 — exceeded
    expect(r4.err).toBeInstanceOf(ApiError);
    expect((r4.err as ApiError).code).toBe("otp_send_rate_limited");
    expect((r4.err as ApiError).httpStatus).toBe(429);
    expect(r4.res.headers["Retry-After"]).toBeDefined();
  });

  it("keys per-identity: a different phone has its own counter", async () => {
    const mw = rateLimit("OTP-SEND", { store });
    await runOnce(mw, { body: { phone: "+27820000001" } } as Partial<Request>);
    await runOnce(mw, { body: { phone: "+27820000001" } } as Partial<Request>);
    await runOnce(mw, { body: { phone: "+27820000001" } } as Partial<Request>);
    const exceeded = await runOnce(mw, { body: { phone: "+27820000001" } } as Partial<Request>);
    expect(exceeded.err).toBeInstanceOf(ApiError);
    // Fresh phone — first hit, allowed.
    const other = await runOnce(mw, { body: { phone: "+27820000002" } } as Partial<Request>);
    expect(other.err).toBeUndefined();
    expect(other.res.headers["RateLimit-Remaining"]).toBe("2");
  });

  it("skips (allows) when the keying identity is absent (e.g. user dimension, no userId)", async () => {
    const mw = rateLimit("READ", { store }); // user-keyed
    const r = await runOnce(mw, { body: {} } as Partial<Request>); // no userId
    expect(r.err).toBeUndefined();
    expect(r.res.headers["RateLimit-Limit"]).toBeUndefined(); // not even counted
  });

  it("AUTH category keys on req.ip", async () => {
    const mw = rateLimit("AUTH", { store }); // limit 10, ip-keyed
    const req = { ip: "10.0.0.5", body: {} } as Partial<Request>;
    const r = await runOnce(mw, req);
    expect(r.err).toBeUndefined();
    expect(r.res.headers["RateLimit-Limit"]).toBe("10");
    expect(r.res.headers["RateLimit-Remaining"]).toBe("9");
  });
});
