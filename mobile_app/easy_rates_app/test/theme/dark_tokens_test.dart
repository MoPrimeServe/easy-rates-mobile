import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';
import 'package:easy_rates_app/theme/theme_controller.dart';

// This suite asserts the dark token *data* — the const ColorScheme and
// EasyRatesTokens values — plus the ThemeController. The theme *assembly*
// (buildEasyRatesDarkTheme, fonts and all) is covered separately in
// app_dark_theme_test.dart; keeping this suite to pure data keeps it fast and
// font-free.
void main() {
  // ── ColorScheme ───────────────────────────────────────────────────────────
  group('easyRatesDarkColorScheme — dark values', () {
    test('brightness is dark', () {
      expect(easyRatesDarkColorScheme.brightness, Brightness.dark);
    });
    test('primary stays lime-500 #E1FB8E (accent retained)', () {
      expect(easyRatesDarkColorScheme.primary, const Color(0xFFE1FB8E));
    });
    test('onPrimary is ink-900 #0A0B0A', () {
      expect(easyRatesDarkColorScheme.onPrimary, const Color(0xFF0A0B0A));
    });
    test('secondary stays sky-500 #3E7BD8 (accent retained)', () {
      expect(easyRatesDarkColorScheme.secondary, const Color(0xFF3E7BD8));
    });
    test('error is lifted negative #FF8A80', () {
      expect(easyRatesDarkColorScheme.error, const Color(0xFFFF8A80));
    });
    test('surface is the dark paper inkSurface #161816', () {
      expect(easyRatesDarkColorScheme.surface, const Color(0xFF161816));
    });
    test('surfaceDim is ink-900 #0A0B0A', () {
      expect(easyRatesDarkColorScheme.surfaceDim, const Color(0xFF0A0B0A));
    });
    test('onSurface is light ink #E3E5DF', () {
      expect(easyRatesDarkColorScheme.onSurface, const Color(0xFFE3E5DF));
    });
  });

  // ── Spacing & radii — brightness-independent, must match light ─────────────
  group('EasyRatesTokens.dark — spacing & radii equal light', () {
    const d = EasyRatesTokens.dark;
    const l = EasyRatesTokens.light;
    test('spacing scale identical to light', () {
      expect(d.s1, l.s1);
      expect(d.s2, l.s2);
      expect(d.s3, l.s3);
      expect(d.s4, l.s4);
      expect(d.s5, l.s5);
      expect(d.s6, l.s6);
      expect(d.s8, l.s8);
      expect(d.s12, l.s12);
    });
    test('radius scale identical to light', () {
      expect(d.rSm, l.rSm);
      expect(d.rMd, l.rMd);
      expect(d.rLg, l.rLg);
      expect(d.rXl, l.rXl);
      expect(d.r2xl, l.r2xl);
      expect(d.rPill, l.rPill);
    });
  });

  // ── Neutrals invert onto the ink ramp ──────────────────────────────────────
  group('EasyRatesTokens.dark — ink neutrals', () {
    const t = EasyRatesTokens.dark;
    test('appBg is ink-900 #0A0B0A', () {
      expect(t.appBg, const Color(0xFF0A0B0A));
    });
    test('sunken is #121412', () {
      expect(t.sunken, const Color(0xFF121412));
    });
    test('fgMuted is lifted to #AFB4AC', () {
      expect(t.fgMuted, const Color(0xFFAFB4AC));
    });
    test('inkSurface stays #161816 (same in both modes)', () {
      expect(t.inkSurface, const Color(0xFF161816));
    });
    test('hairline stays #2A2E2A (same in both modes)', () {
      expect(t.hairline, const Color(0xFF2A2E2A));
    });
  });

  // ── Semantic & brand accents lift for dark legibility ──────────────────────
  group('EasyRatesTokens.dark — semantic & brand accents', () {
    const t = EasyRatesTokens.dark;
    test('positive lifts to #49C27E', () {
      expect(t.positive, const Color(0xFF49C27E));
    });
    test('negative lifts to #FF8A80', () {
      expect(t.negative, const Color(0xFFFF8A80));
    });
    test('warning lifts to #F0B868', () {
      expect(t.warning, const Color(0xFFF0B868));
    });
    test('info lifts to #6FA0E6', () {
      expect(t.info, const Color(0xFF6FA0E6));
    });
    test('limeTint becomes the deep-lime fill #42511D', () {
      expect(t.limeTint, const Color(0xFF42511D));
    });
  });

  // ── ThemeController — the brightness switch ────────────────────────────────
  group('ThemeController — ThemeMode toggle', () {
    test('defaults to ThemeMode.system', () {
      expect(ThemeController().mode, ThemeMode.system);
    });
    test('first toggle lands on dark', () {
      final c = ThemeController();
      c.toggle();
      expect(c.mode, ThemeMode.dark);
      expect(c.isDark, isTrue);
    });
    test('toggling again returns to light', () {
      final c = ThemeController()..toggle(); // -> dark
      c.toggle(); // -> light
      expect(c.mode, ThemeMode.light);
      expect(c.isDark, isFalse);
    });
    test('setMode notifies listeners on change', () {
      final c = ThemeController();
      var notified = 0;
      c.addListener(() => notified++);
      c.setMode(ThemeMode.dark);
      expect(notified, 1);
    });
    test('setMode to the current mode does not notify', () {
      final c = ThemeController(initial: ThemeMode.dark);
      var notified = 0;
      c.addListener(() => notified++);
      c.setMode(ThemeMode.dark);
      expect(notified, 0);
    });
  });
}
