import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../components/components.dart';
import '../../services/auth_service.dart';
import '../../services/otp_service.dart';
import '../../theme/theme.dart';

/// Navigation payload for `/otp`, passed via `context.go('/otp', extra: …)`.
/// `phone` is the raw E.164 number (used for verify/resend); `maskedPhone`,
/// `ttlSeconds`, and `resendCooldownSeconds` come from the auth-initiate response
/// (register/start or login) so nothing is hardcoded.
class OtpArgs {
  final String phone;
  final String maskedPhone;
  final OtpPurpose purpose;
  final int ttlSeconds;
  final int resendCooldownSeconds;

  /// The Sign Up fields, carried through REGISTRATION so the screen can call
  /// POST /auth/register after a successful verify. Null for LOGIN.
  final RegisterDraft? registerDraft;

  const OtpArgs({
    required this.phone,
    required this.maskedPhone,
    required this.purpose,
    required this.ttlSeconds,
    required this.resendCooldownSeconds,
    this.registerDraft,
  });
}

enum _UiState { live, expired, support }

/// Why we're on the expired screen — picks the copy (otp-service routes both
/// `otp_expired` and `max_attempts_exceeded` here, distinguished by error.code).
enum _ExpiredReason { ttl, maxAttempts }

/// OTP entry — implements the otp-service verify/resend state machine. Shared by the
/// REGISTRATION and LOGIN flows; `args.purpose` routes the verified result. Timers are
/// advisory UX only — the server is the source of truth, so every verify response is
/// honoured regardless of the local clock.
class OtpScreen extends StatefulWidget {
  final OtpArgs args;
  const OtpScreen({super.key, required this.args});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = OtpService();
  final _auth = AuthService();
  final _codeController = TextEditingController();

  Timer? _ticker;
  _UiState _state = _UiState.live;
  _ExpiredReason _expiredReason = _ExpiredReason.ttl;

  late int _expiryRemaining; // silent — flips to EXPIRED at 0
  late int _resendRemaining; // visible — re-enables Resend at 0

  bool _loading = false;
  String? _error;
  int? _attemptsRemaining;

