// splash_screen.dart — ink-900 brand entry screen.
//
// The Splash screen is ALWAYS dark, regardless of the device/app theme setting —
// the ink field is a design signature, not a brightness preference. Achieved by
// wrapping in Theme(data: buildEasyRatesDarkTheme()), which scopes the dark token
// set to this subtree without touching MaterialApp's global ThemeMode.
//
// Layout (top → bottom):
//   spacer (flex 2)
//   droplet logo  — 96pt circle, lime fill, two-layer glow
//   spacing
//   "EasyRates"   — displayLarge, 58pt Space Grotesk, lime
//   spacing
//   tagline       — bodyLarge, 17pt Manrope, muted onSurface
//   spacer (flex 1)
//   carousel dots — 3 pills; first (this screen) active in lime
//   spacer (flex 3)
//   "Get started" — full-width lime pill → /onboarding
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildEasyRatesDarkTheme(),
      child: const _SplashBody(),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;

    return Scaffold(
      backgroundColor: t.appBg, // ink-900
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // ── Droplet logo + lime glow ───────────────────────────────────
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withAlpha(AppColors.tintFillAlpha),
                    boxShadow: [
                      // inner bright ring
                      BoxShadow(
                        color: scheme.primary.withAlpha(AppColors.tintBorderAlpha),
                        blurRadius: 32,
                        spreadRadius: 8,
                      ),
                      // outer soft halo
                      BoxShadow(
                        color: scheme.primary.withAlpha(AppColors.tintFillAlpha),
                        blurRadius: 72,
                        spreadRadius: 24,
                      ),
                    ],
                  ),
                  child: Icon(
                    LucideIcons.droplet,
                    size: 48,
                    color: scheme.primary,
                  ),
                ),
              ),

              SizedBox(height: t.s8), // 32

              // ── Headline — brand name ─────────────────────────────────────
              Text(
                'EasyRates',
                style: textTheme.displayLarge!.copyWith(color: scheme.primary),
                textAlign: TextAlign.center,
              ),

              SizedBox(height: t.s3), // 12

              // ── Subhead — localised to Emfuleni ──────────────────────────
              Text(
                'Emfuleni municipal billing,\nplain and simple.',
                style: textTheme.bodyLarge!.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 1),

              // ── Carousel dots ─────────────────────────────────────────────
              // Three dots represent the onboarding flow; the first is active
              // (this screen is step 0).
              Center(
                child: _Dots(active: 0, count: 3, scheme: scheme, t: t),
              ),

              const Spacer(flex: 3),

              // ── Primary CTA ────────────────────────────────────────────────
              AppButton(
                label: 'Get started',
                variant: AppButtonVariant.primary,
                onPressed: () => context.go('/home'),
              ),

              SizedBox(height: t.s6), // 24 — breathing room above home-indicator
            ],
          ),
        ),
      ),
    );
  }
}

// Three-dot step indicator. The active dot is a lime pill; inactive dots are
// lime at tintBorderAlpha (~30%) — visible on ink but clearly subordinate.
class _Dots extends StatelessWidget {
  const _Dots({
    required this.active,
    required this.count,
    required this.scheme,
    required this.t,
  });

  final int active;
  final int count;
  final ColorScheme scheme;
  final EasyRatesTokens t;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: t.s1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.primary
                  : scheme.primary.withAlpha(AppColors.tintBorderAlpha),
              borderRadius: BorderRadius.circular(t.rPill),
            ),
          ),
        );
      }),
    );
  }
}
