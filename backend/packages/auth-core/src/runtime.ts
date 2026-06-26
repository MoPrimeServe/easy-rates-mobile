import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { env } from "@easyrates/config";
import type { KvStore } from "./store.js";
import { MemoryKvStore } from "./store.js";
import { RedisKvStore, getRedis, pingRedis } from "./redis-store.js";
import { OtpStateMachine } from "./otp-state.js";
import { RegistrationTokenService, TokenService } from "./tokens.js";

/**
 * Wires env → KvStore → services. Resolves the OTP/session state store once:
 * Redis if reachable (the authoritative phone-keyed store the otp-service
 * contract describes), else an in-process MemoryKvStore fallback (single
 * process only — logged loudly so the operator knows state is not shared).
 */

function loadPem(inline: string | undefined, path: string): string {
  if (inline && inline.trim().length > 0) return inline;
  return readFileSync(resolve(process.cwd(), path), "utf8");
}

export type StoreBackend = "redis" | "memory";

export interface AuthCoreRuntime {
  store: KvStore;
  storeBackend: StoreBackend;
  otp: OtpStateMachine;
  tokens: TokenService;
  registrationTokens: RegistrationTokenService;
}

let cached: AuthCoreRuntime | null = null;

export async function createAuthCoreRuntime(): Promise<AuthCoreRuntime> {
  if (cached) return cached;

  let store: KvStore;
  let storeBackend: StoreBackend;

  const redis = getRedis(env.REDIS_URL);
  if (redis && (await pingRedis(redis))) {
    store = new RedisKvStore(redis);
    storeBackend = "redis";
    console.log("[auth-core] OTP/session store: Redis (authoritative).");
  } else {
    store = new MemoryKvStore();
    storeBackend = "memory";
    console.warn(
      "[auth-core] OTP/session store: in-process MemoryKvStore (Redis " +
        "unreachable). State is NOT shared across processes — dev fallback only.",
    );
  }

  const otp = new OtpStateMachine(store, {
    ttlSeconds: env.OTP_TTL_SECONDS,
    resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
    maxResends: env.OTP_MAX_RESENDS_PER_SESSION,
    maxAttempts: env.OTP_MAX_INVALID_ATTEMPTS,
    codePepper: env.ID_NUMBER_HMAC_PEPPER, // reuse the keyed pepper for code hashing
    mock: env.OTP_MOCK,
  });

  const tokens = new TokenService(store, {
    privateKeyPem: loadPem(env.JWT_PRIVATE_KEY_PEM, env.JWT_PRIVATE_KEY_PEM_PATH),
    publicKeyPem: loadPem(env.JWT_PUBLIC_KEY_PEM, env.JWT_PUBLIC_KEY_PEM_PATH),
    issuer: env.JWT_ISSUER,
    audience: env.JWT_AUDIENCE,
    accessTtlSeconds: env.JWT_ACCESS_TTL_SECONDS,
    refreshTtlDays: env.JWT_REFRESH_TTL_DAYS,
  });

  const registrationTokens = new RegistrationTokenService(
    store,
    env.REGISTRATION_TOKEN_TTL_SECONDS,
  );

  cached = { store, storeBackend, otp, tokens, registrationTokens };
  return cached;
}
