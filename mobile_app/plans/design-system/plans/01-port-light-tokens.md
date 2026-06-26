# 🎨 Port The Light Token Store

## Description
Port the verified light token store from the learning capstone into the product
app's theme layer as the canonical token source — colours, the 4px spacing scale,
radii, and the type ramp — so every widget resolves values through the theme.

## Purpose
Serves Objective 1 / DoD 1. The light tokens are the foundation the dark theme,
fonts, and audit all build on; nothing downstream can resolve through tokens
until they live in the product theme.

## Goal
A `lib/theme/` light theme — `ColorScheme` + `TextTheme` + an `EasyRatesTokens`
ThemeExtension (spacing, radii) — ported from the capstone, wired app-wide,
carrying the exact Mohapi V1 light values.

## Tasks
- [x] Create `lib/theme/` and seed it from the verified light token store in `learning/easyrates-fullstack` (capstone)
- [x] Light `ColorScheme` from the palette (lime-500 `#E1FB8E` primary, ink-900 `#0A0B0A`, sky-500 `#3E7BD8`)
- [x] `TextTheme` from the type ramp (58/40/30/24/17/15/13/11)
- [x] `EasyRatesTokens` ThemeExtension: 4px spacing scale + radii (8/16/22/28/36/pill)
- [x] Wire the light theme into `MaterialApp.theme`; read tokens via `Theme.of(context)`

## Engagement Instructions
```
$ flutter analyze lib/theme        # no errors
$ flutter test test/theme/light_tokens_test.dart   # ColorScheme + token values match the spec sheet
```
Runs once the Flutter project is scaffolded. Until then, the by-hand check is:
open the ported file and confirm every spec value above (lime-500 `#E1FB8E`,
ink-900 `#0A0B0A`, sky-500 `#3E7BD8`, the 4px scale, radii 8/16/22/28/36/pill,
and the 58/40/30/24/17/15/13/11 ramp) appears literally.
