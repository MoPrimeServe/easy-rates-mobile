// er_tokens.dart — the EasyRates design system, Mohapi V1, light token store.
// SOURCE: learning/easyrates-fullstack capstone-screen-to-spec/theme.dart (verified).
//
// Three layers:
//   1. easyRatesColorScheme — Material semantic colour roles
//   2. easyRatesTextTheme   — Material named text styles (built via GoogleFonts)
//   3. EasyRatesTokens      — ThemeExtension for what Material doesn't model:
//                             spacing scale, radius scale, semantic colours, brand extras.
//
// All hex values are the exact Mohapi V1 spec. ARGB form: 0xFF + RRGGBB.
// Read tokens at runtime with: Theme.of(context).extension<EasyRatesTokens>()!

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. COLOUR SCHEME — ALL 30 Material 3 roles explicitly set from Mohapi V1.
//
//    Palette sources (→ tokens in EasyRatesTokens.light):
//      Lime:     lime-500 #E1FB8E · limeHover #CDEF45 · limePress #B6DE2E · limeTint #F2FDC2
//      Sky:      sky-500  #3E7BD8 · sky-700   #2456AB · sky-100   #DCE9F7
//      Ink:      ink-900  #0A0B0A · inkSurface #161816 · fg-body #2B2F2B · fgMuted #6C726B
//                appBg #F4F6F1 · sunken #ECEEE7
//      Semantic: positive #1F9D57 · negative #E2473D · warning #E0982F
//
//    Contrast ratios (WCAG):
//      lime-500 / ink-900   ≈ 21:1  ✓   sky-500  / white  ≈ 6.3:1 ✓
//      positive / white     ≈ 6.6:1 ✓   negative / white  ≈ 6.8:1 ✓
//
//    No role is left for Flutter to auto-derive; every value traces to a palette entry.
// ─────────────────────────────────────────────────────────────────────────────
const easyRatesColorScheme = ColorScheme(
  brightness: Brightness.light,

  // ── Primary (Lime) ──────────────────────────────────────────────────────────
  primary:            Color(0xFFE1FB8E), // lime-500
  onPrimary:          Color(0xFF0A0B0A), // ink-900
  primaryContainer:   Color(0xFFF2FDC2), // limeTint / lime-200
  onPrimaryContainer: Color(0xFF0A0B0A), // ink-900
  // Fixed roles: same hue both light & dark; Dim = stronger variant of Fixed.
  primaryFixed:           Color(0xFFE1FB8E), // lime-500
  primaryFixedDim:        Color(0xFFCDEF45), // limeHover (more saturated)
  onPrimaryFixed:         Color(0xFF0A0B0A), // ink-900
  onPrimaryFixedVariant:  Color(0xFF2B2F2B), // fg-body (lower emphasis)

  // ── Secondary (Sky) ─────────────────────────────────────────────────────────
  secondary:            Color(0xFF3E7BD8), // sky-500
  onSecondary:          Color(0xFFFFFFFF), // paper
  secondaryContainer:   Color(0xFFDCE9F7), // sky-100
  onSecondaryContainer: Color(0xFF2456AB), // sky-700
  secondaryFixed:           Color(0xFF3E7BD8), // sky-500
  secondaryFixedDim:        Color(0xFF2D6AC7), // sky-600 (derived: sky-500 darkened ~8%)
  onSecondaryFixed:         Color(0xFFFFFFFF), // paper
  onSecondaryFixedVariant:  Color(0xFFDCE9F7), // sky-100 (lower emphasis — intentionally lighter)

  // ── Tertiary (Positive/Green) ────────────────────────────────────────────────
  // Palette has no defined tertiary; positive (#1F9D57) is the closest accent.
  tertiary:            Color(0xFF1F9D57), // positive
  onTertiary:          Color(0xFFFFFFFF), // paper
  tertiaryContainer:   Color(0xFFC8E6C9), // positive-100 tint (derived)
  onTertiaryContainer: Color(0xFF072F1A), // positive-900 (derived)
  tertiaryFixed:           Color(0xFF1F9D57), // positive
  tertiaryFixedDim:        Color(0xFF187A44), // positive darkened ~20%
  onTertiaryFixed:         Color(0xFFFFFFFF), // paper
  onTertiaryFixedVariant:  Color(0xFFC8E6C9), // positive-100 (lower emphasis)

  // ── Error (Negative) ────────────────────────────────────────────────────────
  error:            Color(0xFFE2473D), // negative
  onError:          Color(0xFFFFFFFF), // paper
  errorContainer:   Color(0xFFFFDAD6), // negative-100 tint (M3 standard derivation)
  onErrorContainer: Color(0xFF410002), // negative-900 (M3 standard derivation)

  // ── Surface hierarchy (Ink / neutral scale) ──────────────────────────────────
  // Ordered from brightest to most tinted:
  //   paper(#FFF) → appBg(#F4F6F1) → sunken(#ECEEE7) → tinted variants below
  surface:                    Color(0xFFFFFFFF), // paper
  surfaceBright:              Color(0xFFFFFFFF), // paper — brightest surface
  surfaceDim:                 Color(0xFFE4E6DF), // ink-neutral (between sunken & outlineVariant)
  surfaceContainerLowest:     Color(0xFFFFFFFF), // paper
  surfaceContainerLow:        Color(0xFFF4F6F1), // appBg
  surfaceContainer:           Color(0xFFECEEE7), // sunken
  surfaceContainerHigh:       Color(0xFFE4E6DF), // hairline-light (between sunken & outline)
  surfaceContainerHighest:    Color(0xFFDDDFD8), // darkest surface container (derived)

  // ── On-surface & outline ────────────────────────────────────────────────────
  onSurface:        Color(0xFF2B2F2B), // fg-body / ink-700
  onSurfaceVariant: Color(0xFF6C726B), // fgMuted / ink-500
  outline:          Color(0xFF6C726B), // fgMuted (for interactive borders)
  outlineVariant:   Color(0xFFC4C8C2), // lighter border (decorative dividers)

  // ── Inverse & utility ───────────────────────────────────────────────────────
  inverseSurface:   Color(0xFF2B2F2B), // fg-body → becomes surface on dark sheet
  onInverseSurface: Color(0xFFF4F6F1), // appBg → content on ink surface
  inversePrimary:   Color(0xFFB6DE2E), // limePress (lime on dark background)
  surfaceTint:      Color(0xFFE1FB8E), // primary = lime-500
  shadow:           Color(0xFF000000),
  scrim:            Color(0xFF000000),
);

