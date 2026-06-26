// pay_screen.dart — the Pay screen (Home → Pay → Success middle step).
//
// Sections (top → bottom):
//   • back button         — leading chevron, "Pay account" title
//   • AMOUNT DUE hero     — eyebrow / Space Grotesk tabular figure / Due badge
//   • breakdown card      — supply / energy / standing / total (Emfuleni tariffs)
//   • payment-method card — masked Absa card + "Change" affordance
//   • sticky bottom bar   — full-width "Pay R …" primary button + secured footer
//
// Breakdown arithmetic (asserted at the bottom of this file):
//   Water supply tariff   R  680.00
//   Wastewater levy       R  412.50
//   Network standing      R  157.50
//   ─────────────────────────────────
//   Total                 R 1 250.00   ← same figure as the hero
//
// All colours, sizes, and radii resolve through EasyRatesTokens.
// All money is rendered "R <grouped-integer>.<cents>" (SA convention).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

// ── Breakdown data ───────────────────────────────────────────────────────────
// Line-item amounts in Rand. Their sum MUST equal _kTotal (asserted below).
const double _kSupply    = 680.00;
const double _kWastewater= 412.50;
const double _kStanding  = 157.50;
const double _kTotal     = _kSupply + _kWastewater + _kStanding; // 1 250.00

// ── Money formatter (SA style: "R 1 250.00") ─────────────────────────────────
String _fmt(double value, {String symbol = 'R'}) {
  final fixed = value.toStringAsFixed(2);
  final dot   = fixed.indexOf('.');
  final dec   = fixed.substring(dot + 1);
  final buf   = StringBuffer();
  final int   = fixed.substring(0, dot);
  for (var i = 0; i < int.length; i++) {
    if (i > 0 && (int.length - i) % 3 == 0) buf.write(' '); // narrow NBSP thousands
    buf.write(int[i]);
  }
  return '$symbol $buf.$dec';
}

class PayScreen extends StatelessWidget {
  const PayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt     = theme.textTheme;
    final t      = theme.extension<EasyRatesTokens>()!;

    return Scaffold(
      backgroundColor: t.appBg,
      body: Column(
        children: [
          // ── Scrollable body ───────────────────────────────────────────────
          Expanded(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: t.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: t.s3),

                    // ── Back button row ────────────────────────────────────
                    Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'Back',
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).maybePop(),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsets.all(t.s2),
                              child: Icon(
                                LucideIcons.chevronLeft,
                                size: t.iconLg,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: t.s2),
                        Text('Pay account', style: tt.titleMedium),
                      ],
                    ),
                    SizedBox(height: t.s5),

                    // ── AMOUNT DUE hero ────────────────────────────────────
                    Text(
                      'AMOUNT DUE',
                      style: tt.labelSmall!.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: t.s1),
                    // FittedBox prevents the 40px figure from overflowing on
                    // narrow screens.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _fmt(_kTotal),
                        style: tt.headlineLarge!.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(height: t.s2),
                    const AppBadge(AppBadgeVariant.due),
                    SizedBox(height: t.s5),

                    // ── Breakdown card ────────────────────────────────────
                    _SectionLabel('Breakdown', tt, t, scheme),
                    SizedBox(height: t.s2),
                    _BreakdownCard(t: t, scheme: scheme, tt: tt),
                    SizedBox(height: t.s5),

                    // ── Payment-method card ────────────────────────────────
                    _SectionLabel('Payment method', tt, t, scheme),
                    SizedBox(height: t.s2),
                    _PaymentMethodCard(t: t, scheme: scheme, tt: tt),
                    SizedBox(height: t.s5),
                  ],
                ),
              ),
            ),
          ),

          // ── Sticky CTA bar ────────────────────────────────────────────────
          _StickyBar(t: t, scheme: scheme, tt: tt),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, this.tt, this.t, this.scheme);
  final String text;
  final TextTheme tt;
  final EasyRatesTokens t;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: tt.titleSmall!.copyWith(color: scheme.onSurface));
}

// ── Breakdown card ────────────────────────────────────────────────────────────
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.t, required this.scheme, required this.tt});
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: t.radiusLg,
        border: Border.all(color: scheme.outlineVariant, width: t.borderWidth),
      ),
      child: Column(
        children: [
          _LineItem(
            label: 'Water supply tariff',
            amount: _kSupply,
            t: t, scheme: scheme, tt: tt,
          ),
          _RowDivider(scheme: scheme),
          _LineItem(
            label: 'Wastewater levy',
            amount: _kWastewater,
            t: t, scheme: scheme, tt: tt,
          ),
          _RowDivider(scheme: scheme),
          _LineItem(
            label: 'Network standing charge',
            amount: _kStanding,
            t: t, scheme: scheme, tt: tt,
          ),
          // Bold divider before the total row
          Divider(height: 1, color: scheme.outline, thickness: t.borderWidth),
          _TotalRow(t: t, scheme: scheme, tt: tt),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.scheme});
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: scheme.outlineVariant);
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.label,
    required this.amount,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final String label;
  final double amount;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: t.listTilePadding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurface),
            ),
          ),
          Text(
            _fmt(amount),
            style: tt.bodyMedium!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.t, required this.scheme, required this.tt});
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: t.listTilePadding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Total',
              style: tt.titleSmall!.copyWith(color: scheme.onSurface),
            ),
          ),
          Text(
            _fmt(_kTotal),
            style: tt.titleSmall!.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment-method card ───────────────────────────────────────────────────────
class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.t, required this.scheme, required this.tt});
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: t.listTilePadding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: t.radiusLg,
        border: Border.all(color: scheme.outlineVariant, width: t.borderWidth),
      ),
      child: Row(
        children: [
          // Card-type icon tile
          Container(
            width: t.s12,
            height: t.s12,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: t.radiusMd,
            ),
            alignment: Alignment.center,
            child: Icon(
              LucideIcons.creditCard,
              size: t.iconMd,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(width: t.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Absa Bank  •••• 4821',
                  style: tt.titleSmall!.copyWith(color: scheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: t.s1),
                Text(
                  'Expires 09/28',
                  style: tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(width: t.s3),
          Semantics(
            button: true,
            label: 'Change payment method',
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Change',
                style: tt.labelMedium!.copyWith(color: scheme.secondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sticky CTA bar ────────────────────────────────────────────────────────────
class _StickyBar extends StatelessWidget {
  const _StickyBar({required this.t, required this.scheme, required this.tt});
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: t.borderWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.s5, vertical: t.s4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Full-width primary CTA
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Pay ${_fmt(_kTotal)}',
                  variant: AppButtonVariant.primary,
                  onPressed: () => context.go('/success', extra: _kTotal),
                ),
              ),
              SizedBox(height: t.s3),
              // Secured footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.lockKeyhole,
                    size: t.iconSm,
                    color: scheme.onSurfaceVariant,
                  ),
                  SizedBox(width: t.s1),
                  Text(
                    'Payments secured by Emfuleni billing',
                    style: tt.bodySmall!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
