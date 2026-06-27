// auth_service.dart — client for the public auth-service front door (api/auth-service.md).
//
// Passwordless, OTP-first (ADR-002). The Flutter client NEVER calls /otp/send — it stays
// [internal]. The client calls auth-service to initiate; auth-service dispatches the OTP
// server-to-server. The lifecycle params + masked phone the Verify OTP screen needs are
// surfaced here:
//
//   POST /auth/register/start { phone } → 202 { ttlSeconds, resendCooldownSeconds, maskedPhone }
//   POST /auth/login          { phone } → 200 { message, ttlSeconds, resendCooldownSeconds, maskedPhone }
//   POST /auth/register       { ... }   → 201 AuthTokenResponse (session pair — persisted)
//   POST /auth/logout         { refreshToken } → 200 (tokens cleared)
//
// Wired to the live backend via the shared ApiClient (lib/api/api_client.dart), which
// unwraps the `{ data, error }` envelope (conventions §2) and runs the 401→refresh→retry
// flow (§6). The public types below are the contract the UI depends on — kept identical to
// the original stub. Set `useMockServices = true` (or --dart-define) for offline dev.

import '../api/api_client.dart';
import '../api/services.dart';
import '../api/token_store.dart';

/// Compile-time toggle: when true, the services return canned data with a simulated
/// delay (the original stub behaviour) instead of hitting the backend. Default false
/// (live). Override at build time: `--dart-define=USE_MOCK_SERVICES=true`.
const bool useMockServices =
    bool.fromEnvironment('USE_MOCK_SERVICES', defaultValue: false);

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

  /// Parse an AuthTokenResponse `data` object (conventions §10 — camelCase keys).
  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        userId: json['userId'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessTokenExpiresInSeconds:
            (json['accessTokenExpiresInSeconds'] as num).toInt(),
        refreshTokenTtlDays: (json['refreshTokenTtlDays'] as num).toInt(),
      );
}

class AuthService {
  AuthService({ApiClient? client, TokenStore? tokenStore})
      : _client = client ?? sharedApiClient,
        _tokenStore = tokenStore ?? sharedTokenStore;

  final ApiClient _client;
  final TokenStore _tokenStore;

  /// POST /auth/register/start { phone } — dispatches a REGISTRATION OTP.
  /// Maps the 202 `data` → OtpInit. A 409 `conflict` (phone already registered)
  /// surfaces as an ApiException for the Sign Up screen.
  Future<OtpInit> registerStart(String phone) async {
    if (useMockServices) {
      await Future.delayed(const Duration(milliseconds: 600));
      return OtpInit(
        ttlSeconds: 600,
        resendCooldownSeconds: 30,
        maskedPhone: _mask(phone),
      );
    }
    final data = await _client.post(
      '/auth/register/start',
      body: {'phone': phone},
      authenticated: false, // [public]
    );
    return _otpInit(data);
  }

  /// POST /auth/login { phone } — anti-enumeration: always 200, OTP sent only if registered.
  /// Maps the 200 `data` (message + lifecycle params) → OtpInit.
  Future<OtpInit> login(String phone) async {
    if (useMockServices) {
      await Future.delayed(const Duration(milliseconds: 600));
      return OtpInit(
        ttlSeconds: 600,
        resendCooldownSeconds: 30,
        maskedPhone: _mask(phone),
      );
    }
    final data = await _client.post(
      '/auth/login',
      body: {'phone': phone},
      authenticated: false, // [public]
    );
    return _otpInit(data);
  }

  /// POST /auth/register { phone, displayName, email?, idNumber, registrationToken }
  /// → 201 AuthTokens. Runs after a successful REGISTRATION OTP verify. Persists the
  /// returned session pair (access → memory, refresh → secure storage). A 401
  /// (registrationToken invalid/expired/used) surfaces as an ApiException.
  Future<AuthTokens> register(RegisterDraft draft, String registrationToken) async {
    if (useMockServices) {
      await Future.delayed(const Duration(milliseconds: 600));
      const tokens = AuthTokens(
        userId: 'stub-user',
        accessToken: 'stub-access',
        refreshToken: 'stub-refresh',
        accessTokenExpiresInSeconds: 900,
        refreshTokenTtlDays: 30,
      );
      await _persist(tokens);
      return tokens;
    }
    final data = await _client.post(
      '/auth/register',
      body: {
        'phone': draft.phone,
        'displayName': draft.displayName,
        if (draft.email != null && draft.email!.isNotEmpty) 'email': draft.email,
        'idNumber': draft.idNumber,
        'registrationToken': registrationToken,
      },
      authenticated: false, // [public]
    );
    final tokens = AuthTokens.fromJson(data);
    await _persist(tokens);
    return tokens;
  }

  /// POST /auth/logout { refreshToken } — revokes the refresh token server-side, then
  /// clears both tokens locally. Idempotent on the client: even if the server call
  /// fails, the local tokens are cleared so the device is logged out.
  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (!useMockServices && refreshToken != null) {
      try {
        await _client.post(
          '/auth/logout',
          body: {'refreshToken': refreshToken},
        );
      } on ApiException {
        // Already-revoked / network: local clear below still logs the device out.
      }
    }
    await _tokenStore.clear();
  }

  /// Persist a freshly minted session pair via the shared token store.
  Future<void> _persist(AuthTokens tokens) => _tokenStore.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );

  // Parse the auth-initiate `data` (register/start 202, login 200) into OtpInit.
  // login also carries `message`, which the Verify screen does not need.
  OtpInit _otpInit(Map<String, dynamic> data) => OtpInit(
        ttlSeconds: (data['ttlSeconds'] as num).toInt(),
        resendCooldownSeconds: (data['resendCooldownSeconds'] as num).toInt(),
        maskedPhone: data['maskedPhone'] as String,
      );

  // Mock-only masking; the real maskedPhone comes from the server.
  String _mask(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return '+27****';
    return '+27****${digits.substring(digits.length - 4)}';
  }
}
