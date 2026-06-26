# 🌑 Splash — Dark Ink Landing

## Background
Composes `component-kit/` (primary button) on `design-system/` dark theme
(ink-900). Both are prerequisite scopes; this plan assembles, it does not build
widgets or tokens.

## Description
Assemble the Splash screen: the dark ink-900 entry screen with the lime droplet
logo, carousel dots, headline/subhead, and the "Get started" call to action.

## Purpose
Serves Objective 1 / DoD 1 — the app's first screen and the entry point of the
Splash → Home navigation flow.

## Goal
`lib/screens/splash/splash_screen.dart` renders in dark brightness, faithful to the
Splash spec screenshot, with a working "Get started" button.

## Tasks

- [x] Create `lib/screens/splash_screen.dart` on the dark ink-900 surface (dark theme brightness)
- [x] Place the lime droplet logo with its glow effect
- [x] Add the carousel dots indicator
- [x] Add the headline + subhead (Space Grotesk display / Manrope body from tokens)
- [x] Compose the primary lime pill button as "Get started"
- [x] Localise all copy to Emfuleni / EasyRates

## Engagement Instructions
```
$ flutter run            # then observe the Splash screen on launch
# expect: ink-900 dark background, lime droplet logo with glow, dots,
#         headline+subhead, lime "Get started" pill. Compare to Splash spec.
$ flutter test test/screens/splash_golden_test.dart   # golden vs spec, if added
```

## Recommended skill
— custom; no skill fits (Flutter spec-fidelity screen assembly; project-specific).
