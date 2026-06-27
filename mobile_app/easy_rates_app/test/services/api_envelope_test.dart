// api_envelope_test.dart — exercises the `{ data, error }` envelope unwrap
// (conventions §2), the error-code → typed-result mapping, and the 401 → refresh
// → retry-once flow (§6) against a fake Dio adapter, with the secure-storage
// channel stubbed by an in-memory map (no platform needed).

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:easy_rates_app/api/api_client.dart';
import 'package:easy_rates_app/api/token_store.dart';
import 'package:easy_rates_app/services/auth_service.dart';
import 'package:easy_rates_app/services/otp_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted HttpClientAdapter: maps a request path to a canned status + body so
/// the real ApiClient/Dio pipeline (interceptors, envelope unwrap) runs unchanged.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  /// path → (statusCode, jsonBody). May be stateful (e.g. first 401, then 200).
  final (int, Map<String, dynamic>) Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (status, body) = handler(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _success(Map<String, dynamic> data) =>
    {'data': data, 'error': null};

Map<String, dynamic> _error(String code, {Map<String, dynamic>? details}) => {
      'data': null,
      'error': {'code': code, 'message': '$code message', 'details': details ?? {}},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory stub for the flutter_secure_storage method channel so saveTokens /
  // readRefreshToken work without a real platform.
  final secureStore = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          secureStore[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return secureStore[args['key'] as String];
        case 'delete':
          secureStore.remove(args['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        case 'containsKey':
          return secureStore.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  ApiClient buildClient(
    (int, Map<String, dynamic>) Function(RequestOptions) handler, {
    TokenStore? store,
  }) {
    final dio = Dio(BaseOptions(
      baseUrl: ApiClient.baseUrl,
      validateStatus: (_) => true,
    ));
    dio.httpClientAdapter = _FakeAdapter(handler);
    return ApiClient(tokenStore: store ?? TokenStore(), dio: dio);
  }

  group('envelope unwrap (§2)', () {
    test('a success envelope yields the inner data object', () async {
      final client = buildClient((_) => (
            200,
            _success({'maskedPhone': '+27****4567', 'ttlSeconds': 600}),
          ));
      final data = await client.post('/auth/login', authenticated: false);
      expect(data['maskedPhone'], '+27****4567');
      expect(data['ttlSeconds'], 600);
    });

    test('an error envelope throws an ApiException carrying error.code + details',
        () async {
      final client = buildClient((_) => (
            422,
            _error('otp_invalid', details: {'attemptsRemaining': 3, 'maxAttempts': 5}),
          ));
      expect(
        () => client.post('/otp/verify', authenticated: false),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'otp_invalid')
              .having((e) => e.details['attemptsRemaining'], 'attemptsRemaining', 3),
        ),
      );
    });
  });

  group('OtpService.verify mapping', () {
    test('otp_invalid error → OtpInvalid(attemptsRemaining, maxAttempts)', () async {
      final client = buildClient((_) => (
            422,
            _error('otp_invalid', details: {'attemptsRemaining': 2, 'maxAttempts': 5}),
          ));
      final result = await OtpService(client: client).verify(
        phone: '+27821234567',
        code: '000000',
        purpose: OtpPurpose.login,
      );
      expect(result, isA<OtpInvalid>());
      final invalid = result as OtpInvalid;
      expect(invalid.attemptsRemaining, 2);
      expect(invalid.maxAttempts, 5);
    });

    test('REGISTRATION success → OtpVerifyRegistration(registrationToken)', () async {
      final client = buildClient((_) => (
            200,
            _success({'registrationToken': 'rt_abc123', 'ttlSeconds': 600}),
          ));
      final result = await OtpService(client: client).verify(
        phone: '+27821234567',
        code: '123456',
        purpose: OtpPurpose.registration,
      );
      expect(result, isA<OtpVerifyRegistration>());
      expect((result as OtpVerifyRegistration).registrationToken, 'rt_abc123');
    });

    test('LOGIN success → OtpVerifyLogin(tokens) and persists the pair', () async {
      final store = TokenStore();
      final client = buildClient(
        (_) => (
          200,
          _success({
            'userId': 'u1',
            'accessToken': 'jwt-access',
            'refreshToken': 'hex-refresh',
            'accessTokenExpiresInSeconds': 900,
            'refreshTokenTtlDays': 30,
          }),
        ),
        store: store,
      );
      final result = await OtpService(client: client).verify(
        phone: '+27821234567',
        code: '123456',
        purpose: OtpPurpose.login,
      );
      expect(result, isA<OtpVerifyLogin>());
      expect((result as OtpVerifyLogin).tokens.accessToken, 'jwt-access');
      expect(store.accessToken, 'jwt-access');
      expect(await store.readRefreshToken(), 'hex-refresh');
    });

    test('otp_expired → OtpExpired; max_attempts_exceeded → OtpMaxAttemptsExceeded',
        () async {
      final expiredClient = buildClient((_) => (410, _error('otp_expired')));
      expect(
        await OtpService(client: expiredClient)
            .verify(phone: '+27821234567', code: '000000', purpose: OtpPurpose.login),
        isA<OtpExpired>(),
      );

      final maxClient = buildClient(
          (_) => (429, _error('max_attempts_exceeded', details: {'maxAttempts': 5})));
      final r = await OtpService(client: maxClient)
          .verify(phone: '+27821234567', code: '000000', purpose: OtpPurpose.login);
      expect(r, isA<OtpMaxAttemptsExceeded>());
      expect((r as OtpMaxAttemptsExceeded).maxAttempts, 5);
    });
  });

  group('OtpService.resend mapping', () {
    test('202 → OtpResendOk(ttl, cooldown, resendsRemaining)', () async {
      final client = buildClient((_) => (
            202,
            _success(
                {'ttlSeconds': 600, 'resendCooldownSeconds': 30, 'resendsRemaining': 2}),
          ));
      final r = await OtpService(client: client)
          .resend(phone: '+27821234567', purpose: OtpPurpose.login);
      expect(r, isA<OtpResendOk>());
      final ok = r as OtpResendOk;
      expect(ok.resendsRemaining, 2);
      expect(ok.ttlSeconds, 600);
    });

    test('resend_cooldown_active → OtpResendCooldown(retryAfterSeconds)', () async {
      final client = buildClient((_) =>
          (429, _error('resend_cooldown_active', details: {'retryAfterSeconds': 18})));
      final r = await OtpService(client: client)
          .resend(phone: '+27821234567', purpose: OtpPurpose.login);
      expect(r, isA<OtpResendCooldown>());
      expect((r as OtpResendCooldown).retryAfterSeconds, 18);
    });
  });

  group('AuthService initiate mapping', () {
    test('register/start 202 → OtpInit', () async {
      final client = buildClient((_) => (
            202,
            _success({
              'ttlSeconds': 600,
              'resendCooldownSeconds': 30,
              'maskedPhone': '+27****4567',
            }),
          ));
      final init = await AuthService(client: client).registerStart('+27821234567');
      expect(init.ttlSeconds, 600);
      expect(init.resendCooldownSeconds, 30);
      expect(init.maskedPhone, '+27****4567');
    });

    test('register 201 → AuthTokens persisted to the store', () async {
      final store = TokenStore();
      final client = buildClient(
        (_) => (
          201,
          _success({
            'userId': 'u1',
            'accessToken': 'jwt-access',
            'refreshToken': 'hex-refresh',
            'accessTokenExpiresInSeconds': 900,
            'refreshTokenTtlDays': 30,
          }),
        ),
        store: store,
      );
      final tokens = await AuthService(client: client, tokenStore: store).register(
        const RegisterDraft(
          phone: '+27821234567',
          displayName: 'Thabo',
          idNumber: '9202204720082',
        ),
        'rt_abc123',
      );
      expect(tokens.accessToken, 'jwt-access');
      expect(store.accessToken, 'jwt-access');
      expect(await store.readRefreshToken(), 'hex-refresh');
    });
  });

  group('401 → refresh → retry-once (§6)', () {
    test('a 401 triggers a refresh and the original request is retried once',
        () async {
      final store = TokenStore();
      await store.saveTokens(accessToken: 'stale', refreshToken: 'r1');

      var sessionCalls = 0;
      final client = buildClient(
        (options) {
          if (options.path.endsWith('/auth/refresh')) {
            return (
              200,
              _success({
                'accessToken': 'fresh',
                'refreshToken': 'r2',
                'accessTokenExpiresInSeconds': 900,
                'refreshTokenTtlDays': 30,
              }),
            );
          }
          // /auth/session: 401 first, then 200 once the access token is refreshed.
          sessionCalls++;
          if (options.headers['Authorization'] == 'Bearer fresh') {
            return (200, _success({'userId': 'u1', 'kycStatus': 'VERIFIED'}));
          }
          return (401, _error('unauthenticated'));
        },
        store: store,
      );

      final data = await client.get('/auth/session');
      expect(data['userId'], 'u1');
      expect(sessionCalls, 2); // first 401, then the retry succeeded
      expect(store.accessToken, 'fresh');
      expect(await store.readRefreshToken(), 'r2'); // rotated
    });

    test('a refresh-401 clears tokens and surfaces unauthenticated', () async {
      final store = TokenStore();
      await store.saveTokens(accessToken: 'stale', refreshToken: 'r1');

      final client = buildClient(
        (options) {
          if (options.path.endsWith('/auth/refresh')) {
            return (401, _error('unauthenticated'));
          }
          return (401, _error('unauthenticated'));
        },
        store: store,
      );

      await expectLater(
        client.get('/auth/session'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unauthenticated')),
      );
      // After the throw settles, the refresh-401 path must have wiped both tokens.
      expect(store.accessToken, isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });
}
