// app_spacing.dart — named aliases that derive directly from EasyRatesTokens.light.
// Single source of truth: change a value in EasyRatesTokens.light and it propagates here.
// Use t.screenPadding / t.cardPadding from the ThemeExtension in widget code when possible;
// these statics exist for the rare cases without a BuildContext (e.g. static const widgets).
import 'package:flutter/material.dart';

abstract final class AppSpacing {
  // Scalar aliases — must be literals in Dart const context; values mirror EasyRatesTokens.light.
  // Keep these in sync with EasyRatesTokens.light manually: s1/s2/s4/s6/s8/s12.
  static const double xs  = 4;   // s1
  static const double sm  = 8;   // s2
  static const double md  = 16;  // s4
  static const double lg  = 24;  // s6
  static const double xl  = 32;  // s8
  static const double xxl = 48;  // s12

  // EdgeInsets must remain literal const — EdgeInsets.symmetric/all are const-constructible
  // but cannot reference instance fields in a const initialiser.
  // Values match EasyRatesTokens.light.screenPadding and .cardPadding exactly.
  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16); // s5 / s4
  static const EdgeInsets cardPadding = EdgeInsets.all(20); // s5
  static const EdgeInsets listTilePadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 12);   // s4 / s3
}
