# 💳 Pay — Amount Due & Breakdown

## Background
Composes `component-kit/` (Due badge, payment-method card, sticky primary
button) on `design-system/` light theme. Prerequisite scopes; assembly only.

## Description
Assemble the Pay screen: back button, the AMOUNT DUE hero, the due badge, the
line-item breakdown card, the payment-method card, the sticky "Pay R…" button,
and the secured footer.

## Purpose
Serves Objective 3 / DoD 3 — the transactional middle of the Home → Pay →
Success flow.

## Goal
`lib/screens/pay/pay_screen.dart` renders in light brightness, shows a correct
R-formatted breakdown that totals, and matches the Pay spec screenshot.

## Tasks
- [x] Create `lib/screens/pay_screen.dart` on the light surface
- [x] Add the back button
- [x] Add the AMOUNT DUE hero display (Space Grotesk tabular figures, R)
- [x] Compose the Due status badge
- [x] Build the line-item breakdown card — supply / wastewater / standing / total (Emfuleni tariff terms, R)
- [x] Add the payment-method card with masked card digits
- [x] Compose the sticky "Pay R…" primary button pinned to the bottom
- [x] Add the secured footer
- [x] Verify the breakdown line items sum to the total shown in the hero

## Engagement Instructions
```
$ flutter run            # navigate Home → Pay
# expect: light; back button; AMOUNT DUE hero in R; Due badge; breakdown
#         (supply/wastewater/standing/total) summing correctly; payment-method
#         card; sticky "Pay R…"; secured footer. Compare to Pay spec.
$ flutter test test/screens/pay_golden_test.dart
```

## Recommended skill
— custom; no skill fits (Flutter spec-fidelity screen assembly; project-specific).
