// app_theme.dart — assembles one ThemeData from the Mohapi V1 token store.
// SOURCE: learning/easyrates-fullstack capstone (verified). One edit here re-skins
// every widget that reads Theme.of(context) — no widget edits needed.
//
// Component nudges baked in:
//   FilledButton → pill (StadiumBorder), lime fill, ink label
//   CardTheme    → paper surface, rLg (22) radius, zero elevation
//   AppBar       → ink surface, paper text (inverted on lime primary)
import 'package:flutter/material.dart';
import 'er_tokens.dart';

// Light entry-point. Mount via MaterialApp(theme: buildEasyRatesTheme()).
ThemeData buildEasyRatesTheme() =>
    _buildEasyRatesTheme(easyRatesColorScheme, EasyRatesTokens.light);

// Dark entry-point. Mount via MaterialApp(darkTheme: buildEasyRatesDarkTheme()).
ThemeData buildEasyRatesDarkTheme() =>
    _buildEasyRatesTheme(easyRatesDarkColorScheme, EasyRatesTokens.dark);

// Both themes are assembled here from a (scheme, tokens) pair, so the component
// nudges stay byte-identical across brightnesses and only the palette swaps.
//
// Component nudges baked in:
//   FilledButton → pill (StadiumBorder), lime fill, ink label
//   CardTheme    → paper surface, rLg (22) radius, zero elevation
//   AppBar       → the signature inverted "ink" bar (dark in both modes), light label
ThemeData _buildEasyRatesTheme(ColorScheme scheme, EasyRatesTokens t) {
  final textTheme = buildEasyRatesTextTheme();
  final isLight = scheme.brightness == Brightness.light;

  // The AppBar is a dark ink bar in BOTH modes (a deliberate signature): in light
  // it inverts to inkSurface #161816, in dark it sits flush at ink-900. Either way
  // its label must read light — paper in light, light-ink onSurface in dark.
  final inkBarBg = isLight ? t.inkSurface : t.appBg;
  final onInkBar = isLight ? scheme.surface : scheme.onSurface;
  // Light keeps its bespoke hairline-light divider; dark uses the ink hairline.
  final dividerColor = isLight ? const Color(0xFFE4E6DF) : t.hairline;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: t.appBg,
    extensions: [t],
    // Global icon default: Lucide glyphs inherit this size + colour (currentColor)
    // wherever an Icon sets neither. iconMd (22) is the default tier; onSurface is
    // the inherited colour. The Lucide font supplies the 2px stroke intrinsically.
    iconTheme: IconThemeData(size: t.iconMd, color: scheme.onSurface),
    appBarTheme: AppBarTheme(
      backgroundColor: inkBarBg,
      foregroundColor: onInkBar,
      elevation: 0,
      titleTextStyle: textTheme.titleMedium?.copyWith(color: onInkBar),
      // AppBar icons keep the light ink-bar foreground, but adopt the token size.
      iconTheme: IconThemeData(size: t.iconMd, color: onInkBar),
      actionsIconTheme: IconThemeData(size: t.iconMd, color: onInkBar),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: textTheme.titleMedium,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(double.infinity, 48),
        shape: const StadiumBorder(),
        textStyle: textTheme.titleMedium,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(double.infinity, 48),
        side: BorderSide(color: t.hairline),
        shape: const StadiumBorder(),
        textStyle: textTheme.titleMedium,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.rMd),
        borderSide: BorderSide(color: t.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.rMd),
        borderSide: BorderSide(color: scheme.secondary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.rMd),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(t.rMd),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.rLg)),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: dividerColor,
      space: 1,
      thickness: 1,
    ),
  );
}
