import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: t.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Your municipal\naccount, clear.', style: textTheme.displayLarge),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Check your balance, track bills, and understand every charge — '
                'in plain language.',
                style: textTheme.bodyLarge,
              ),
              const Spacer(),
              ErButton(
                label: 'Get started',
                onPressed: () => context.go('/signup'),
              ),
              const SizedBox(height: AppSpacing.sm),
              ErButton(
                label: 'I already have an account',
                variant: ErButtonVariant.ghost,
                onPressed: () => context.go('/login'),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
