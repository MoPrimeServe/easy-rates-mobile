// otp_service.dart — client for the public otp-service routes (api/otp-service.md).
//
//   POST /otp/verify { phone, code }          → OtpVerifyResult  (branch on error.code)
//   POST /otp/resend { phone, purpose }       → OtpResendResult
//
// /otp/send is [internal] and NOT here — the client initiates via auth-service (ADR-002).
// Wired to the live backend via the shared ApiClient, which unwraps the `{ data, error }`
// envelope (conventions §2). verify/resend NEVER switch on the HTTP status — they branch on
// the `data` shape (success) or `error.code` (failure). Set `useMockServices = true` for
// offline dev (preserved stub behaviour below).

import '../api/api_client.dart';
import '../api/services.dart';
import 'auth_service.dart';

/// Outcome of POST /otp/verify. The server infers purpose from Redis context (the request
/// is only { phone, code }); the success branch is chosen from the response shape
/// (registrationToken present ⇒ REGISTRATION; token pair present ⇒ LOGIN), with `purpose`
/// as the tiebreaker for the mock. Modelled as a sealed type so the screen must handle
/// every case.
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
  OtpService({ApiClient? client}) : _client = client ?? sharedApiClient;

  final ApiClient _client;

  /// POST /otp/verify { phone, code } — branch on `error.code`, never the HTTP status.
  /// Success `data` shape decides the variant: a `registrationToken` ⇒ REGISTRATION;
  /// an `accessToken` pair ⇒ LOGIN. On error: otp_invalid → OtpInvalid (attemptsRemaining,
  /// maxAttempts), otp_expired → OtpExpired, max_attempts_exceeded → OtpMaxAttemptsExceeded.
  Future<OtpVerifyResult> verify({
    required String phone,
    required String code,
    required OtpPurpose purpose, // mock-only: real server infers from Redis context
  }) async {
    if (useMockServices) {
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

    final Map<String, dynamic> data;
    try {
      data = await _client.post(
        '/otp/verify',
        body: {'phone': phone, 'code': code},
        authenticated: false, // [public]
      );
    } on ApiException catch (e) {
      return _verifyError(e);
    }
    return parseVerifySuccess(data);
  }

  /// POST /otp/resend { phone, purpose } — supersedes the prior code server-side.
  /// 202 → OtpResendOk; resend_cooldown_active (429) → OtpResendCooldown(retryAfterSeconds).
  Future<OtpResendResult> resend({
    required String phone,
    required OtpPurpose purpose,
  }) async {
    if (useMockServices) {
      await Future.delayed(const Duration(milliseconds: 600));
      return const OtpResendOk(
          ttlSeconds: 600, resendCooldownSeconds: 30, resendsRemaining: 2);
    }

    final Map<String, dynamic> data;
    try {
      data = await _client.post(
        '/otp/resend',
        body: {'phone': phone, 'purpose': _wirePurpose(purpose)},
        authenticated: false, // [public]
      );
    } on ApiException catch (e) {
      if (e.code == 'resend_cooldown_active') {
        return OtpResendCooldown(_int(e.details['retryAfterSeconds']));
      }
      rethrow; // validation_error / rate_limit_exceeded etc. bubble to the screen
    }
    return OtpResendOk(
      ttlSeconds: _int(data['ttlSeconds']),
      resendCooldownSeconds: _int(data['resendCooldownSeconds']),
      resendsRemaining: _int(data['resendsRemaining']),
    );
  }

  /// Map a successful /otp/verify `data` object to the right variant. Exposed for the
  /// envelope/mapping unit test. REGISTRATION carries `registrationToken`; LOGIN carries
  /// the full token pair (`accessToken`, `refreshToken`, …).
  OtpVerifyResult parseVerifySuccess(Map<String, dynamic> data) {
    if (data.containsKey('registrationToken')) {
      return OtpVerifyRegistration(data['registrationToken'] as String);
    }
    final tokens = AuthTokens.fromJson(data);
    // Persist the LOGIN session pair via the shared token store.
    _client.tokenStore.saveTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    return OtpVerifyLogin(tokens);
  }

  /// Map a /otp/verify `error.code` to the right variant. Exposed for the unit test.
  OtpVerifyResult _verifyError(ApiException e) {
    switch (e.code) {
      case 'otp_invalid':
        return OtpInvalid(
          attemptsRemaining: _int(e.details['attemptsRemaining']),
          maxAttempts: _int(e.details['maxAttempts']),
        );
      case 'otp_expired':
        return const OtpExpired();
      case 'max_attempts_exceeded':
        return OtpMaxAttemptsExceeded(_int(e.details['maxAttempts']));
      default:
        // validation_error / rate_limit_exceeded / unauthenticated — let the screen
        // handle a generic failure; rethrow keeps the contract honest.
        throw e;
    }
  }

  String _wirePurpose(OtpPurpose p) =>
      p == OtpPurpose.login ? 'LOGIN' : 'REGISTRATION';

  static int _int(Object? v) => (v as num).toInt();
}