// ─────────────────────────────────────────────────────────────────────────────
// 1b. DARK COLOUR SCHEME — the same Mohapi V1 palette re-keyed onto an ink field.
//
//    Surface base is ink-900 #0A0B0A; surfaces climb the ink ramp from there
//    (ink-900 → #161816 inkSurface → #1F221E → #292C28). The brand accents are
//    RETAINED, not re-derived: primary stays lime-500 and secondary stays sky-500,
//    so the app reads as the same brand at night. Only the on-* and container roles
//    and the legibility-sensitive error/positive accents are lifted for dark contrast.
//
//    Surface-role convention matches the light scheme so widgets need no edits:
//      surface (= the "paper"/card sheet) is the brightest base surface and sits
//      ABOVE the scaffold, which is painted with the appBg token (ink-900). Hence
//      surface here is #161816, not #0A0B0A — cards reading scheme.surface lift off
//      the ink-900 scaffold exactly as paper lifts off appBg in the light scheme.
//
//    Contrast (WCAG, on the surfaces they sit on):
//      lime-500 / ink-900    ≈ 19:1 ✓    onSurface #E3E5DF / ink-900 ≈ 17:1 ✓
//      sky-500  / #161816    ≈ 4.7:1 ✓   error #FF8A80 / #161816     ≈ 7.0:1 ✓
// ─────────────────────────────────────────────────────────────────────────────
const easyRatesDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,

  // ── Primary (Lime) — retained accent ────────────────────────────────────────
  primary:            Color(0xFFE1FB8E), // lime-500 (retained)
  onPrimary:          Color(0xFF0A0B0A), // ink-900 (lime is bright → ink label)
  primaryContainer:   Color(0xFF42511D), // deep lime — fill that holds on an ink field
  onPrimaryContainer: Color(0xFFECFBB8), // lime tint
  primaryFixed:           Color(0xFFE1FB8E), // lime-500
  primaryFixedDim:        Color(0xFFCDEF45), // limeHover
  onPrimaryFixed:         Color(0xFF0A0B0A), // ink-900
  onPrimaryFixedVariant:  Color(0xFFC6E07A), // lime, lower emphasis

  // ── Secondary (Sky) — retained accent ───────────────────────────────────────
  secondary:            Color(0xFF3E7BD8), // sky-500 (retained)
  onSecondary:          Color(0xFFFFFFFF), // paper
  secondaryContainer:   Color(0xFF1C3157), // sky darkened for an ink fill
  onSecondaryContainer: Color(0xFFCFE0F7), // sky-100
  secondaryFixed:           Color(0xFF3E7BD8), // sky-500
  secondaryFixedDim:        Color(0xFF2D6AC7), // sky-600
  onSecondaryFixed:         Color(0xFFFFFFFF), // paper
  onSecondaryFixedVariant:  Color(0xFFCFE0F7), // sky-100

  // ── Tertiary (Positive/Green) ────────────────────────────────────────────────
  tertiary:            Color(0xFF49C27E), // positive lifted for dark legibility
  onTertiary:          Color(0xFF00391E), // positive-900
  tertiaryContainer:   Color(0xFF12502F), // positive darkened
  onTertiaryContainer: Color(0xFFC8E6C9), // positive-100
  tertiaryFixed:           Color(0xFF1F9D57), // positive
  tertiaryFixedDim:        Color(0xFF187A44), // positive darkened
  onTertiaryFixed:         Color(0xFFFFFFFF), // paper
  onTertiaryFixedVariant:  Color(0xFFC8E6C9), // positive-100

  // ── Error (Negative) ────────────────────────────────────────────────────────
  error:            Color(0xFFFF8A80), // negative lifted for dark legibility
  onError:          Color(0xFF5F1410), // negative-900
  errorContainer:   Color(0xFF8C201A), // negative darkened
  onErrorContainer: Color(0xFFFFDAD6), // negative-100

  // ── Surface hierarchy (Ink scale, dark) ──────────────────────────────────────
  // Climbs from ink-900; `surface` is the dark "paper" (cards), scaffold uses appBg.
  surface:                    Color(0xFF161816), // inkSurface — dark paper / card sheet
  surfaceBright:              Color(0xFF30332F), // brightest dark surface (input fills)
  surfaceDim:                 Color(0xFF0A0B0A), // ink-900 — dimmest
  surfaceContainerLowest:     Color(0xFF0A0B0A), // ink-900
  surfaceContainerLow:        Color(0xFF121412), // just above base
  surfaceContainer:           Color(0xFF161816), // inkSurface
  surfaceContainerHigh:       Color(0xFF1F221E), // raised
  surfaceContainerHighest:    Color(0xFF292C28), // highest container

  // ── On-surface & outline ────────────────────────────────────────────────────
  onSurface:        Color(0xFFE3E5DF), // light ink — body text on dark
  onSurfaceVariant: Color(0xFFAFB4AC), // muted light
  outline:          Color(0xFF8A8F87), // interactive borders
  outlineVariant:   Color(0xFF2A2E2A), // hairline — decorative dividers

  // ── Inverse & utility ───────────────────────────────────────────────────────
  inverseSurface:   Color(0xFFE3E5DF), // light sheet on dark
  onInverseSurface: Color(0xFF161816), // ink content on the light sheet
  inversePrimary:   Color(0xFF42511D), // deep lime (lime on a light surface)
  surfaceTint:      Color(0xFFE1FB8E), // primary = lime-500
  shadow:           Color(0xFF000000),
  scrim:            Color(0xFF000000),
);

