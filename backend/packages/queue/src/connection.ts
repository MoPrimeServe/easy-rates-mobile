import { Redis } from "ioredis";
import { env } from "@easyrates/config";

/**
 * Dedicated BullMQ Redis connection.
 *
 * BullMQ requires `maxRetriesPerRequest: null` on its ioredis connection (it
 * manages its own blocking commands), so it cannot share auth-core's shared
 * connection (which sets `maxRetriesPerRequest: 2`). We open ONE connection here
 * and reuse it across every Queue/Worker in this package.
 *
 * Graceful-if-down: if REDIS_URL is unset, `getQueueConnection()` returns null
 * and the producers/health probe report the queue as unavailable rather than
 * throwing. With a URL set but Redis unreachable, BullMQ retries in the
 * background; an `error` listener keeps a blip from crashing the process.
 */
let shared: Redis | null = null;

export function getQueueConnection(): Redis | null {
  if (!env.REDIS_URL) return null;
  if (shared) return shared;
  shared = new Redis(env.REDIS_URL, {
    maxRetriesPerRequest: null, // required by BullMQ
    enableReadyCheck: false,
  });
  shared.on("error", (err: Error) => {
    console.error("[queue] redis connection error:", err.message);
  });
  return shared;
}

/** True when Redis answers PING. Used by the shared /health queue probe. */
export async function pingQueue(): Promise<boolean> {
  const conn = getQueueConnection();
  if (!conn) return false;
  try {
    const res = await conn.ping();
    return res === "PONG";
  } catch {
    return false;
  }
}

/** Close the shared connection (graceful shutdown / test teardown). */
export async function closeQueueConnection(): Promise<void> {
  if (shared) {
    await shared.quit().catch(() => undefined);
    shared = null;
  }
}
