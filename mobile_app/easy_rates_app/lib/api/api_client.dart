// api_client.dart — the single Dio-based front door to the EasyRates backend.
//
// Implements the cross-cutting rules from api/conventions.md so the service layer
// (auth_service, otp_service) only deals in typed payloads and error codes:
//
//   §1  base URL  : one origin, `/api/v1` prefix, host from build config.
//   §2  envelope  : every response is `{ data, error }`; this client unwraps it,
//                   returning `data` on success and THROWING an ApiException whose
//                   ApiError.code the services branch on (never the HTTP status).
//   §6  auth      : injects `Authorization: Bearer <accessToken>` (in-memory token);
//                   on a 401 it calls POST /auth/refresh with the stored refresh
//                   token, rotates the pair, and retries the original request ONCE.
//                   On refresh failure it clears both tokens and surfaces
//                   `unauthenticated` so the UI can route to Login.
//
// The base URL is overridable at build time:
//   flutter run --dart-define=API_BASE_URL=http://localhost:8080/api/v1
// Defaults to the Android-emulator host loopback (10.0.2.2). For web/iOS-sim use
// http://localhost:8080/api/v1; for a device use the LAN IP of the gateway.

import 'package:dio/dio.dart';

import '../services/api_response.dart';
import 'token_store.dart';

/// Thrown when the backend returns an error envelope (or a transport error maps to
/// one). Carries the [ApiError] so a service can `switch` on `error.code`.
class ApiException implements Exception {
  final ApiError error;
  const ApiException(this.error);

  String get code => error.code;
  String get message => error.message;
  Map<String, dynamic> get details => error.details;

  @override
  String toString() => 'ApiException(${error.code}: ${error.message})';
}

class ApiClient {
  ApiClient({TokenStore? tokenStore, Dio? dio})
      : tokenStore = tokenStore ?? TokenStore() {
    _dio = dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // Accept the body on any status — the envelope (not the status code)
            // is the source of truth (§2), so we parse rather than let Dio throw.
            validateStatus: (_) => true,
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
          ),
        );
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest),
    );
  }

  /// Single origin + `/api/v1` prefix (conventions §1). Overridable via
  /// `--dart-define=API_BASE_URL=...`. Default targets the Android emulator's
  /// host loopback; document localhost for web/iOS-sim.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  final TokenStore tokenStore;
  late final Dio _dio;

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokenStore.accessToken;
    if (token != null && _wantsAuth(options)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // Auth header is skipped on the refresh call itself (it authenticates with the
  // refresh-token body, not a bearer) and any request flagged noAuth.
  bool _wantsAuth(RequestOptions options) {
    if (options.extra['noAuth'] == true) return false;
    return true;
  }

  // ---- public verbs ---------------------------------------------------------

  /// POST [path] with a JSON [body]; returns the unwrapped `data` object.
  /// Set [authenticated] = false for `[public]` routes (no bearer expected, and
  /// no 401-refresh retry — those routes never 401 on a missing token).
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) {
    return _send(
      () => _dio.post(
        path,
        data: body,
        options: Options(extra: {'noAuth': !authenticated}),
      ),
      authenticated: authenticated,
    );
  }

  /// GET [path]; returns the unwrapped `data` object.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = true,
  }) {
    return _send(
      () => _dio.get(
        path,
        queryParameters: query,
        options: Options(extra: {'noAuth': !authenticated}),
      ),
      authenticated: authenticated,
    );
  }

  // ---- core: send → unwrap envelope → (401 ? refresh+retry-once) ------------

  Future<Map<String, dynamic>> _send(
    Future<Response> Function() request, {
    required bool authenticated,
  }) async {
    Response response;
    try {
      response = await request();
    } on DioException catch (e) {
      // Transport-level failure (no/garbled response): surface as a generic error
      // the services can still branch on without crashing.
      throw ApiException(
        ApiError(
          code: 'internal_server_error',
          message: e.message ?? 'Network error. Please try again.',
        ),
      );
    }

    final parsed = _unwrap(response);
    if (parsed.error == null) {
      return parsed.data ?? const {};
    }

    // 401 → refresh → retry-once (conventions §6). Only for authenticated routes,
    // and never recurse if it was the refresh call itself that 401'd.
    if (parsed.error!.code == 'unauthenticated' && authenticated) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        final retry = await request();
        final retryParsed = _unwrap(retry);
        if (retryParsed.error == null) {
          return retryParsed.data ?? const {};
        }
        throw ApiException(retryParsed.error!);
      }
      // Refresh failed: tokens already cleared by _tryRefresh; surface 401.
    }

    throw ApiException(parsed.error!);
  }

  /// Exchange the stored refresh token for a new pair (rotated). Returns true on
  /// success (tokens persisted), false on failure (tokens cleared → UI to Login).
  Future<bool> _tryRefresh() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null) {
      await tokenStore.clear();
      return false;
    }
    Response response;
    try {
      response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'noAuth': true}),
      );
    } on DioException {
      await tokenStore.clear();
      return false;
    }
    final parsed = _unwrap(response);
    final data = parsed.data;
    if (parsed.error != null || data == null) {
      // 401 (reuse/expiry) or malformed: clear both, go to Login (§6).
      await tokenStore.clear();
      return false;
    }
    await tokenStore.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return true;
  }

  // ---- envelope parsing (§2) ------------------------------------------------

  /// Split a `{ data, error }` body into its two halves. `data == null` iff
  /// `error != null` (§2 biconditional) — but we tolerate a malformed/empty body
  /// by mapping it to a generic error rather than throwing a cast error.
  _Envelope _unwrap(Response response) {
    final body = response.data;
    if (body is! Map) {
      return _Envelope(
        error: ApiError(
          code: 'internal_server_error',
          message: 'Unexpected response from server.',
        ),
      );
    }
    final json = Map<String, dynamic>.from(body);
    final error = json['error'];
    if (error is Map) {
      final em = Map<String, dynamic>.from(error);
      final details = em['details'];
      return _Envelope(
        error: ApiError(
          code: (em['code'] as String?) ?? 'internal_server_error',
          message: (em['message'] as String?) ?? 'Something went wrong.',
          details: details is Map
              ? Map<String, dynamic>.from(details)
              : const {},
        ),
      );
    }
    final data = json['data'];
    return _Envelope(
      data: data is Map ? Map<String, dynamic>.from(data) : const {},
    );
  }
}

/// Internal parsed-envelope holder: exactly one of [data] / [error] is non-null
/// (mirrors the §2 biconditional).
class _Envelope {
  final Map<String, dynamic>? data;
  final ApiError? error;
  const _Envelope({this.data, this.error});
}
