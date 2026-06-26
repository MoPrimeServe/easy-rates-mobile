# 📊 Usage — Consumption & History

## Background
Composes `component-kit/` (floating tab bar) on `design-system/` light theme,
with a sky line chart. Prerequisite scopes; assembly only.

## Description
Assemble the Usage screen: the Water / Council-tax toggle, the usage card (m³,
+% vs last month, period dropdown, sky line chart), the History list, and the
tab bar.

## Purpose
Serves Objective 5 / DoD 5 — the Home-tab destination, off the main pay flow.

## Goal
`lib/screens/usage/usage_screen.dart` renders in light brightness, charts Emfuleni
usage, and matches the Usage spec screenshot.

## Tasks
- [x] Create `lib/screens/usage_screen.dart` on the light surface
- [x] Add the Water / Council-tax toggle
- [x] Build the usage card — m³ figure, +% vs last month, period dropdown, sky line chart
- [x] Add the History list
- [x] Compose the dark floating tab bar
- [x] Localise content to Emfuleni (council-tax usage, periods)

## Engagement Instructions
```
$ flutter run            # navigate Home tab → Usage
# expect: light; Water/Council-tax toggle; usage card (m³, +%, period dropdown,
#         sky line chart); History list; tab bar. Compare to Usage spec.
$ flutter test test/screens/usage_golden_test.dart
```

## Recommended skill
— custom; no skill fits (Flutter spec-fidelity screen assembly; project-specific).
