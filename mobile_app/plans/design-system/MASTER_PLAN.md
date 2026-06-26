# Design System — Mohapi V1 Tokens, Themes, Fonts & Icons

## Mission
Encode Mohapi Design System V1 as the EasyRates app's single design-system
source of truth. Port the verified-faithful token store from the learning
capstone and harden it into the product theme — light AND dark — then bundle
the real fonts and icon set so every downstream widget draws from tokens and
never hardcodes a colour, size, radius, or icon.

## Objectives
1. Port the verified light token store into the product theme as the canonical
   token source (colours, spacing, radii, type ramp).
2. Add the dark `ColorScheme` + `EasyRatesTokens` (ink-900 surfaces for Splash,
   Success, and the floating tab bar) and a brightness switch between them.
3. Bundle the product fonts — Space Grotesk (display / numbers, tabular figures)
   and Manrope (body / interface).
4. Wire Lucide icons (2px stroke, currentColor, 18 / 20–22 / 24px sizing),
   replacing Material icons throughout.

## Goals
1. Every token on the Mohapi V1 spec sheet is present in BOTH brightnesses:
   colours (lime-500 #E1FB8E primary, ink-900 #0A0B0A, sky-500 #3E7BD8),
   4px spacing scale, radii 8 / 16 / 22 / 28 / 36 / pill, and the
   58 / 40 / 30 / 24 / 17 / 15 / 13 / 11 type ramp.
2. A brightness switch flips the whole app between light and dark themes, with
   ink-900 surfaces appearing correctly on Splash / Success / tab bar in dark.
3. Space Grotesk and Manrope render from bundled assets, with Space Grotesk
   numerals using tabular (monospaced) figures.
4. Lucide icons render at the spec stroke/size/colour; no Material icons remain.
5. Zero hardcoded colours or sizes downstream — every value resolves through the
   theme / token API.

## Expected Outcome
A single, theme-driven design-system layer under `easy_rates/mobile_app/lib/theme/` that
any screen or component imports to get Mohapi V1's exact look in either
brightness. Fonts and icons are bundled and rendering. Building a new widget
means reaching for tokens — there is no other source of colour, size, or icon.

## Definition of Done
1. Light token store ported into the product theme and used as the canonical
   token source.
2. Dark `ColorScheme` + `EasyRatesTokens` present (ink-900 surfaces for Splash /
   Success / tab bar) with a working brightness switch.
3. Space Grotesk + Manrope bundled in pubspec assets and rendering, with tabular
   figures on numbers.
4. Lucide icons wired (2px stroke, currentColor, 18 / 20–22 / 24px); all Material
   icon usages replaced.
5. Every token from the spec sheet present in both brightnesses (colours, 4px
   spacing, radii 8/16/22/28/36/pill, type ramp 58/40/30/24/17/15/13/11).
6. No hardcoded colours/sizes downstream — verified by a grep over `lib/` for raw
   `Color(`, hex literals, and magic numbers outside the theme layer.

## Sub-Scopes
(none)

## Plans
- ✓ 01-port-light-tokens.md
- ✓ 02-dark-theme-brightness-switch.md
- ✓ 03-bundle-fonts.md — SpaceGrotesk SemiBold/Bold only bundled (no Regular/Medium TTF); GoogleFonts synthesises missing weights
- ✓ 04-wire-lucide-icons.md
- ✓ 05-token-parity-no-hardcode-audit.md
