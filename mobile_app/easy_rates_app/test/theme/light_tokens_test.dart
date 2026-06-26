import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

void main() {
  // Binding must be ready before google_fonts touches ServicesBinding.
  // allowRuntimeFetching = false is safe here because the fonts are bundled
  // under assets/fonts/ — no network request is ever made in tests.
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // ── ColorScheme ───────────────────────────────────────────────────────────
  group('easyRatesColorScheme — Mohapi V1 light values', () {
    test('primary is lime-500 #E1FB8E', () {
      expect(easyRatesColorScheme.primary, const Color(0xFFE1FB8E));
    });
    test('onPrimary is ink-900 #0A0B0A', () {
      expect(easyRatesColorScheme.onPrimary, const Color(0xFF0A0B0A));
    });
    test('secondary is sky-500 #3E7BD8', () {
      expect(easyRatesColorScheme.secondary, const Color(0xFF3E7BD8));
    });
    test('brightness is light', () {
      expect(easyRatesColorScheme.brightness, Brightness.light);
    });
    test('error is negative #E2473D', () {
      expect(easyRatesColorScheme.error, const Color(0xFFE2473D));
    });
    test('surface is paper #FFFFFF', () {
      expect(easyRatesColorScheme.surface, const Color(0xFFFFFFFF));
    });
    test('onSurface is fg-body #2B2F2B', () {
      expect(easyRatesColorScheme.onSurface, const Color(0xFF2B2F2B));
    });
  });

  // ── Spacing scale ─────────────────────────────────────────────────────────
  group('EasyRatesTokens.light — 4px spacing scale', () {
    const t = EasyRatesTokens.light;
    test('s1=4  s2=8  s3=12  s4=16', () {
      expect(t.s1,  4.0);
      expect(t.s2,  8.0);
      expect(t.s3,  12.0);
      expect(t.s4,  16.0);
    });
    test('s5=20  s6=24  s8=32  s12=48', () {
      expect(t.s5,  20.0);
      expect(t.s6,  24.0);
      expect(t.s8,  32.0);
      expect(t.s12, 48.0);
    });
  });

  // ── Radius scale ──────────────────────────────────────────────────────────
  group('EasyRatesTokens.light — radius scale', () {
    const t = EasyRatesTokens.light;
    test('rSm=8  rMd=16  rLg=22  rXl=28  r2xl=36  rPill=9999', () {
      expect(t.rSm,   8.0);
      expect(t.rMd,   16.0);
      expect(t.rLg,   22.0);
      expect(t.rXl,   28.0);
      expect(t.r2xl,  36.0);
      expect(t.rPill, 9999.0);
    });
  });

  // ── Semantic colors ───────────────────────────────────────────────────────
  group('EasyRatesTokens.light — semantic colors', () {
    const t = EasyRatesTokens.light;
    test('positive (success) is #1F9D57', () {
      expect(t.positive, const Color(0xFF1F9D57));
    });
    test('negative (error) is #E2473D', () {
      expect(t.negative, const Color(0xFFE2473D));
    });
    test('warning is #E0982F', () {
      expect(t.warning, const Color(0xFFE0982F));
    });
    test('info is sky-500 #3E7BD8', () {
      expect(t.info, const Color(0xFF3E7BD8));
    });
    test('appBg is #F4F6F1', () {
      expect(t.appBg, const Color(0xFFF4F6F1));
    });
    test('fgMuted is #6C726B', () {
      expect(t.fgMuted, const Color(0xFF6C726B));
    });
  });

  // ── TextTheme — spec ramp 58/40/30/24/17/15/13/11 ─────────────────────────
  // buildEasyRatesTextTheme() calls google_fonts, which makes async HTTP
  // requests. Calling it inside setUp (not at group-scope) keeps it inside
  // the test zone so those requests are tracked and cleaned up properly.
  group('buildEasyRatesTextTheme — spec ramp sizes', () {
    late TextTheme tt;
    setUp(() { tt = buildEasyRatesTextTheme(); });

    test('displayLarge  = 58', () => expect(tt.displayLarge!.fontSize,  58));
    test('headlineLarge = 40 (spec h1)', () => expect(tt.headlineLarge!.fontSize, 40));
    test('headlineMedium = 30 (spec h2)', () => expect(tt.headlineMedium!.fontSize, 30));
    test('headlineSmall  = 24 (spec h3)', () => expect(tt.headlineSmall!.fontSize,  24));
    test('titleMedium   = 17', () => expect(tt.titleMedium!.fontSize, 17));
    test('bodyMedium    = 15 (spec body)', () => expect(tt.bodyMedium!.fontSize, 15));
    test('bodySmall     = 13', () => expect(tt.bodySmall!.fontSize,  13));
    test('labelSmall    = 11', () => expect(tt.labelSmall!.fontSize,  11));
  });

  // ── ThemeExtension contract ────────────────────────────────────────────────
  group('EasyRatesTokens.copyWith — ThemeExtension contract', () {
    const t = EasyRatesTokens.light;
    test('copyWith overrides one field, leaves others unchanged', () {
      final modified = t.copyWith(s4: 999);
      expect(modified.s4, 999.0);
      expect(modified.s1, t.s1);
    });
    test('lerp(null, 0) returns original', () {
      expect(t.lerp(null, 0), t);
    });
    test('lerp(null, 1) returns original', () {
      expect(t.lerp(null, 1), t);
    });
  });
}
