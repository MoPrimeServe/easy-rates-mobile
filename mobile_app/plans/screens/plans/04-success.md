# ✅ Success — Payment Confirmed

## Background
Composes `component-kit/` (primary button) on `design-system/` dark theme
(ink-900). Prerequisite scopes; assembly only.

## Description
Assemble the Success screen: the dark ink-900 confirmation with a lime glow
check circle, "Payment sent", the amount in lime, a receipt line, and "Done".

## Purpose
Serves Objective 4 / DoD 4 — the terminal confirmation of the Pay flow.

## Goal
`lib/screens/success/success_screen.dart` renders in dark brightness, shows the amount
in lime R, and matches the Success spec screenshot.

## Tasks
- [x] Create `lib/screens/success_screen.dart` on the dark ink-900 surface
- [x] Add the lime glow check circle
- [x] Add the "Payment sent" headline
- [x] Show the paid amount in lime (R, tabular figures)
- [x] Add the receipt line (reference + date)
- [x] Compose the "Done" button

## Engagement Instructions
```
$ flutter run            # navigate Home → Pay → (Pay R…) → Success
# expect: ink-900 dark; lime glow check circle; "Payment sent"; amount in lime R;
#         receipt line; "Done" button. Compare to Success spec.
$ flutter test test/screens/success_golden_test.dart
```

## Recommended skill
— custom; no skill fits (Flutter spec-fidelity screen assembly; project-specific).
