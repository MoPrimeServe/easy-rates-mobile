import type { NextFunction, Request, Response } from "express";
import { Redis } from "ioredis";
import { env } from "@easyrates/config";
import { ApiError } from "./api-error.js";

/**
 * Redis-backed rate limiter (conventions §5). A fixed-window counter keyed per
 * category + identity. On every request it emits the standard headers
 * (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`) and, when
 * exhausted, `Retry-After` + a `429 rate_limit_exceeded` envelope.
 *
 * Categories (limit / window / key dimension):
 *   OTP-SEND     3  / 10 min  / phone   → otp-specific `otp_send_rate_limited`
 *   OTP-VERIFY  10  / 10 min  / phone   → otp-specific `otp_verify_rate_limited`
 *   AUTH        10  / 15 min  / IP
 *   READ        60  / 1 min   / user
 *   WRITE       20  / 1 hour  / user
 *   SUBMIT       5  / 24 hour / user
 *
 * Default-safe: if RATE_LIMIT_ENABLED=false the middleware is a pass-through; if
 * Redis is unavailable it FAILS OPEN (logs once, allows the request) so a Redis
 * blip never takes the API down.
 */

export type RateLimitCategory =
  | "OTP-SEND"
  | "OTP-VERIFY"
  | "AUTH"
  | "READ"
  | "WRITE"
  | "SUBMIT";

export interface RateLimitRule {
  limit: number;
  windowSeconds: number;
  /** Where the identity comes from. */
  dimension: "phone" | "ip" | "user";
  /** Error code emitted on 429 (OTP categories override the generic code). */
  code: string;
}

export const RATE_LIMIT_RULES: Record<RateLimitCategory, RateLimitRule> = {
  "OTP-SEND": { limit: 3, windowSeconds: 600, dimension: "phone", code: "otp_send_rate_limited" },
  "OTP-VERIFY": { limit: 10, windowSeconds: 600, dimension: "phone", code: "otp_verify_rate_limited" },
  AUTH: { limit: 10, windowSeconds: 900, dimension: "ip", code: "rate_limit_exceeded" },
  READ: { limit: 60, windowSeconds: 60, dimension: "user", code: "rate_limit_exceeded" },
  WRITE: { limit: 20, windowSeconds: 3600, dimension: "user", code: "rate_limit_exceeded" },
  SUBMIT: { limit: 5, windowSeconds: 86400, dimension: "user", code: "rate_limit_exceeded" },
};

// ---- Counter store (Redis, with fail-open) ----------------------------------

export interface CounterStore {
  /**
   * Increment the window counter for `key`, setting the TTL on first hit.
   * Returns the new count and the seconds remaining in the window.
   */
  hit(key: string, windowSeconds: number): Promise<{ count: number; ttl: number }>;
}

let sharedRedis: Redis | null = null;
let redisDownLogged = false;

function getRateLimitRedis(): Redis | null {
  if (!env.REDIS_URL) return null;
  if (sharedRedis) return sharedRedis;
  sharedRedis = new Redis(env.REDIS_URL, {
    maxRetriesPerRequest: 1,
    enableReadyCheck: false,
    lazyConnect: false,
  });
  sharedRedis.on("error", (err: Error) => {
    if (!redisDownLogged) {
      console.error("[ratelimit] redis error (failing open):", err.message);
      redisDownLogged = true;
    }
  });
  return sharedRedis;
}

/** Redis fixed-window counter: INCR then EXPIRE on first hit; one round-trip via pipeline. */
export class RedisCounterStore implements CounterStore {
  constructor(private readonly client: Redis) {}

  async hit(key: string, windowSeconds: number): Promise<{ count: number; ttl: number }> {
    const count = await this.client.incr(key);
    if (count === 1) {
      await this.client.expire(key, windowSeconds);
      return { count, ttl: windowSeconds };
    }
    const ttl = await this.client.ttl(key);
    return { count, ttl: ttl > 0 ? ttl : windowSeconds };
  }
}

