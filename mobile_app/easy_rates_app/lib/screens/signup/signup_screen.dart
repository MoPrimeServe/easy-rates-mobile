import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../services/auth_service.dart';
import '../../theme/theme.dart';
import '../otp/otp_screen.dart';

/// OTP-first registration (ADR-002). Collects the Sign Up fields, calls
/// POST /auth/register/start { phone } to dispatch a REGISTRATION OTP, and advances to the
/// OTP screen carrying a [RegisterDraft]; POST /auth/register runs after a successful verify.
/// No password (passwordless). Proof-of-address is a later step (Upload Proof of Address →
/// POST /auth/kyc), not yet built.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _idController = TextEditingController();
  final _phoneController = TextEditingController();
  final _auth = AuthService();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _idController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final id = _idController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Name and mobile number are required.');
      return;
    }
    if (id.length != 13) {
      setState(() => _error = 'Enter your 13-digit SA ID number.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final init = await _auth.registerStart(phone);
    if (mounted) {
      setState(() => _loading = false);
      context.go(
        '/otp',
        extra: OtpArgs(
          phone: phone,
          maskedPhone: init.maskedPhone,
          purpose: OtpPurpose.registration,
          ttlSeconds: init.ttlSeconds,
          resendCooldownSeconds: init.resendCooldownSeconds,
          registerDraft: RegisterDraft(
            phone: phone,
            displayName: name,
            email: email.isEmpty ? null : email,
            idNumber: id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final t = theme.extension<EasyRatesTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: SingleChildScrollView(
        padding: t.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('Let\'s get you set up', style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We\'ll send a code to confirm your number. No password needed.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(LucideIcons.user),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
                prefixIcon: Icon(LucideIcons.mail),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              maxLength: 13,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'SA ID number',
                counterText: '',
                prefixIcon: Icon(LucideIcons.idCard),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
              onSubmitted: (_) => _start(),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ErButton(label: 'Send code', loading: _loading, onPressed: _start),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
