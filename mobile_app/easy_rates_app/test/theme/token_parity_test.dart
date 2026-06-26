import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';
import 'package:easy_rates_app/theme/app_theme.dart';

// Parity contract: every spec token is present in BOTH light and dark.
//
//   • Brightness-INDEPENDENT tokens (spacing, radii, icon sizes) must be byte-
//     identical across the two sets — a value that drifts between modes is a bug.
//   • Brightness-DEPENDENT tokens (the palette) legitimately differ, so "parity"
//     means the role is DEFINED in both. The const ColorScheme / EasyRatesTokens
//     constructors make every field required, so this is structurally guaranteed;
//     the assertions below pin the spec values that must survive in each mode.
//   • The type ramp is built once and shared, so both ThemeData carry identical
//     sizes — asserted here against the spec set {58,40,30,24,17,15,13,11}.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const l = EasyRatesTokens.light;
  const d = EasyRatesTokens.dark;

  // ── Brightness-independent tokens must be IDENTICAL in light & dark ─────────
  group('parity — brightness-independent tokens are identical', () {
    test('spacing scale (4px grid) identical', () {
      expect([d.s1, d.s2, d.s3, d.s4, d.s5, d.s6, d.s8, d.s12],
             [l.s1, l.s2, l.s3, l.s4, l.s5, l.s6, l.s8, l.s12]);
      // and matches the spec grid
      expect([l.s1, l.s2, l.s3, l.s4, l.s5, l.s6, l.s8, l.s12],
             [4, 8, 12, 16, 20, 24, 32, 48]);
    });

    test('radius scale (8/16/22/28/36/pill) identical', () {
      expect([d.rSm, d.rMd, d.rLg, d.rXl, d.r2xl, d.rPill],
             [l.rSm, l.rMd, l.rLg, l.rXl, l.r2xl, l.rPill]);
      expect([l.rSm, l.rMd, l.rLg, l.rXl, l.r2xl, l.rPill],
             [8, 16, 22, 28, 36, 9999]);
    });

    test('icon size tokens (18/22/24) identical', () {
      expect([d.iconSm, d.iconMd, d.iconLg], [l.iconSm, l.iconMd, l.iconLg]);
      expect([l.iconSm, l.iconMd, l.iconLg], [18, 22, 24]);
    });

    test('border ring widths (1/2) identical', () {
      expect([d.borderWidth, d.borderWidthFocus],
             [l.borderWidth, l.borderWidthFocus]);
      expect([l.borderWidth, l.borderWidthFocus], [1, 2]);
    });

    test('ink-nav tokens identical (bar is dark in both modes)', () {
      expect(d.ink900, l.ink900);
      expect(d.onInkMuted, l.onInkMuted);
      expect(l.ink900, const Color(0xFF0A0B0A));     // deepest ink
      expect(l.onInkMuted, const Color(0xFFAFB4AC)); // muted light on ink
    });
  });

  // ── Brightness-dependent tokens: the spec role is present in BOTH ───────────
  group('parity — palette roles defined in both modes', () {
    test('semantic accents present (and differ for dark legibility)', () {
      // Present in both:
      for (final c in [l.positive, l.negative, l.warning, l.info,
                       d.positive, d.negative, d.warning, d.info]) {
        expect(c, isA<Color>());
      }
      // Light spec values:
      expect(l.positive, const Color(0xFF1F9D57));
      expect(l.negative, const Color(0xFFE2473D));
      // Dark lifts them:
      expect(d.positive, const Color(0xFF49C27E));
      expect(d.negative, const Color(0xFFFF8A80));
    });

    test('brand lime ramp + ink neutrals present in both', () {
      for (final c in [l.limePress, l.limeHover, l.limeTint,
                       l.inkSurface, l.hairline, l.fgMuted, l.appBg, l.sunken,
                       d.limePress, d.limeHover, d.limeTint,
                       d.inkSurface, d.hairline, d.fgMuted, d.appBg, d.sunken]) {
        expect(c, isA<Color>());
      }
    });
  });

  // ── ColorScheme: lime/sky brand accents retained across both modes ──────────
  group('parity — ColorScheme brand accents retained', () {
    test('primary lime-500 + secondary sky-500 in both schemes', () {
      expect(easyRatesColorScheme.primary, const Color(0xFFE1FB8E));
      expect(easyRatesDarkColorScheme.primary, const Color(0xFFE1FB8E));
      expect(easyRatesColorScheme.secondary, const Color(0xFF3E7BD8));
      expect(easyRatesDarkColorScheme.secondary, const Color(0xFF3E7BD8));
    });
  });

  // ── Type ramp: built once, identical across both ThemeData ──────────────────
  group('parity — type ramp identical & spec-complete in both themes', () {
    late ThemeData light;
    late ThemeData dark;
    setUp(() {
      light = buildEasyRatesTheme();
      dark = buildEasyRatesDarkTheme();
    });

    List<double?> ramp(TextTheme tt) => [
          tt.displayLarge!.fontSize,
          tt.headlineLarge!.fontSize,
          tt.headlineMedium!.fontSize,
          tt.headlineSmall!.fontSize,
          tt.titleMedium!.fontSize,
          tt.bodyMedium!.fontSize,
          tt.bodySmall!.fontSize,
          tt.labelSmall!.fontSize,
        ];

    test('spec ramp sizes {58,40,30,24,17,15,13,11} in light', () {
      expect(ramp(light.textTheme), [58, 40, 30, 24, 17, 15, 13, 11]);
    });
    test('dark ramp identical to light', () {
      expect(ramp(dark.textTheme), ramp(light.textTheme));
    });
  });
}
