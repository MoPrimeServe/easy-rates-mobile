import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../services/auth_service.dart';
import '../../theme/theme.dart';
import '../otp/otp_screen.dart';

/// Returning-user sign-in. Passwordless (ADR-002): the user enters the phone on their
/// account, POST /auth/login dispatches a LOGIN OTP (anti-enumeration — always 200), and
/// verification on /otp is the sole auth factor. No password by design.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _loading = true);
    final init = await _auth.login(phone);
    if (mounted) {
      setState(() => _loading = false);
      context.go(
        '/otp',
        extra: OtpArgs(
          phone: phone,
          maskedPhone: init.maskedPhone,
          purpose: OtpPurpose.login,
          ttlSeconds: init.ttlSeconds,
          resendCooldownSeconds: init.resendCooldownSeconds,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: t.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('Welcome back', style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Enter your mobile number and we\'ll send you a code.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixIcon: Icon(LucideIcons.phone),
              ),
              onSubmitted: (_) => _sendCode(),
            ),
            const SizedBox(height: AppSpacing.lg),
            ErButton(label: 'Send code', loading: _loading, onPressed: _sendCode),
          ],
        ),
      ),
    );
  }
}