  @override
  void initState() {
    super.initState();
    _expiryRemaining = widget.args.ttlSeconds;
    _resendRemaining = widget.args.resendCooldownSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _tick(Timer _) {
    setState(() {
      if (_resendRemaining > 0) _resendRemaining--;
      if (_state == _UiState.live && _expiryRemaining > 0) {
        _expiryRemaining--;
        if (_expiryRemaining == 0) {
          _state = _UiState.expired;
          _expiredReason = _ExpiredReason.ttl;
        }
      }
    });
  }

  String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _destination => '/dashboard'; // both purposes land here for now

  Future<void> _verify(String code) async {
    if (_loading || _state != _UiState.live || code.length != 6) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await _otp.verify(
      phone: widget.args.phone,
      code: code,
      purpose: widget.args.purpose,
    );
    if (!mounted) return;

    switch (result) {
      case OtpVerifyRegistration(:final registrationToken):
        await _completeRegistration(registrationToken);
      case OtpVerifyLogin():
        // TODO: persist the AuthTokens (in-memory access + secure-storage refresh).
        _ticker?.cancel();
        context.go(_destination);
      case OtpInvalid(:final attemptsRemaining):
        setState(() {
          _loading = false;
          _error = 'Incorrect code.';
          _attemptsRemaining = attemptsRemaining;
          _codeController.clear();
        });
      case OtpExpired():
        setState(() {
          _loading = false;
          _state = _UiState.expired;
          _expiredReason = _ExpiredReason.ttl;
        });
      case OtpMaxAttemptsExceeded():
        setState(() {
          _loading = false;
          _state = _UiState.expired;
          _expiredReason = _ExpiredReason.maxAttempts;
        });
    }
  }

  /// REGISTRATION verify succeeded: exchange the single-use registrationToken + the
  /// Sign Up draft for the session via POST /auth/register, then advance. Canonical next
  /// step is Upload Proof of Address (KYC); routed to the dashboard until that screen exists.
  Future<void> _completeRegistration(String registrationToken) async {
    final draft = widget.args.registerDraft;
    if (draft != null) {
      // TODO: persist the returned AuthTokens, then go to Upload Proof of Address.
      await _auth.register(draft, registrationToken);
      if (!mounted) return;
    }
    _ticker?.cancel();
    context.go(_destination);
  }

  Future<void> _resend() async {
    if (_loading) return;
    setState(() => _loading = true);

    final result = await _otp.resend(
      phone: widget.args.phone,
      purpose: widget.args.purpose,
    );
    if (!mounted) return;

    switch (result) {
      case OtpResendOk(
          :final ttlSeconds,
          :final resendCooldownSeconds,
          :final resendsRemaining
        ):
        setState(() {
          _loading = false;
          if (resendsRemaining == 0) {
            _state = _UiState.support;
          } else {
            _state = _UiState.live;
            _expiryRemaining = ttlSeconds; // server-authoritative TTL of the new code
            _resendRemaining = resendCooldownSeconds;
            _error = null;
            _attemptsRemaining = null;
            _codeController.clear();
          }
        });
      case OtpResendCooldown(:final retryAfterSeconds):
        setState(() {
          _loading = false;
          _resendRemaining = retryAfterSeconds;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final t = theme.extension<EasyRatesTokens>()!;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: Padding(
        padding: t.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(_title, style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(_subtitle, style: textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            ..._buildForState(scheme, textTheme, t),
          ],
        ),
      ),
    );
  }

  String get _title => switch (_state) {
        _UiState.live => 'Enter your code',
        _UiState.expired => switch (_expiredReason) {
            _ExpiredReason.ttl => 'Code expired',
            _ExpiredReason.maxAttempts => 'Too many attempts',
          },
        _UiState.support => 'Need a hand?',
      };

  String get _subtitle => switch (_state) {
        _UiState.live => 'We sent a 6-digit code to ${widget.args.maskedPhone}.',
        _UiState.expired => switch (_expiredReason) {
            _ExpiredReason.ttl =>
              'That code is no longer valid. Request a new one to continue.',
            _ExpiredReason.maxAttempts =>
              'You\'ve entered too many incorrect codes. Request a new one.',
          },
        _UiState.support =>
          'You\'ve reached the resend limit for now. Please contact support to continue.',
      };

  List<Widget> _buildForState(
    ColorScheme scheme,
    TextTheme textTheme,
    EasyRatesTokens t,
  ) {
    switch (_state) {
      case _UiState.live:
        return [
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            enabled: !_loading,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: '••••••',
              counterText: '',
            ),
            onChanged: (v) {
              if (v.length == 6) _verify(v);
            },
            onSubmitted: _verify,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _attemptsRemaining != null
                  ? '$_error $_attemptsRemaining attempts remaining.'
                  : _error!,
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _resendControl(textTheme, t),
        ];

      case _UiState.expired:
        return [
          ErButton(
            label: 'Request a new code',
            loading: _loading,
            onPressed: _resend,
          ),
        ];

      case _UiState.support:
        return [
          ErButton(
            label: 'Contact support',
            variant: ErButtonVariant.outlined,
            // TODO: wire support contact (tel: / email / in-app).
            onPressed: () {},
          ),
        ];
    }
  }

  /// Visible resend control: a disabled cooldown label while `_resendRemaining` ticks,
  /// an enabled ghost button at 0.
  Widget _resendControl(TextTheme textTheme, EasyRatesTokens t) {
    if (_resendRemaining > 0) {
      return Text(
        'Resend code in ${_mmss(_resendRemaining)}',
        style: textTheme.bodySmall?.copyWith(color: t.fgMuted),
      );
    }
    return ErButton(
      label: 'Resend code',
      variant: ErButtonVariant.ghost,
      loading: _loading,
      onPressed: _resend,
    );
  }
}
