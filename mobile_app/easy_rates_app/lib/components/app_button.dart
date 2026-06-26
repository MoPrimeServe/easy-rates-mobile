// app_button.dart — a token-driven button with three variants.
//
//   primary   → lime pill   (colorScheme.primary / onPrimary)
//   secondary → ink pill     (colorScheme.inverseSurface / onInverseSurface)
//   outline   → outline ring (transparent fill, onSurface label, outline border)
//
// Every painted value comes from AppButtonVariant.spec(): colours, radius,
// padding, icon size, gap, text style, and the pressed/disabled state layers.
// Nothing is hardcoded here — change a token in the theme layer and the button
// follows. See the `spec()` method below for the variant → token mapping.
import 'package:flutter/material.dart';
import '../theme/theme.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outline;

  // Maps this variant (+ interaction state) onto resolved design-system tokens.
  // The widget paints exactly what this returns — the single source of truth for
  // how a button looks. `pressed` / `disabled` select the state-layer tokens.
  AppButtonSpec spec(
    BuildContext context, {
    bool pressed = false,
    bool disabled = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = theme.extension<EasyRatesTokens>()!;

    // ── Geometry — identical across variants, all from tokens ────────────────
    final radius = t.radiusPill;                                     // pill
    final padding = EdgeInsets.symmetric(horizontal: t.s5, vertical: t.s3); // 20/12
    final minHeight = t.s12;                                         // 48 tap target
    final iconSize = t.iconSm;                                       // 18 leading glyph
    final gap = t.s2;                                                // 8 icon→label
    final baseText = theme.textTheme.titleMedium!;

    // ── Resting fill / foreground / ring per variant ─────────────────────────
    Color? fill;          // null = no fill (outline at rest)
    Color foreground;
    BorderSide? side;     // null = no ring
    switch (this) {
      case AppButtonVariant.primary: // lime pill
        fill = pressed ? t.limePress : scheme.primary;
        foreground = scheme.onPrimary;
        side = null;
      case AppButtonVariant.secondary: // ink pill
        fill = scheme.inverseSurface;
        foreground = scheme.onInverseSurface;
        if (pressed) {
          // Darken the ink by laying its own foreground over it at the press alpha.
          fill = Color.alphaBlend(
            foreground.withAlpha(AppColors.pressOverlayAlpha), fill);
        }
        side = null;
      case AppButtonVariant.outline: // outline ring
        foreground = scheme.onSurface;
        fill = pressed
            ? scheme.onSurface.withAlpha(AppColors.pressOverlayAlpha)
            : null;
        side = BorderSide(color: scheme.outline);
    }

    // ── Disabled overlays everything (Material 12% container / 38% content) ───
    if (disabled) {
      foreground = scheme.onSurface.withAlpha(AppColors.disabledContentAlpha);
      switch (this) {
        case AppButtonVariant.outline:
          fill = null;
          side = BorderSide(
            color: scheme.onSurface.withAlpha(AppColors.disabledContainerAlpha));
        case AppButtonVariant.primary:
        case AppButtonVariant.secondary:
          fill = scheme.onSurface.withAlpha(AppColors.disabledContainerAlpha);
          side = null;
      }
    }

    return AppButtonSpec(
      fill: fill,
      foreground: foreground,
      side: side,
      radius: radius,
      padding: padding,
      minHeight: minHeight,
      iconSize: iconSize,
      gap: gap,
      textStyle: baseText.copyWith(color: foreground),
    );
  }
}

// The resolved visual spec for one button in one state. Pure data — produced by
// AppButtonVariant.spec(), consumed by AppButton.build().
@immutable
class AppButtonSpec {
  const AppButtonSpec({
    required this.fill,
    required this.foreground,
    required this.side,
    required this.radius,
    required this.padding,
    required this.minHeight,
    required this.iconSize,
    required this.gap,
    required this.textStyle,
  });

  final Color? fill;               // null → no fill painted
  final Color foreground;          // label + icon colour
  final BorderSide? side;          // null → no ring
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double minHeight;
  final double iconSize;
  final double gap;
  final TextStyle textStyle;
}

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// Optional leading glyph — pass a Lucide icon (e.g. `LucideIcons.arrowRight`).
  final IconData? icon;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final spec = widget.variant.spec(
      context,
      pressed: _pressed,
      disabled: disabled,
    );

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: spec.iconSize, color: spec.foreground),
          SizedBox(width: spec.gap),
        ],
        Text(widget.label, style: spec.textStyle),
      ],
    );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => _setPressed(true),
        onTapUp: disabled ? null : (_) => _setPressed(false),
        onTapCancel: disabled ? null : () => _setPressed(false),
        onTap: disabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          constraints: BoxConstraints(minHeight: spec.minHeight),
          padding: spec.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: spec.fill,
            borderRadius: spec.radius,
            border: spec.side == null ? null : Border.fromBorderSide(spec.side!),
          ),
          child: content,
        ),
      ),
    );
  }
}
