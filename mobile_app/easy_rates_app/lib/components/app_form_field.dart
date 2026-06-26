// app_form_field.dart — a token-driven text field with a leading-glyph slot and
// four ring states, all resolved from the design system.
//
//   resting   → hairline ring,  muted glyph/label
//   focused   → sky-500 ring (2px), sky glyph/label   ← AppFieldRing.resolve
//   error     → negative ring,   red glyph/label + helper
//   disabled  → muted ring on a sunken fill, faded content
//
// The leading slot takes EITHER a Lucide glyph (`icon`) or a short textual
// marker (`prefixText`, e.g. '#' for an account, 'R' for an amount). Every
// painted value — ring colour/width, fill, glyph, text, radius, padding — comes
// from AppFieldRing.resolve(); nothing is hardcoded here.
import 'package:flutter/material.dart';
import '../theme/theme.dart';

// The resolved visual spec for the field in one state. Pure data.
@immutable
class AppFieldRing {
  const AppFieldRing({
    required this.border,
    required this.borderWidth,
    required this.fill,
    required this.accent,
    required this.textColor,
    required this.hintColor,
    required this.errorColor,
    required this.radius,
    required this.padding,
    required this.glyphSize,
    required this.gap,
    required this.stackGap,
    required this.inputStyle,
    required this.labelStyle,
    required this.helperStyle,
  });

  final Color border;        // the ring
  final double borderWidth;  // 1 rest/error/disabled · 2 focus
  final Color fill;          // field background
  final Color accent;        // leading glyph + label + cursor (state cue)
  final Color textColor;     // typed text
  final Color hintColor;     // placeholder
  final Color errorColor;    // helper text under the field
  final BorderRadius radius;
  final EdgeInsetsGeometry padding;
  final double glyphSize;
  final double gap;          // leading glyph → input
  final double stackGap;     // label↕field↕helper
  final TextStyle inputStyle;
  final TextStyle labelStyle;
  final TextStyle helperStyle;

  // Maps interaction state onto tokens. Precedence: disabled ▸ error ▸ focus ▸
  // rest — the strongest active state wins the ring.
  factory AppFieldRing.resolve(
    BuildContext context, {
    required bool focused,
    required bool hasError,
    required bool disabled,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = theme.extension<EasyRatesTokens>()!;

    Color border;
    Color accent;
    if (disabled) {
      border = scheme.outlineVariant;
      accent = scheme.onSurface.withAlpha(AppColors.disabledContentAlpha);
    } else if (hasError) {
      border = scheme.error;          // negative
      accent = scheme.error;
    } else if (focused) {
      border = scheme.secondary;      // sky-500
      accent = scheme.secondary;
    } else {
      border = t.hairline;
      accent = t.fgMuted;
    }

    return AppFieldRing(
      border: border,
      borderWidth: (focused && !disabled) ? t.borderWidthFocus : t.borderWidth,
      fill: disabled ? t.sunken : scheme.surface,
      accent: accent,
      textColor: disabled
          ? scheme.onSurface.withAlpha(AppColors.disabledContentAlpha)
          : scheme.onSurface,
      hintColor: t.fgMuted,
      errorColor: scheme.error,
      radius: t.radiusMd,                                              // 16
      padding: EdgeInsets.symmetric(horizontal: t.s4, vertical: t.s3), // 16/12
      glyphSize: t.iconSm,                                             // 18
      gap: t.s3,                                                       // 12
      stackGap: t.s2,                                                  // 8
      inputStyle: theme.textTheme.bodyLarge!,    // 17 regular
      labelStyle: theme.textTheme.labelMedium!,  // 13 — field label
      helperStyle: theme.textTheme.bodySmall!,   // 13 — helper / error
    );
  }
}

class AppFormField extends StatefulWidget {
  const AppFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.icon,
    this.prefixText,
    this.errorText,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;

  /// Leading Lucide glyph (e.g. `LucideIcons.hash`). Takes priority over [prefixText].
  final IconData? icon;

  /// OR a short leading marker — '#' for an account, 'R' for an amount.
  final String? prefixText;

  final String? errorText;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppFormField> createState() => _AppFormFieldState();
}

class _AppFormFieldState extends State<AppFormField> {
  FocusNode? _internal;
  FocusNode get _node => widget.focusNode ?? (_internal ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {}); // repaint the ring on focus enter/leave
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ring = AppFieldRing.resolve(
      context,
      focused: _node.hasFocus,
      hasError: widget.errorText != null,
      disabled: !widget.enabled,
    );

    Widget? leading;
    if (widget.icon != null) {
      leading = Icon(widget.icon, size: ring.glyphSize, color: ring.accent);
    } else if (widget.prefixText != null) {
      leading = Text(
        widget.prefixText!,
        style: ring.inputStyle.copyWith(
          color: ring.accent,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: ring.labelStyle.copyWith(color: ring.accent)),
          SizedBox(height: ring.stackGap),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: ring.padding,
          decoration: BoxDecoration(
            color: ring.fill,
            borderRadius: ring.radius,
            border: Border.all(color: ring.border, width: ring.borderWidth),
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading, SizedBox(width: ring.gap)],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                  cursorColor: ring.accent,
                  style: ring.inputStyle.copyWith(color: ring.textColor),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: ring.inputStyle.copyWith(color: ring.hintColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.errorText != null) ...[
          SizedBox(height: ring.stackGap),
          Text(widget.errorText!,
              style: ring.helperStyle.copyWith(color: ring.errorColor)),
        ],
      ],
    );
  }
}
