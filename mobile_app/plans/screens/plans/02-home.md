# 🏠 Home — Balance, Actions & Bills

## Background
Composes `component-kit/` (balance card, bill row, status badges, floating tab
bar) on `design-system/` light theme. Prerequisite scopes; assembly only.

## Description
Assemble the Home screen: greeting + bell, the lime balance card, the 5-action
quick row, the sky tip banner, the "Your bills" list, and the dark floating tab
bar.

## Purpose
Serves Objective 2 / DoD 2 — the app's hub; origin of both the Pay flow and the
Usage tab.

## Goal
`lib/screens/home/home_screen.dart` renders in light brightness, composes kit widgets
only, displays R, and matches the Home spec screenshot.

## Tasks
- [x] Create `lib/screens/home_screen.dart` on the light surface
- [x] Add "Hi {name}" greeting + bell icon (Lucide bell)
- [x] Compose the lime balance card with an Emfuleni name + R balance
- [x] Build the 5-action quick row — Pay / Bills / Usage / Auto-pay / More (Lucide glyphs)
- [x] Add the sky tip banner
- [x] Compose the "Your bills" list from bill rows + status badges, with Emfuleni bill types
- [x] Compose the dark floating tab bar
- [x] Confirm all money renders in R with SA formatting (no £)

## Engagement Instructions
```
$ flutter run            # navigate to Home (or set as initial route temporarily)
# expect: light surface; "Hi {name}"+bell; lime balance card in R; 5-action row;
#         sky tip banner; bill rows with badges; dark floating tab bar.
$ flutter test test/screens/home_golden_test.dart
```

## Recommended skill
— custom; no skill fits (Flutter spec-fidelity screen assembly; project-specific).
