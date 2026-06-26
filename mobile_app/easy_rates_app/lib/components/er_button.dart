import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum ErButtonVariant { primary, outlined, ghost }

class ErButton extends StatelessWidget {
  const ErButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ErButtonVariant.primary,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ErButtonVariant variant;
  final Widget? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<EasyRatesTokens>()!;
    // Spinner takes the variant's own foreground so it stays legible: ink on the
    // lime primary fill, onSurface on the surface-coloured outlined/ghost buttons.
    final spinnerColor = variant == ErButtonVariant.primary
        ? colorScheme.onPrimary
        : colorScheme.onSurface;
    final child = loading
        ? SizedBox(
            width: t.iconMd,
            height: t.iconMd,
            child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
          )
        : icon != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon!, SizedBox(width: t.s2), Text(label)],
              )
            : Text(label);

    return switch (variant) {
      ErButtonVariant.primary => ElevatedButton(
          onPressed: loading ? null : onPressed,
          child: child,
        ),
      ErButtonVariant.outlined => OutlinedButton(
          onPressed: loading ? null : onPressed,
          child: child,
        ),
      ErButtonVariant.ghost => TextButton(
          onPressed: loading ? null : onPressed,
          child: child,
        ),
    };
  }
}
