# 🌙 Dark Theme + Brightness Switch

## Description
Add the dark counterpart to the light token store and a switch that flips the
whole app between brightnesses. Ink-900 surfaces must appear on Splash, Success,
and the floating tab bar in dark.

## Purpose
Objective 2 / DoD 2. Half the token surface (DoD 5) only exists once dark is
present; the brightness switch is what makes both brightnesses reachable at
runtime.

## Goal
A dark `ColorScheme` + dark `EasyRatesTokens`, wired into `MaterialApp.darkTheme`
+ `themeMode`, with a working brightness switch and ink-900 surfaces correct on
Splash / Success / the floating tab bar.

## Tasks
- [x] Dark `ColorScheme` (ink-900 `#0A0B0A` surfaces; lime-500 / sky-500 retained as accents)
- [x] Dark `EasyRatesTokens` values where they differ from light
- [x] Ink-900 surface treatment for Splash, Success, and the floating tab bar
- [x] Brightness switch (`ThemeMode` toggle) flipping the whole app light↔dark
- [x] Wire dark theme into `MaterialApp.darkTheme` + `themeMode`

## Engagement Instructions
```
$ flutter test test/theme/dark_tokens_test.dart   # dark ColorScheme + ink-900 surfaces match spec
```
Visual: run the app, toggle the switch, and confirm Splash / Success / tab bar
show ink-900 in dark and that only themed surfaces change when the brightness
flips.
