// success_screen.dart — terminal confirmation of the Home → Pay → Success flow.
//
// Theme: DARK — the entire screen is rendered against the ink-900 (#0A0B0A)
// surface using the dark EasyRates token set. The lime accent reads at ~19:1
// on ink-900, making the check circle and amount maximally legible.
//
// Sections (centred vertically):
//   • lime glow check circle   — 96 px circle; lime box-shadow glow; Lucide check
//   • "Payment sent" headline  — headlineMedium (30 Space Grotesk), onSurface
//   • amount in lime           — headlineLarge (40 Space Grotesk) tabular, primary
//   • receipt card             — reference number + formatted date, on surface card
//   • "Done" CTA               — full-width primary (lime) AppButton, sticky bottom
//
// The screen accepts optional [amount] and [reference] parameters so it can be
// driven from the Pay flow; both default to demo values for standalone testing.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({
    super.key,
    this.amount = 1250.00,
    this.reference = 'EMF-20260613-4821',
    this.paidAt = 'Jun 13 2026 · 14:32',
  });

  /// The confirmed payment amount in Rand — shown in lime, tabular figures.
  final double amount;

  /// Municipal payment reference number displayed on the receipt line.
  final String reference;

  /// Human-readable date/time shown on the receipt line.
  final String paidAt;

  // SA money format: "R 1 250.00"
  String _fmt(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot   = fixed.indexOf('.');
    final dec   = fixed.substring(dot + 1);
    final int   = fixed.substring(0, dot);
    final buf   = StringBuffer();
    for (var i = 0; i < int.length; i++) {
      if (i > 0 && (int.length - i) % 3 == 0) buf.write(' ');
      buf.write(int[i]);
    }
    return 'R $buf.$dec';
  }

  @override
  Widget build(BuildContext context) {
    // Force the entire screen into the dark token set. The system theme is
    // irrelevant here — Success is always ink-900 regardless of user preference.
    return Theme(
      data: buildEasyRatesDarkTheme(),
      child: Builder(builder: _buildDark),
    );
  }

  Widget _buildDark(BuildContext context) {
    final theme  = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt     = theme.textTheme;
    final t      = theme.extension<EasyRatesTokens>()!;

    return Scaffold(
      // ink-900 — the deepest ink, brightness-independent (same value in both sets).
      backgroundColor: t.ink900,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.s5),
          child: Column(
            children: [
              // ── Centred confirmation content ─────────────────────────────
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Lime glow check circle ──────────────────────────
                      _GlowCheckCircle(scheme: scheme, t: t),
                      SizedBox(height: t.s5),

                      // ── "Payment sent" headline ─────────────────────────
                      Text(
                        'Payment sent',
                        style: tt.headlineMedium!.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      SizedBox(height: t.s2),

                      // ── Amount in lime ──────────────────────────────────
                      Text(
                        _fmt(amount),
                        style: tt.headlineLarge!.copyWith(
                          color: scheme.primary, // lime-500
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      SizedBox(height: t.s5),

                      // ── Receipt card ────────────────────────────────────
                      _ReceiptCard(
                        reference: reference,
                        paidAt: paidAt,
                        t: t,
                        scheme: scheme,
                        tt: tt,
                      ),
                    ],
                  ),
                ),
              ),

              // ── "Done" CTA — sticky to the bottom of safe area ──────────
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Done',
                  variant: AppButtonVariant.primary,
                  onPressed: () => context.go('/home'),
                ),
              ),
              SizedBox(height: t.s4),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Lime glow check circle ────────────────────────────────────────────────────
// A 96×96 circle filled with a soft lime tint; a lime BoxShadow radiates outward
// to create the "glow" halo; the Lucide check sits centred in lime.
class _GlowCheckCircle extends StatelessWidget {
  const _GlowCheckCircle({required this.scheme, required this.t});
  final ColorScheme scheme;
  final EasyRatesTokens t;

  @override
  Widget build(BuildContext context) {
    // lime-500 at varying opacities for the tint fill and the glow shadow.
    final lime = scheme.primary; // lime-500 (#E1FB8E)

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Soft lime tint fill — primary-container from the dark scheme is
        // #42511D (deep lime on ink), giving the circle a subtle lime ground.
        color: scheme.primaryContainer,
        boxShadow: [
          BoxShadow(
            color: lime.withAlpha(100), // ~39% — inner halo · design-value-ok
            blurRadius: 24,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: lime.withAlpha(48), // ~19% — wide outer glow · design-value-ok
            blurRadius: 48,
            spreadRadius: 8,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(LucideIcons.check, size: t.iconLg * 1.5, color: lime),
    );
  }
}

// ── Receipt card ──────────────────────────────────────────────────────────────
// A small surface card (inkSurface = #161816) that lifts off the ink-900 floor
// just enough to show the reference number and date as a receipt stub.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.reference,
    required this.paidAt,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final String reference;
  final String paidAt;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final muted = scheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.s4, vertical: t.s3),
      decoration: BoxDecoration(
        // surface in the dark scheme = inkSurface (#161816) — lifts off ink-900.
        color: scheme.surface,
        borderRadius: t.radiusMd,
        border: Border.all(color: t.hairline, width: t.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.receipt, size: t.iconSm, color: muted),
          SizedBox(width: t.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ref $reference',
                style: tt.labelMedium!.copyWith(color: scheme.onSurface),
              ),
              SizedBox(height: 2),
              Text(
                paidAt,
                style: tt.bodySmall!.copyWith(color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
