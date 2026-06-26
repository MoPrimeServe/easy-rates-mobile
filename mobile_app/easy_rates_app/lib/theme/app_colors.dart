// app_colors.dart — static aliases over the Mohapi V1 canonical palette.
// SOURCE: EasyRatesTokens.light + easyRatesColorScheme in er_tokens.dart.
// These exist so widget code that cannot use BuildContext still compiles cleanly.
// Prefer reading Theme.of(context) / EasyRatesTokens in new widget code.
import 'package:flutter/material.dart';

abstract final class AppColors {
  // Brand (Mohapi V1 lime palette)
  static const Color primary      = Color(0xFFE1FB8E); // lime-500
  static const Color primaryLight = Color(0xFFCDEF45); // limeHover
  static const Color primaryDark  = Color(0xFFB6DE2E); // limePress

  static const Color accent = Color(0xFF3E7BD8); // sky-500

  // Surfaces
  static const Color background     = Color(0xFFF4F6F1); // appBg
  static const Color surface        = Color(0xFFFFFFFF); // paper
  static const Color surfaceVariant = Color(0xFFECEEE7); // sunken

  // Semantic status
  static const Color success = Color(0xFF1F9D57); // positive
  static const Color warning = Color(0xFFE0982F); // warning
  static const Color error   = Color(0xFFE2473D); // negative
  static const Color info    = Color(0xFF3E7BD8); // sky-500

  // Text
  static const Color textPrimary   = Color(0xFF2B2F2B); // onSurface / fg body
  static const Color textSecondary = Color(0xFF6C726B); // fgMuted
  static const Color textDisabled  = Color(0xFFB0B8AF); // fgMuted lightened

  // Divider (not in token store — derived from sunken, lighter)
  static const Color divider = Color(0xFFE4E6DF);

  // Tint strengths for semantic fills (status-pill backgrounds & borders).
  // A semantic colour (positive/warning/…) is composited over the surface at
  // these alphas to make a soft fill + a slightly stronger hairline. 0–255.
  static const int tintFillAlpha   = 26; // ~10% — pill background
  static const int tintBorderAlpha = 77; // ~30% — pill border

  // State-layer alphas (Material state opacities), tokenised so widget state
  // styling never hardcodes an alpha. Applied over onSurface / the foreground.
  static const int pressOverlayAlpha      = 31; // ~12% — pressed state layer
  static const int disabledContainerAlpha = 31; // ~12% — disabled fill / ring
  static const int disabledContentAlpha   = 97; // ~38% — disabled label / icon
}