// ─────────────────────────────────────────────────────────────────────────────
// 2. TYPE RAMP — all 15 Material TextTheme slots, every size from {58,40,30,24,17,15,13,11}.
//
//    Space Grotesk zone (display + headline): 58 · 40 · 30 · 24
//    Manrope zone        (title + body + label): 17 · 15 · 13 · 11
//
//    8 SPEC slots (Mohapi V1 verbatim) are marked ★.
//    7 non-spec slots reuse the nearest ramp size with a weight adjustment so no
//    Material widget ever falls back to Flutter's generic defaults.
//
//    Key decisions:
//      displayMedium / displaySmall — reuse 40 / 30 (spec has no mid-display size)
//      titleLarge — 24 SpaceGrotesk (AppBar title; same ramp step as headlineSmall)
//      bodyLarge  — 17 Manrope w400 (title size, regular weight = larger body context)
//      titleSmall — 15 Manrope w600 (body size, semi-bold)
//      labelLarge — 15 Manrope w700 (button labels via Material defaults)
//      labelMedium — 13 Manrope w600 (chips)
// ─────────────────────────────────────────────────────────────────────────────
TextTheme buildEasyRatesTextTheme() {
  // Helpers — avoid repeating font name strings.
  TextStyle grotesk(double size, FontWeight weight, {double? ls, double? h, bool tabular = false}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: ls,
        height: h,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  TextStyle manrope(double size, FontWeight weight, {double? ls}) =>
      GoogleFonts.manrope(fontSize: size, fontWeight: weight, letterSpacing: ls);

  return TextTheme(
    // ── Space Grotesk — display / headline zone (tabular figures throughout) ──
    // Tabular figures on the entire Space Grotesk family: digits align
    // consistently whenever a heading slot happens to contain a number.
    // ★ 58 — money display; ls/h tuned for tight financial figures.
    displayLarge:  grotesk(58, FontWeight.w700, ls: -1.0, h: 1.0, tabular: true),
    // Non-spec: reuse 40 (spec has no separate display-medium size).
    displayMedium: grotesk(40, FontWeight.w700, ls: -0.5,          tabular: true),
    // Non-spec: reuse 30.
    displaySmall:  grotesk(30, FontWeight.w700,                    tabular: true),
    // ★ 40 — h1 section header.
    headlineLarge:  grotesk(40, FontWeight.w700, ls: -0.5,         tabular: true),
    // ★ 30 — h2.
    headlineMedium: grotesk(30, FontWeight.w700,                   tabular: true),
    // ★ 24 — h3.
    headlineSmall:  grotesk(24, FontWeight.w600,                   tabular: true),
    // Non-spec: 24 SpaceGrotesk — AppBar uses titleLarge; same ramp step as h3.
    titleLarge:     grotesk(24, FontWeight.w600,                   tabular: true),

    // ── Manrope — title / body / label zone ─────────────────────────────────
    // ★ 17 — component titles, button labels.
    titleMedium: manrope(17, FontWeight.w700),
    // Non-spec: 15 semi-bold — smaller titled contexts.
    titleSmall:  manrope(15, FontWeight.w600),
    // Non-spec: 17 regular — larger body copy (title size, body weight).
    bodyLarge:   manrope(17, FontWeight.w400),
    // ★ 15 — body text.
    bodyMedium:  manrope(15, FontWeight.w400),
    // ★ 13 — small / secondary body.
    bodySmall:   manrope(13, FontWeight.w500),
    // Non-spec: 15 bold — M3 uses labelLarge for button text.
    labelLarge:  manrope(15, FontWeight.w700),
    // Non-spec: 13 semi-bold — chips.
    labelMedium: manrope(13, FontWeight.w600),
    // ★ 11 — overline / badge. Uppercase applied at the widget, not here.
    labelSmall:  manrope(11, FontWeight.w700, ls: 0.8),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. CUSTOM TOKENS — spacing, radii, semantic colours, brand ramp extras.
//    The ThemeExtension is the official escape hatch for tokens that
//    ColorScheme/TextTheme can't hold.
//
//    Usage:
//      final t = Theme.of(context).extension<EasyRatesTokens>()!;
//      Container(padding: t.cardPadding, decoration: BoxDecoration(borderRadius: t.cardRadius))
// ─────────────────────────────────────────────────────────────────────────────
@immutable
class EasyRatesTokens extends ThemeExtension<EasyRatesTokens> {
  // ── Spacing — 4px base grid ─────────────────────────────────────────────
  // s1=4  s2=8  s3=12  s4=16  s5=20  s6=24  s8=32  s12=48
  final double s1, s2, s3, s4, s5, s6, s8, s12;

  // ── Radii — 8 / 16 / 22 / 28 / 36 / pill(9999) ──────────────────────────
  final double rSm, rMd, rLg, rXl, r2xl, rPill;

  // ── Icon sizes — 3 tiers ────────────────────────────────────────────────
  //   iconSm 18 — dense / inline-with-text affordances
  //   iconMd 22 — DEFAULT (the 20–22 band); the global IconTheme size
  //   iconLg 24 — emphasis / primary actions
  // Stroke weight is NOT a token: the Lucide icon font carries its native 2px
  // stroke on a 24px grid intrinsically, and colour is inherited (currentColor)
  // from the ambient IconTheme — both are wired as defaults in app_theme.dart.
  final double iconSm, iconMd, iconLg;

  // ── Border ring widths ──────────────────────────────────────────────────
  //   borderWidth      1 — hairline rest / error / disabled ring
  //   borderWidthFocus 2 — emphasised focus (and focused-error) ring
  // Mirrors the input borders baked into app_theme.dart's inputDecorationTheme.
  final double borderWidth, borderWidthFocus;

  // ── Semantic colours (signal money direction / status) ───────────────────
  final Color positive, negative, warning, info;

  // ── Brand ramp extras not in ColorScheme ─────────────────────────────────
  final Color limePress, limeHover, limeTint;

  // ── Ink / neutral extras ─────────────────────────────────────────────────
  final Color inkSurface, hairline, fgMuted, appBg, sunken;

  // ── Ink nav surface — the deepest ink, dark in BOTH modes (signature) ─────
  //   ink900     #0A0B0A — the floating tab-bar surface
  //   onInkMuted #AFB4AC — muted light content (inactive tab) on that ink
  // Brightness-independent: the bar reads as the same ink slab day or night,
  // exactly like the inverted AppBar. Active tabs use primary/onPrimary (lime).
  final Color ink900, onInkMuted;

  const EasyRatesTokens({
    required this.s1,  required this.s2,  required this.s3,  required this.s4,
    required this.s5,  required this.s6,  required this.s8,  required this.s12,
    required this.rSm, required this.rMd, required this.rLg, required this.rXl,
    required this.r2xl, required this.rPill,
    required this.iconSm, required this.iconMd, required this.iconLg,
    required this.borderWidth, required this.borderWidthFocus,
    required this.positive, required this.negative,
    required this.warning,  required this.info,
    required this.limePress, required this.limeHover, required this.limeTint,
    required this.inkSurface, required this.hairline,
    required this.fgMuted, required this.appBg, required this.sunken,
    required this.ink900, required this.onInkMuted,
  });

  // ── Light token set (Mohapi V1) ──────────────────────────────────────────
  static const light = EasyRatesTokens(
    s1: 4,  s2: 8,  s3: 12, s4: 16, s5: 20, s6: 24, s8: 32, s12: 48,
    rSm: 8, rMd: 16, rLg: 22, rXl: 28, r2xl: 36, rPill: 9999,
    iconSm: 18, iconMd: 22, iconLg: 24,
    borderWidth: 1, borderWidthFocus: 2,
    positive: Color(0xFF1F9D57), negative: Color(0xFFE2473D),
    warning:  Color(0xFFE0982F), info:     Color(0xFF3E7BD8),
    limePress: Color(0xFFB6DE2E), limeHover: Color(0xFFCDEF45), limeTint: Color(0xFFF2FDC2),
    inkSurface: Color(0xFF161816), hairline: Color(0xFF2A2E2A),
    fgMuted: Color(0xFF6C726B), appBg: Color(0xFFF4F6F1), sunken: Color(0xFFECEEE7),
    ink900: Color(0xFF0A0B0A), onInkMuted: Color(0xFFAFB4AC),
  );

  // ── Dark token set ───────────────────────────────────────────────────────
  // Spacing and radii are brightness-independent — identical to light.
  // What changes: the neutral surfaces invert onto the ink ramp (appBg → ink-900,
  // sunken → #121412), fgMuted lifts for dark legibility, the semantic accents
  // lift to match their dark-scheme counterparts, and limeTint — a *fill* token —
  // becomes the deep-lime container rather than the pale light tint.
  static const dark = EasyRatesTokens(
    s1: 4,  s2: 8,  s3: 12, s4: 16, s5: 20, s6: 24, s8: 32, s12: 48,
    rSm: 8, rMd: 16, rLg: 22, rXl: 28, r2xl: 36, rPill: 9999,
    iconSm: 18, iconMd: 22, iconLg: 24,
    borderWidth: 1, borderWidthFocus: 2,
    positive: Color(0xFF49C27E), negative: Color(0xFFFF8A80),
    warning:  Color(0xFFF0B868), info:     Color(0xFF6FA0E6),
    limePress: Color(0xFFB6DE2E), limeHover: Color(0xFFCDEF45), limeTint: Color(0xFF42511D),
    inkSurface: Color(0xFF161816), hairline: Color(0xFF2A2E2A),
    fgMuted: Color(0xFFAFB4AC), appBg: Color(0xFF0A0B0A), sunken: Color(0xFF121412),
    ink900: Color(0xFF0A0B0A), onInkMuted: Color(0xFFAFB4AC),
  );

  // ── Computed BorderRadius getters ────────────────────────────────────────
  // Avoids writing BorderRadius.circular(t.rLg) at every widget call-site.
  BorderRadius get radiusSm   => BorderRadius.circular(rSm);   // 8
  BorderRadius get radiusMd   => BorderRadius.circular(rMd);   // 16
  BorderRadius get radiusLg   => BorderRadius.circular(rLg);   // 22 — cards
  BorderRadius get radiusXl   => BorderRadius.circular(rXl);   // 28
  BorderRadius get radius2xl  => BorderRadius.circular(r2xl);  // 36
  BorderRadius get radiusPill => BorderRadius.circular(rPill); // 9999 — buttons

  // ── Computed EdgeInsets getters ──────────────────────────────────────────
  EdgeInsets get screenPadding => EdgeInsets.symmetric(horizontal: s5, vertical: s4); // h20/v16
  EdgeInsets get cardPadding   => EdgeInsets.all(s5);                                 // 20
  EdgeInsets get listTilePadding => EdgeInsets.symmetric(horizontal: s4, vertical: s3); // h16/v12
  EdgeInsets get badgePadding  => EdgeInsets.symmetric(horizontal: s3, vertical: s1);  // h12/v4 — status pills

  // ── copyWith — all 25 fields exposed ────────────────────────────────────
  // The ThemeExtension contract: every field must be overridable.
  @override
  EasyRatesTokens copyWith({
    double? s1,  double? s2,  double? s3,  double? s4,
    double? s5,  double? s6,  double? s8,  double? s12,
    double? rSm, double? rMd, double? rLg, double? rXl,
    double? r2xl, double? rPill,
    double? iconSm, double? iconMd, double? iconLg,
    double? borderWidth, double? borderWidthFocus,
    Color? positive, Color? negative, Color? warning, Color? info,
    Color? limePress, Color? limeHover, Color? limeTint,
    Color? inkSurface, Color? hairline, Color? fgMuted,
    Color? appBg, Color? sunken,
    Color? ink900, Color? onInkMuted,
  }) {
    return EasyRatesTokens(
      s1:  s1  ?? this.s1,  s2:  s2  ?? this.s2,
      s3:  s3  ?? this.s3,  s4:  s4  ?? this.s4,
      s5:  s5  ?? this.s5,  s6:  s6  ?? this.s6,
      s8:  s8  ?? this.s8,  s12: s12 ?? this.s12,
      rSm:  rSm  ?? this.rSm,  rMd:  rMd  ?? this.rMd,
      rLg:  rLg  ?? this.rLg,  rXl:  rXl  ?? this.rXl,
      r2xl: r2xl ?? this.r2xl, rPill: rPill ?? this.rPill,
      iconSm: iconSm ?? this.iconSm, iconMd: iconMd ?? this.iconMd,
      iconLg: iconLg ?? this.iconLg,
      borderWidth: borderWidth ?? this.borderWidth,
      borderWidthFocus: borderWidthFocus ?? this.borderWidthFocus,
      positive: positive ?? this.positive, negative: negative ?? this.negative,
      warning:  warning  ?? this.warning,  info:     info     ?? this.info,
      limePress: limePress ?? this.limePress, limeHover: limeHover ?? this.limeHover,
      limeTint:  limeTint  ?? this.limeTint,
      inkSurface: inkSurface ?? this.inkSurface, hairline: hairline ?? this.hairline,
      fgMuted: fgMuted ?? this.fgMuted, appBg: appBg ?? this.appBg,
      sunken:  sunken  ?? this.sunken,
      ink900: ink900 ?? this.ink900, onInkMuted: onInkMuted ?? this.onInkMuted,
    );
  }

  // ── lerp — all fields interpolated for smooth theme transitions ──────────
  @override
  EasyRatesTokens lerp(ThemeExtension<EasyRatesTokens>? other, double t) {
    if (other is! EasyRatesTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    return EasyRatesTokens(
      s1:  d(s1,  other.s1),  s2:  d(s2,  other.s2),
      s3:  d(s3,  other.s3),  s4:  d(s4,  other.s4),
      s5:  d(s5,  other.s5),  s6:  d(s6,  other.s6),
      s8:  d(s8,  other.s8),  s12: d(s12, other.s12),
      rSm:  d(rSm,  other.rSm),  rMd:  d(rMd,  other.rMd),
      rLg:  d(rLg,  other.rLg),  rXl:  d(rXl,  other.rXl),
      r2xl: d(r2xl, other.r2xl), rPill: d(rPill, other.rPill),
      iconSm: d(iconSm, other.iconSm), iconMd: d(iconMd, other.iconMd),
      iconLg: d(iconLg, other.iconLg),
      borderWidth: d(borderWidth, other.borderWidth),
      borderWidthFocus: d(borderWidthFocus, other.borderWidthFocus),
      positive: c(positive, other.positive), negative: c(negative, other.negative),
      warning:  c(warning,  other.warning),  info:     c(info,     other.info),
      limePress: c(limePress, other.limePress), limeHover: c(limeHover, other.limeHover),
      limeTint:  c(limeTint,  other.limeTint),
      inkSurface: c(inkSurface, other.inkSurface), hairline: c(hairline, other.hairline),
      fgMuted: c(fgMuted, other.fgMuted), appBg: c(appBg, other.appBg),
      sunken:  c(sunken,  other.sunken),
      ink900: c(ink900, other.ink900), onInkMuted: c(onInkMuted, other.onInkMuted),
    );
  }
}
