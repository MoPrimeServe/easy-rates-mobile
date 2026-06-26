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

// Runtime wiring
export { createAuthCoreRuntime } from "./runtime.js";
export type { AuthCoreRuntime, StoreBackend } from "./runtime.js";

// Validation helper
export { parseOrValidationError } from "./zod-validate.js";
