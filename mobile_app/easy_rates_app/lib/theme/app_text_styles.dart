// app_text_styles.dart — static aliases over the Mohapi V1 type ramp.
// Every size is from the spec ramp: {58, 40, 30, 24, 17, 15, 13, 11}.
// SOURCE: buildEasyRatesTextTheme() in er_tokens.dart — keep in sync.
// Prefer Theme.of(context).textTheme in new widget code.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

abstract final class AppTextStyles {
  // ── Space Grotesk — display / headline zone (★ = Mohapi V1 spec) ────────
  // ★ 58 — money display; tabular figures keep digits aligned.
  static TextStyle get displayLarge => GoogleFonts.spaceGrotesk(
        fontSize: 58, fontWeight: FontWeight.w700,
        letterSpacing: -1.0, height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.textPrimary,
      );

  // ★ 40 — h1 / large section header.
  static TextStyle get displayMedium => GoogleFonts.spaceGrotesk(
        fontSize: 40, fontWeight: FontWeight.w700,
        letterSpacing: -0.5, color: AppColors.textPrimary,
      );

  // ★ 24 — h3 / AppBar title.
  static TextStyle get titleLarge => GoogleFonts.spaceGrotesk(
        fontSize: 24, fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  // ── Manrope — title / body / label zone (★ = Mohapi V1 spec) ───────────
  // ★ 17 — component titles, button labels.
  static TextStyle get titleMedium => GoogleFonts.manrope(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // ★ 17 regular — larger body context (title size, body weight). Was 16 — fixed.
  static TextStyle get bodyLarge => GoogleFonts.manrope(
        fontSize: 17, fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  // ★ 15 — body text.
  static TextStyle get bodyMedium => GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  // ★ 13 — small / secondary body.
  static TextStyle get bodySmall => GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  // ★ 15 bold — button labels (matches labelLarge in TextTheme).
  static TextStyle get labelLarge => GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // ★ 11 — overline / badge. Uppercase applied at widget, not here.
  static TextStyle get caption => GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 0.8, color: AppColors.textSecondary,
      );

  // Money / account numbers — Space Grotesk tabular (spec: displayLarge family).
  static TextStyle get mono => GoogleFonts.spaceGrotesk(
        fontSize: moneyBaseSize, fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: AppColors.textPrimary,
      );

  // ── Numeric / money sub-scale (Space Grotesk tabular) ────────────────────
  // Financial figures use their own sizes, deliberately OFF the text ramp:
  // the Material ramp has no small Space-Grotesk-tabular slot, so the strike-
  // stack money display defines its own scale here. Widgets derive theme-aware
  // colour from textTheme and pull only the size from these constants — keeping
  // the literals in the theme layer rather than scattered across components.
  static const double moneyStruckSize   = 12; // struck-through "was" figure
  static const double moneyBaseSize     = 15; // resting figure (== body size)
  static const double moneyEmphasisSize = 22; // headline "amount due" figure
}
