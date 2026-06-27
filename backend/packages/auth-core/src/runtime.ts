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
import {
  AzureKeyVaultKeyProvider,
  EnvKeyProvider,
  type Jwks,
  type KeyProvider,
} from "./key-provider.js";

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
  /** The signing-key boundary (env-backed today; Azure Key Vault stubbed). */
  keyProvider: KeyProvider;
  /** The published JWK set — served at `GET /.well-known/jwks.json`. */
  jwks: Jwks;
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

  const privateKeyPem = loadPem(
    env.JWT_PRIVATE_KEY_PEM,
    env.JWT_PRIVATE_KEY_PEM_PATH,
  );
  const publicKeyPem = loadPem(
    env.JWT_PUBLIC_KEY_PEM,
    env.JWT_PUBLIC_KEY_PEM_PATH,
  );

  // Signing-key boundary. `env` loads the RS256 PEMs; `azure-key-vault` is a
  // marked stub that throws (needs provisioned infra — see key-provider.ts).
  const keyProvider: KeyProvider =
    env.JWT_KEY_PROVIDER === "azure-key-vault"
      ? new AzureKeyVaultKeyProvider()
      : new EnvKeyProvider(privateKeyPem, publicKeyPem, env.JWT_SIGNING_KEY_ID);
  const signingKey = keyProvider.getSigningKey();

  const tokens = new TokenService(store, {
    privateKeyPem: signingKey.privateKeyPem,
    publicKeyPem,
    issuer: env.JWT_ISSUER,
    audience: env.JWT_AUDIENCE,
    accessTtlSeconds: env.JWT_ACCESS_TTL_SECONDS,
    refreshTtlDays: env.JWT_REFRESH_TTL_DAYS,
    keyId: signingKey.kid,
  });

  const registrationTokens = new RegistrationTokenService(
    store,
    env.REGISTRATION_TOKEN_TTL_SECONDS,
  );

  cached = {
    store,
    storeBackend,
    otp,
    otpDriver,
    tokens,
    registrationTokens,
    keyProvider,
    jwks: keyProvider.getPublicJwks(),
  };
  return cached;
}
