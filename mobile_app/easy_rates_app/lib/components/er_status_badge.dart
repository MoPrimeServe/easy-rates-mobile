import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum ErStatus { paid, overdue, partial, unknown }

class ErStatusBadge extends StatelessWidget {
  const ErStatusBadge(this.status, {super.key});

  final ErStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;

    final (label, color) = switch (status) {
      ErStatus.paid    => ('Paid',     t.positive),
      ErStatus.overdue => ('Overdue',  colorScheme.error),
      ErStatus.partial => ('Partial',  t.warning),
      ErStatus.unknown => ('Unknown',  t.fgMuted),
    };

    return Container(
      padding: t.badgePadding,
      decoration: BoxDecoration(
        color: color.withAlpha(AppColors.tintFillAlpha),
        borderRadius: t.radiusPill,
        border: Border.all(color: color.withAlpha(AppColors.tintBorderAlpha)),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall!.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
