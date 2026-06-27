// Stores
export type { KvStore } from "./store.js";
export { MemoryKvStore } from "./store.js";
export { RedisKvStore, getRedis, pingRedis } from "./redis-store.js";

// OTP state machine
export {
  OtpStateMachine,
  generateCode,
} from "./otp-state.js";
export type {
  OtpPurpose,
  OtpConfig,
  SendResult,
  ResendResult,
} from "./otp-state.js";
export {
  otpInvalid,
  otpExpired,
  maxAttemptsExceeded,
  resendCooldownActive,
} from "./otp-errors.js";

// Tokens
export { TokenService, RegistrationTokenService } from "./tokens.js";
export type {
  TokenConfig,
  TokenService as TokenServiceType,
  AccessClaims,
  AuthTokenPair,
} from "./tokens.js";

// Identity helpers
export {
  PHONE_REGEX,
  phoneSchema,
  idNumberSchema,
  maskPhone,
  isValidSaId,
  hashIdNumber,
} from "./identity.js";

// OTP delivery providers (swappable boundary)
export { MockOtpProvider } from "./otp-provider.js";
export type { OtpProvider } from "./otp-provider.js";
export {
  TwilioVerifyProvider,
  mapVerifyOutcome,
} from "./twilio-verify.js";
export type {
  TwilioVerifyApi,
  TwilioVerifyConfig,
  TwilioLikeError,
} from "./twilio-verify.js";
export {
  createTwilioVerifyApi,
  fetchVerifyService,
} from "./twilio-client.js";
export type { TwilioCreds } from "./twilio-client.js";

// Signing-key boundary (KeyProvider) + JWKS
export {
  EnvKeyProvider,
  AzureKeyVaultKeyProvider,
  publicPemToJwk,
} from "./key-provider.js";
export type {
  KeyProvider,
  SigningKey,
  PublicJwk,
  Jwks,
} from "./key-provider.js";

// Runtime wiring
export { createAuthCoreRuntime } from "./runtime.js";
export type { AuthCoreRuntime, StoreBackend, OtpDriver } from "./runtime.js";

// Validation helper
export { parseOrValidationError } from "./zod-validate.js";

// Shared RS256 bearer-auth middleware (promoted from apps/auth — reused by
// property/bill/account services).
export { requireAuth } from "./auth-middleware.js";
export type { AuthedRequest } from "./auth-middleware.js";
