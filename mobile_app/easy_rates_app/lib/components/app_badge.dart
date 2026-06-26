// app_badge.dart — a token-driven status pill with five variants.
//
//   paid     → positive · check        ink-green "paid"
//   due      → warning  · clock        amber "due soon"
//   pastDue  → error    · circleAlert  red "overdue"
//   autoPay  → info     · repeat       sky "enrolled in autopay"
//   newBill  → fgMuted  · fileText     neutral "a new statement"
//
// Each variant resolves to one semantic colour + one Lucide glyph + a label via
// AppBadgeVariant.spec(). The pill paints a soft tint of that colour (fill +
// hairline border) using the AppColors tint alphas, sizes from the token store,
// and labelMedium (the "chips" type slot). Nothing is hardcoded — see spec().
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/theme.dart';

enum AppBadgeVariant {
  paid,
  due,
  pastDue,
  autoPay,
  newBill;

  // Maps this variant onto its semantic colour, glyph, label, and the shared
  // pill geometry — all from design-system tokens. The single source of truth
  // for how a badge looks.
  AppBadgeSpec spec(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = theme.extension<EasyRatesTokens>()!;

    late Color color;
    late IconData icon;
    late String label;
    switch (this) {
      case AppBadgeVariant.paid:
        color = t.positive;   icon = LucideIcons.check;        label = 'Paid';
      case AppBadgeVariant.due:
        color = t.warning;    icon = LucideIcons.clock;        label = 'Due';
      case AppBadgeVariant.pastDue:
        color = scheme.error; icon = LucideIcons.circleAlert;  label = 'Past due';
      case AppBadgeVariant.autoPay:
        color = t.info;       icon = LucideIcons.repeat;       label = 'AutoPay';
      case AppBadgeVariant.newBill:
        color = t.fgMuted;    icon = LucideIcons.fileText;     label = 'New bill';
    }

    return AppBadgeSpec(
      color: color,
      icon: icon,
      label: label,
      fillAlpha: AppColors.tintFillAlpha,     // ~10% soft fill
      borderAlpha: AppColors.tintBorderAlpha, // ~30% hairline
      padding: t.badgePadding,                // h12 / v4
      radius: t.radiusPill,                   // pill
      iconSize: t.iconSm,                     // 18 — small glyph
      gap: t.s1,                              // 4 — glyph→label
      textStyle: theme.textTheme.labelMedium!, // 13 Manrope w600 — chips
    );
  }
}

// The resolved visual spec for one badge. Pure data — produced by
// AppBadgeVariant.spec(), consumed by AppBadge.build().
@immutable
class AppBadgeSpec {
  const AppBadgeSpec({
    required this.color,
    required this.icon,
    required this.label,
    required this.fillAlpha,
    required this.borderAlpha,
    required this.padding,
    required this.radius,
    required this.iconSize,
    required this.gap,
    required this.textStyle,
  });

  final Color color;          // the semantic hue; tinted for fill/border, solid for glyph+label
  final IconData icon;        // leading Lucide glyph
  final String label;
  final int fillAlpha;
  final int borderAlpha;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final double iconSize;
  final double gap;
  final TextStyle textStyle;
}

class AppBadge extends StatelessWidget {
  const AppBadge(this.variant, {super.key});

  final AppBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final spec = variant.spec(context);
    return Container(
      padding: spec.padding,
      decoration: BoxDecoration(
        color: spec.color.withAlpha(spec.fillAlpha),
        borderRadius: spec.radius,
        border: Border.all(color: spec.color.withAlpha(spec.borderAlpha)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: spec.iconSize, color: spec.color),
          SizedBox(width: spec.gap),
          Text(spec.label, style: spec.textStyle.copyWith(color: spec.color)),
        ],
      ),
    );
  }
}