/** In-memory counter (test/fallback). Per-process; windows tracked with timestamps. */
export class MemoryCounterStore implements CounterStore {
  private windows = new Map<string, { count: number; resetAtMs: number }>();

  async hit(key: string, windowSeconds: number): Promise<{ count: number; ttl: number }> {
    const now = Date.now();
    const existing = this.windows.get(key);
    if (!existing || existing.resetAtMs <= now) {
      const resetAtMs = now + windowSeconds * 1000;
      this.windows.set(key, { count: 1, resetAtMs });
      return { count: 1, ttl: windowSeconds };
    }
    existing.count += 1;
    return { count: existing.count, ttl: Math.ceil((existing.resetAtMs - now) / 1000) };
  }
}

// ---- Identity extraction ----------------------------------------------------

interface IdentityReq extends Request {
  userId?: string;
}

function identityFor(rule: RateLimitRule, req: IdentityReq): string | null {
  switch (rule.dimension) {
    case "ip":
      return req.ip ?? req.socket?.remoteAddress ?? "unknown-ip";
    case "user":
      // No authenticated user yet (limiter mounted before auth, or anon) → skip.
      return req.userId ?? null;
    case "phone": {
      const body = (req.body ?? {}) as { phone?: unknown };
      return typeof body.phone === "string" && body.phone.length > 0
        ? body.phone
        : null;
    }
  }
}

// ---- Middleware factory -----------------------------------------------------

export interface RateLimitOptions {
  /** Override the counter store (tests inject a MemoryCounterStore). */
  store?: CounterStore;
}

/**
 * Build an Express middleware enforcing one rate-limit category. Pure header
 * math is in `computeHeaders` (unit-tested); this wires it to the store + req.
 */
export function rateLimit(
  category: RateLimitCategory,
  options: RateLimitOptions = {},
) {
  const rule = RATE_LIMIT_RULES[category];

  return async function rateLimitMiddleware(
    req: IdentityReq,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    if (!env.RATE_LIMIT_ENABLED) {
      next();
      return;
    }

    const identity = identityFor(rule, req);
    // No identity to key on (e.g. user dimension before auth) → cannot limit; allow.
    if (identity === null) {
      next();
      return;
    }

    // Resolve the store: injected → Redis → fail-open in-memory.
    let store = options.store;
    if (!store) {
      const redis = getRateLimitRedis();
      store = redis ? new RedisCounterStore(redis) : new MemoryCounterStore();
    }

    const key = `ratelimit:${category}:${identity}`;
    let count: number;
    let ttl: number;
    try {
      const hit = await store.hit(key, rule.windowSeconds);
      count = hit.count;
      ttl = hit.ttl;
    } catch (e) {
      // Fail open — a counter failure must not block the request.
      if (!redisDownLogged) {
        console.error("[ratelimit] counter failed (failing open):", (e as Error).message);
        redisDownLogged = true;
      }
      next();
      return;
    }

    const { remaining, exceeded, retryAfter } = computeHeaders(rule, count, ttl);
    res.setHeader("RateLimit-Limit", String(rule.limit));
    res.setHeader("RateLimit-Remaining", String(remaining));
    res.setHeader("RateLimit-Reset", String(ttl));

    if (exceeded) {
      res.setHeader("Retry-After", String(retryAfter));
      next(
        new ApiError(rule.code, 429, "Too many requests. Please slow down.", {
          retryAfterSeconds: retryAfter,
        }),
      );
      return;
    }
    next();
  };
}

/**
 * Pure header math for a counter hit. `remaining` is clamped at 0; `exceeded` is
 * true once `count` passes `limit`; `retryAfter` is the window seconds left.
 * Exported for unit testing without Express or Redis.
 */
export function computeHeaders(
  rule: RateLimitRule,
  count: number,
  ttl: number,
): { remaining: number; exceeded: boolean; retryAfter: number } {
  const remaining = Math.max(rule.limit - count, 0);
  const exceeded = count > rule.limit;
  return { remaining, exceeded, retryAfter: ttl };
}
