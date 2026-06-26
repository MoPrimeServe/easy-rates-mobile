/**
 * KvStore — the minimal key/value contract the OTP state machine and the
 * refresh-token store depend on. Two implementations exist:
 *
 *  - RedisKvStore  — backed by ioredis; used when REDIS_URL resolves (Redis is
 *    the authoritative OTP / session state store, keyed by phone — this is the
 *    design the otp-service contract documents: `otp:${phone}` context with a
 *    server-owned TTL, attempt counter, and resend cooldown).
 *  - MemoryKvStore — an in-process Map with TTL; the default for unit tests and
 *    a graceful fallback when Redis is absent (single-process only).
 *
 * Why not the `OTPAttempt` Prisma table as the source of truth? Registration is
 * OTP-first (ADR-002): no `User` row exists when the REGISTRATION code is sent,
 * but `OTPAttempt.userId` is a NOT-NULL FK to `User`. A phone-keyed store is the
 * only design that serves passwordless OTP-first registration against the live
 * schema. The `OTPAttempt` table is used as a best-effort LOGIN audit mirror by
 * the otp-service when a `User` exists; Redis remains authoritative.
 */
export interface KvStore {
  get(key: string): Promise<string | null>;
  /** Set `key=value` with a TTL in seconds (overwrites). */
  set(key: string, value: string, ttlSeconds: number): Promise<void>;
  del(key: string): Promise<void>;
  /** Remaining TTL in seconds: >0 live, -2 missing, -1 no-expiry. */
  ttl(key: string): Promise<number>;
  /** A monotonic-ish wall clock in ms; injectable so tests control time. */
  now(): number;
}

interface MemoryEntry {
  value: string;
  expiresAtMs: number; // absolute ms; Infinity = no expiry
}

/** In-process TTL map. Single-process only. Test/fallback store. */
export class MemoryKvStore implements KvStore {
  private readonly map = new Map<string, MemoryEntry>();
  private clock: () => number;

  constructor(clock?: () => number) {
    this.clock = clock ?? (() => Date.now());
  }

  /** Test helper: replace the clock to simulate time passing. */
  setClock(clock: () => number): void {
    this.clock = clock;
  }

  now(): number {
    return this.clock();
  }

  private live(key: string): MemoryEntry | null {
    const e = this.map.get(key);
    if (!e) return null;
    if (e.expiresAtMs <= this.now()) {
      this.map.delete(key);
      return null;
    }
    return e;
  }

  async get(key: string): Promise<string | null> {
    return this.live(key)?.value ?? null;
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    this.map.set(key, {
      value,
      expiresAtMs: this.now() + ttlSeconds * 1000,
    });
  }

  async del(key: string): Promise<void> {
    this.map.delete(key);
  }

  async ttl(key: string): Promise<number> {
    const e = this.map.get(key);
    if (!e) return -2;
    const remainingMs = e.expiresAtMs - this.now();
    if (remainingMs <= 0) {
      this.map.delete(key);
      return -2;
    }
    return Math.ceil(remainingMs / 1000);
  }
}
