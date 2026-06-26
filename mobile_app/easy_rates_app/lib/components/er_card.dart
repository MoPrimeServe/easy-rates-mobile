import 'package:flutter/material.dart';
import '../theme/theme.dart';

class ErCard extends StatelessWidget {
  const ErCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<EasyRatesTokens>()!;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radiusLg, // match the Card's own rLg (22) corner
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
