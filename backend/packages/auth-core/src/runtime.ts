import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { env } from "@easyrates/config";
import type { KvStore } from "./store.js";
import { MemoryKvStore } from "./store.js";
import { RedisKvStore, getRedis, pingRedis } from "./redis-store.js";
import { OtpStateMachine } from "./otp-state.js";
import { MockOtpProvider, type OtpProvider } from "./otp-provider.js";
import { TwilioVerifyProvider } from "./twilio-verify.js";
import { createTwilioVerifyApi } from "./twilio-client.js";
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
export type OtpDriver = "mock" | "twilio";

export interface AuthCoreRuntime {
  store: KvStore;
  storeBackend: StoreBackend;
  otp: OtpProvider;
  otpDriver: OtpDriver;
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

  // OTP delivery provider selection (default-safe). OTP_MOCK=true → the
  // in-process state machine (no SMS). OTP_MOCK=false → Twilio Verify, but only
  // when the three creds are present; if any is missing we log loudly and fall
  // back to mock so a misconfigured env never hard-fails OTP.
  const otpParams = {
    ttlSeconds: env.OTP_TTL_SECONDS,
    resendCooldownSeconds: env.OTP_RESEND_COOLDOWN_SECONDS,
    maxResends: env.OTP_MAX_RESENDS_PER_SESSION,
    maxAttempts: env.OTP_MAX_INVALID_ATTEMPTS,
  };
  const twilioReady =
    Boolean(env.TWILIO_ACCOUNT_SID) &&
    Boolean(env.TWILIO_AUTH_TOKEN) &&
    Boolean(env.TWILIO_SERVICE_SID);

  let otp: OtpProvider;
  let otpDriver: OtpDriver;
  if (!env.OTP_MOCK && twilioReady) {
    const api = createTwilioVerifyApi({
      accountSid: env.TWILIO_ACCOUNT_SID!,
      authToken: env.TWILIO_AUTH_TOKEN!,
      serviceSid: env.TWILIO_SERVICE_SID!,
    });
    otp = new TwilioVerifyProvider(api, store, otpParams);
    otpDriver = "twilio";
    console.log("[auth-core] OTP delivery: Twilio Verify (real SMS).");
  } else {
    if (!env.OTP_MOCK && !twilioReady) {
      console.warn(
        "[auth-core] OTP_MOCK=false but Twilio creds are incomplete — " +
          "falling back to the mock OTP provider (no SMS).",
      );
    }
    const machine = new OtpStateMachine(store, {
      ...otpParams,
      codePepper: env.ID_NUMBER_HMAC_PEPPER, // reuse the keyed pepper for code hashing
      mock: true,
    });
    otp = new MockOtpProvider(machine);
    otpDriver = "mock";
  }

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

  cached = { store, storeBackend, otp, otpDriver, tokens, registrationTokens };
  return cached;
}
