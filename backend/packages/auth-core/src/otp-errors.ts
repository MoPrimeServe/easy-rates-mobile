import { ApiError } from "@easyrates/http";

/**
 * OTP-specific error codes (otp-service contract). These are NOT in the
 * conventions §3 standard set — they are service-specific and carry their own
 * HTTP status + `details` shape (verbatim from the contract). `error.code` stays
 * snake_case; `details` keys are camelCase (conventions §10).
 */

/** 422 otp_invalid — wrong code; details.attemptsRemaining + maxAttempts. */
export function otpInvalid(
  attemptsRemaining: number,
  maxAttempts: number,
): ApiError {
  return new ApiError(
    "otp_invalid",
    422,
    "Incorrect code. Please try again.",
    { attemptsRemaining, maxAttempts },
  );
}

/** 410 otp_expired — code expired/superseded; details.ttlSeconds = 0. */
export function otpExpired(): ApiError {
  return new ApiError(
    "otp_expired",
    410,
    "Your verification code has expired. Please request a new one.",
    { ttlSeconds: 0 },
  );
}

/** 429 max_attempts_exceeded — too many wrong codes; details.maxAttempts. NO account lockout (ADR-002). */
export function maxAttemptsExceeded(maxAttempts: number): ApiError {
  return new ApiError(
    "max_attempts_exceeded",
    429,
    "Too many incorrect attempts. Please request a new code.",
    { maxAttempts },
  );
}

/** 429 resend_cooldown_active — resend too soon; details.retryAfterSeconds (remaining). */
export function resendCooldownActive(retryAfterSeconds: number): ApiError {
  return new ApiError(
    "resend_cooldown_active",
    429,
    "Please wait before requesting another code.",
    { retryAfterSeconds },
  );
}
