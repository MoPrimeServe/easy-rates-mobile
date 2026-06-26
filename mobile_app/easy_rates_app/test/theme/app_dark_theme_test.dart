import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';
import 'package:easy_rates_app/theme/app_theme.dart';

// Covers the parametrized theme builder — what buildEasyRates(Dark)Theme wires
// from a (scheme, tokens) pair. This builds the full ThemeData (incl. the
// GoogleFonts TextTheme), which works under `flutter test` because the Space
// Grotesk / Manrope static weights are bundled in assets/fonts/ and resolved
// from the asset manifest (allowRuntimeFetching off → no network).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('buildEasyRatesDarkTheme — dark wiring', () {
    final theme = buildEasyRatesDarkTheme();
    test('carries the dark colorScheme', () {
      expect(theme.colorScheme, easyRatesDarkColorScheme);
    });
    test('brightness is dark', () {
      expect(theme.brightness, Brightness.dark);
    });
    test('scaffold background is ink-900', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0B0A));
    });
    test('EasyRatesTokens extension is the dark set', () {
      expect(theme.extension<EasyRatesTokens>()!.appBg, EasyRatesTokens.dark.appBg);
    });
    test('AppBar is the ink-900 bar with a light label', () {
      final bar = theme.appBarTheme;
      expect(bar.backgroundColor, const Color(0xFF0A0B0A)); // ink-900
      expect(bar.foregroundColor, easyRatesDarkColorScheme.onSurface); // light ink
    });
  });

  group('buildEasyRatesTheme — light still intact', () {
    final theme = buildEasyRatesTheme();
    test('carries the light colorScheme', () {
      expect(theme.colorScheme, easyRatesColorScheme);
    });
    test('brightness is light', () {
      expect(theme.brightness, Brightness.light);
    });
    test('scaffold background is appBg #F4F6F1', () {
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6F1));
    });
    test('AppBar is the inverted inkSurface bar with paper label', () {
      final bar = theme.appBarTheme;
      expect(bar.backgroundColor, const Color(0xFF161816)); // inkSurface
      expect(bar.foregroundColor, easyRatesColorScheme.surface); // paper
    });
  });
}
