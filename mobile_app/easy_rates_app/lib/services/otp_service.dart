// otp_service.dart — client for the public otp-service routes (api/otp-service.md).
//
//   POST /otp/verify { phone, code }          → OtpVerifyResult  (branch on error.code)
//   POST /otp/resend { phone, purpose }       → OtpResendResult
//
// /otp/send is [internal] and NOT here — the client initiates via auth-service (ADR-002).
// STUB: no HTTP client wired yet; bodies simulate the round-trip and return canned data.

import 'auth_service.dart';

/// Outcome of POST /otp/verify. The server infers purpose from Redis context (the request
/// is only { phone, code }); the stub takes purpose to choose the success branch. Modelled
/// as a sealed type so the screen must handle every case.
sealed class OtpVerifyResult {
  const OtpVerifyResult();
}

/// approved REGISTRATION — single-use token consumed by POST /auth/register (no session yet).
class OtpVerifyRegistration extends OtpVerifyResult {
  final String registrationToken;
  const OtpVerifyRegistration(this.registrationToken);
}

/// approved LOGIN — the session token pair.
class OtpVerifyLogin extends OtpVerifyResult {
  final AuthTokens tokens;
  const OtpVerifyLogin(this.tokens);
}

/// otp_invalid (422) — wrong code, still live. Stay on screen, show attempts remaining.
class OtpInvalid extends OtpVerifyResult {
  final int attemptsRemaining;
  final int maxAttempts;
  const OtpInvalid({required this.attemptsRemaining, required this.maxAttempts});
}

/// otp_expired (410) — TTL elapsed. Route to the Resend destination.
class OtpExpired extends OtpVerifyResult {
  const OtpExpired();
}

/// max_attempts_exceeded (429) — too many wrong codes. Same destination as expired, but the
/// distinct code lets the screen render "too many attempts" copy instead of "expired".
class OtpMaxAttemptsExceeded extends OtpVerifyResult {
  final int maxAttempts;
  const OtpMaxAttemptsExceeded(this.maxAttempts);
}

/// Outcome of POST /otp/resend.
sealed class OtpResendResult {
  const OtpResendResult();
}

/// 202 — a fresh code was sent. When [resendsRemaining] reaches 0 the screen swaps the
/// Resend button for a support-contact CTA (otp-service resolves this without a 5th code).
class OtpResendOk extends OtpResendResult {
  final int ttlSeconds; // the new code's TTL — reset the expiry countdown from this
  final int resendCooldownSeconds;
  final int resendsRemaining;
  const OtpResendOk({
    required this.ttlSeconds,
    required this.resendCooldownSeconds,
    required this.resendsRemaining,
  });
}

/// resend_cooldown_active (429) — still inside the cooldown; [retryAfterSeconds] remaining.
class OtpResendCooldown extends OtpResendResult {
  final int retryAfterSeconds;
  const OtpResendCooldown(this.retryAfterSeconds);
}

class OtpService {
  /// POST /otp/verify { phone, code } — branch on error.code, never the HTTP status.
  Future<OtpVerifyResult> verify({
    required String phone,
    required String code,
    required OtpPurpose purpose, // stub-only: real server infers from Redis context
  }) async {
    // TODO: real POST /otp/verify; map 410/422/429 error.code to the variants below.
    await Future.delayed(const Duration(milliseconds: 600));
    if (code == '123456') {
      return purpose == OtpPurpose.login
          ? const OtpVerifyLogin(
              AuthTokens(
                userId: 'stub-user',
                accessToken: 'stub-access',
                refreshToken: 'stub-refresh',
                accessTokenExpiresInSeconds: 900,
                refreshTokenTtlDays: 30,
              ),
            )
          : const OtpVerifyRegistration('stub-registration-token');
    }
    return const OtpInvalid(attemptsRemaining: 4, maxAttempts: 5);
  }

  /// POST /otp/resend { phone, purpose } — supersedes the prior code server-side.
  Future<OtpResendResult> resend({
    required String phone,
    required OtpPurpose purpose,
  }) async {
    // TODO: real POST /otp/resend; 429 resend_cooldown_active → OtpResendCooldown.
    await Future.delayed(const Duration(milliseconds: 600));
    return const OtpResendOk(ttlSeconds: 600, resendCooldownSeconds: 30, resendsRemaining: 2);
  }
}
