# 🔤 Bundle Space Grotesk + Manrope

## Description
Bundle the product fonts and make numerals tabular — Space Grotesk for display /
numbers, Manrope for body / interface.

## Purpose
Objective 3 / DoD 3. The type ramp from Plan 01 renders in the real typefaces
only once the fonts are bundled; tabular figures keep numbers aligned in totals
and tables.

## Goal
Space Grotesk + Manrope declared in pubspec assets and rendering, with Space
Grotesk numerals using tabular (monospaced) figures.

## Tasks
- [x] Add Space Grotesk + Manrope font files under `assets/fonts/`
- [x] Declare both families in `pubspec.yaml` `fonts:`
- [x] Map `TextTheme` styles to families (Space Grotesk display/numbers, Manrope body/interface)
- [x] Enable tabular figures on Space Grotesk numerals (`FontFeature.tabularFigures()`)

## Engagement Instructions
```
$ flutter pub get && flutter analyze
```
Visual: render a screen with a numeric total + body text; confirm Space Grotesk
on the numbers (digits column-aligned) and Manrope on the body.
