import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

/// Wizard step 1 — enter account/erf number to locate the ratepayer record.
class AccountLookupScreen extends StatefulWidget {
  const AccountLookupScreen({super.key});

  @override
  State<AccountLookupScreen> createState() => _AccountLookupScreenState();
}

class _AccountLookupScreenState extends State<AccountLookupScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final ref = _controller.text.trim();
    if (ref.isEmpty) return;

    setState(() => _loading = true);
    // TODO: call AccountService.lookup(ref)
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() => _loading = false);
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    return Scaffold(
      appBar: AppBar(title: const Text('Find your account')),
      body: Padding(
        padding: t.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text('Enter your account number', style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'You\'ll find this on any municipal statement.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 1234567890',
                prefixIcon: Icon(LucideIcons.receiptText),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: AppSpacing.md),
            ErButton(
              label: 'Look up account',
              loading: _loading,
              onPressed: _lookup,
            ),
          ],
        ),
      ),
    );
  }
}
