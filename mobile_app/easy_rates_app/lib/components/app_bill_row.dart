// app_bill_row.dart — the "Your bills" list row, composed from tokens.
//
// Layout (left → right):
//   ┌────┐
//   │icon│  Title                         −R 1 250.00   [ Past due ]
//   └────┘  Subtitle                       (signed R)    (AppBadge)
//
//   • icon tile   — a rounded sunken square holding a Lucide glyph
//   • title       — titleSmall (15 Manrope w600)
//   • subtitle    — bodySmall (13), muted, single-line ellipsis
//   • amount      — Space Grotesk tabular, signed, in R, coloured by direction
//   • trailing    — the 02-status-badges widget (AppBadge) as the trailing slot
//
// Money direction drives BOTH the sign glyph and the colour, straight from the
// "signal money direction" semantic tokens:
//   amount > 0 → '+'  · t.positive (a credit / money in)
//   amount < 0 → '−'  · t.negative (a charge / money owed)   ('−' is U+2212)
//   amount = 0 →  ''  · onSurface  (neutral)
// The caller owns the sign convention; this widget only renders it correctly.
// Nothing is hardcoded — every colour, size, and gap comes from the theme layer.
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'app_badge.dart';

class AppBillRow extends StatelessWidget {
  const AppBillRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    this.onTap,
  });

  /// Leading glyph shown in the icon tile — pass a Lucide icon
  /// (e.g. `LucideIcons.droplet`).
  final IconData icon;
  final String title;
  final String subtitle;

  /// Signed amount in Rand. Positive renders as a green '+' credit, negative as
  /// a red '−' charge — see the file header for the direction → token mapping.
  final double amount;

  /// Trailing status badge variant (the `02-status-badges` widget).
  final AppBadgeVariant status;

  /// Optional row tap — to a bill detail. Omit for a non-interactive row.
  final VoidCallback? onTap;

  /// The signed money string: sign glyph + 'R' + space-grouped integer + '.dd'.
  /// E.g. `1250.0 → '+R 1 250.00'`, `-842.5 → '−R 842.50'`, `0 → 'R 0.00'`.
  /// Space thousands separator is the SA convention; the point decimal matches
  /// the rest of the kit (see ErAmountDisplay).
  static String formatSignedAmount(double amount, {String symbol = 'R'}) {
    final sign = amount > 0
        ? '+'
        : amount < 0
            ? '−' // true minus, not a hyphen
            : '';
    final fixed = amount.abs().toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final grouped = _groupThousands(fixed.substring(0, dot));
    return '$sign$symbol $grouped${fixed.substring(dot)}';
  }

  // Insert a space every three digits from the right: '1250' → '1 250'.
  static String _groupThousands(String digits) {
    final buf = StringBuffer();
    final n = digits.length;
    for (var i = 0; i < n; i++) {
      if (i > 0 && (n - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  /// The amount's colour, by money direction — from the semantic tokens.
  static Color amountColor(BuildContext context, double amount) {
    final theme = Theme.of(context);
    final t = theme.extension<EasyRatesTokens>()!;
    if (amount > 0) return t.positive;
    if (amount < 0) return t.negative;
    return theme.colorScheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;

    // Icon tile — a rounded sunken square with a centred muted glyph.
    final iconTile = Container(
      width: t.s12, // 48 square
      height: t.s12,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer, // sunken (light) / inkSurface (dark)
        borderRadius: t.radiusMd, // 16 — rounded square
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: t.iconMd, color: scheme.onSurfaceVariant),
    );

    // Signed money figure — Space Grotesk tabular (same base as ErAmountDisplay).
    final amountStyle = textTheme.displayLarge!.copyWith(
      fontSize: AppTextStyles.moneyBaseSize, // 15
      fontWeight: FontWeight.w700,
      color: amountColor(context, amount),
    );

    final row = Row(
      children: [
        iconTile,
        SizedBox(width: t.s3), // 12
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: t.s1), // 4
              Text(
                subtitle,
                style: textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(width: t.s3), // 12
        Text(
          formatSignedAmount(amount),
          style: amountStyle,
          maxLines: 1,
          softWrap: false,
        ),
        SizedBox(width: t.s3), // 12 — amount → trailing badge
        AppBadge(status),
      ],
    );

    return Semantics(
      button: onTap != null,
      label: '$title, ${formatSignedAmount(amount)}',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: t.listTilePadding, // h16 / v12
          child: row,
        ),
      ),
    );
  }
}
