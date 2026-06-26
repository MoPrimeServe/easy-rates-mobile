import { Redis } from "ioredis";
import type { KvStore } from "./store.js";

/**
 * Redis-backed KvStore. Used in dev/prod when REDIS_URL resolves. Wraps a shared
 * ioredis connection. TTLs are enforced by Redis itself (EX), so `otp_expired`
 * is detected by a missing key — exactly the otp-service contract's design.
 */
export class RedisKvStore implements KvStore {
  constructor(private readonly client: Redis) {}

  now(): number {
    return Date.now();
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.client.set(key, value, "EX", ttlSeconds);
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  async ttl(key: string): Promise<number> {
    return this.client.ttl(key);
  }
}

let shared: Redis | null = null;

/**
 * Lazily open (or reuse) a single ioredis connection. Returns null if no
 * REDIS_URL is configured, so callers can fall back to MemoryKvStore.
 */
export function getRedis(redisUrl: string | undefined): Redis | null {
  if (!redisUrl) return null;
  if (shared) return shared;
  shared = new Redis(redisUrl, {
    maxRetriesPerRequest: 2,
    lazyConnect: false,
  });
  // Avoid an unhandled 'error' event crashing the process if Redis blips.
  shared.on("error", (err: Error) => {
    console.error("[redis] connection error:", err.message);
  });
  return shared;
}

export async function pingRedis(client: Redis): Promise<boolean> {
  try {
    const res = await client.ping();
    return res === "PONG";
  } catch {
    return false;
  }
}
