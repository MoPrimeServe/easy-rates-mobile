import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Two-number "strike stack" — shows current amount over a crossed-out previous
/// amount. Pass [previous] as null to show a single amount.
class ErAmountDisplay extends StatelessWidget {
  const ErAmountDisplay({
    super.key,
    required this.current,
    this.previous,
    this.currencySymbol = 'R',
    this.label,
  });

  final double current;
  final double? previous;
  final String currencySymbol;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    // Base mono style: Space Grotesk tabular figures, inherited from displayLarge.
    // Theme-aware colour comes from displayLarge; only the off-ramp money sizes
    // are pulled from the theme layer (AppTextStyles money sub-scale).
    final monoBase = textTheme.displayLarge!.copyWith(
      fontSize: AppTextStyles.moneyBaseSize, fontWeight: FontWeight.w500,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: textTheme.labelSmall),
          SizedBox(height: t.s1),
        ],
        if (previous != null)
          Text(
            '$currencySymbol ${previous!.toStringAsFixed(2)}',
            style: monoBase.copyWith(
              decoration: TextDecoration.lineThrough,
              color: t.fgMuted,
              fontSize: AppTextStyles.moneyStruckSize,
            ),
          ),
        Text(
          '$currencySymbol ${current.toStringAsFixed(2)}',
          style: monoBase.copyWith(
            fontSize: AppTextStyles.moneyEmphasisSize,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
