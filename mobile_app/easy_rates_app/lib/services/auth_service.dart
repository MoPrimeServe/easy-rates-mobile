// auth_service.dart — client for the public auth-service front door (api/auth-service.md).
//
// Passwordless, OTP-first (ADR-002). The Flutter client NEVER calls /otp/send — it stays
// [internal]. The client calls auth-service to initiate; auth-service dispatches the OTP
// server-to-server. The lifecycle params + masked phone the Verify OTP screen needs are
// surfaced here:
//
//   POST /auth/register/start { phone } → 202 { ttlSeconds, resendCooldownSeconds, maskedPhone }
//   POST /auth/login          { phone } → 200 { message, ttlSeconds, resendCooldownSeconds, maskedPhone }
//
// STUB: no HTTP client is wired yet (pubspec has none). Replace the bodies with real
// requests once the backend is live; the public types are the contract the UI depends on.

/// REGISTRATION starts onboarding; LOGIN signs a returning user in. (ADR-002 dropped
/// PASSWORD_RESET.) The server infers purpose from Redis context at verify time; the
/// client tracks it to route the verified result.
enum OtpPurpose { registration, login }

/// Lifecycle params + masked phone for the Verify OTP screen, returned by the public
/// auth-initiate endpoints. The client hardcodes none of them.
class OtpInit {
  final int ttlSeconds; // OTP expiry window
  final int resendCooldownSeconds; // initial resend cooldown
  final String maskedPhone; // e.g. "+27****1234" — for display

  const OtpInit({
    required this.ttlSeconds,
    required this.resendCooldownSeconds,
    required this.maskedPhone,
  });
}

/// Registration fields collected on the Sign Up screen and held until OTP verify
/// succeeds. POST /auth/register consumes them with the registrationToken to create the
/// User and mint the session (ADR-002 — OTP-first; the User exists only after this call).
/// Proof-of-address is NOT here — it uploads later via POST /auth/kyc.
class RegisterDraft {
  final String phone; // E.164 +27; must match the verified registrationToken
  final String displayName;
  final String? email;
  final String idNumber; // 13-digit SA ID, Luhn-valid

  const RegisterDraft({
    required this.phone,
    required this.displayName,
    this.email,
    required this.idNumber,
  });
}

/// Session token pair (AuthTokenResponse) — issued by POST /auth/register and
/// POST /otp/verify (LOGIN).
class AuthTokens {
  final String userId;
  final String accessToken; // RS256 JWT, in-memory only
  final String refreshToken; // opaque 256-bit hex, secure storage
  final int accessTokenExpiresInSeconds; // 900
  final int refreshTokenTtlDays; // 30

  const AuthTokens({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresInSeconds,
    required this.refreshTokenTtlDays,
  });
}

class AuthService {
  /// POST /auth/register/start { phone } — dispatches a REGISTRATION OTP.
  Future<OtpInit> registerStart(String phone) async {
    // TODO: real POST /auth/register/start; 409 conflict if phone already registered.
    await Future.delayed(const Duration(milliseconds: 600));
    return OtpInit(
      ttlSeconds: 600,
      resendCooldownSeconds: 30,
      maskedPhone: _mask(phone),
    );
  }

  /// POST /auth/login { phone } — anti-enumeration: always 200, OTP sent only if registered.
  Future<OtpInit> login(String phone) async {
    // TODO: real POST /auth/login; body is byte-identical whether or not phone is registered.
    await Future.delayed(const Duration(milliseconds: 600));
    return OtpInit(
      ttlSeconds: 600,
      resendCooldownSeconds: 30,
      maskedPhone: _mask(phone),
    );
  }

  /// POST /auth/register { phone, displayName, email?, idNumber, registrationToken }
  /// → 201 AuthTokens. Runs after a successful REGISTRATION OTP verify.
  Future<AuthTokens> register(RegisterDraft draft, String registrationToken) async {
    // TODO: real POST /auth/register; 401 if registrationToken invalid/expired/used.
    await Future.delayed(const Duration(milliseconds: 600));
    return const AuthTokens(
      userId: 'stub-user',
      accessToken: 'stub-access',
      refreshToken: 'stub-refresh',
      accessTokenExpiresInSeconds: 900,
      refreshTokenTtlDays: 30,
    );
  }

  // Stub-only masking; the real maskedPhone comes from the server.
  String _mask(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return '+27****';
    return '+27****${digits.substring(digits.length - 4)}';
  }
}
