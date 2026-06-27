// token_store.dart — the client's half of the token model (conventions.md §6).
//
//   Access token  : RS256 JWT, 900 s TTL. Held IN MEMORY ONLY, never on disk
//                   (a stolen device must not yield a usable bearer token).
//   Refresh token : opaque 256-bit hex, 30 d TTL, single-use (rotated on every
//                   /auth/refresh). Persisted in flutter_secure_storage so a
//                   relaunch can restore the session via /auth/refresh.
//
// clear() wipes both — called on logout and on a refresh-401 (reuse/expiry).

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the session tokens. One instance is shared by the ApiClient interceptors
/// and the auth/otp services. The access token lives only in this object's memory;
/// the refresh token is mirrored to secure storage so it survives an app restart.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshKey = 'er_refresh_token';

  final FlutterSecureStorage _storage;

  String? _accessToken; // in-memory only
  String? _refreshToken; // mirrors secure storage

  /// The current access token, or null if none / cleared.
  String? get accessToken => _accessToken;

  /// True once a session pair has been seeded (register / verify-login / refresh).
  bool get hasSession => _accessToken != null;

  /// Read the refresh token, preferring the in-memory copy and falling back to
  /// secure storage (e.g. on a cold start before any login this session).
  Future<String?> readRefreshToken() async {
    return _refreshToken ??= await _storage.read(key: _refreshKey);
  }

  /// Persist a freshly issued token pair (register, verify-LOGIN, or refresh).
  /// Access token → memory; refresh token → secure storage.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  /// Replace only the access token (kept for completeness; refresh always rotates
  /// the pair, so saveTokens is the usual path).
  void setAccessToken(String accessToken) => _accessToken = accessToken;

  /// Wipe both tokens — logout, or a refresh that failed with 401 (conventions §6).
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _refreshKey);
  }
}
