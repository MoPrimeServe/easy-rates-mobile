# 🔘 Buttons — Three Variants

## Background
Built on the capstone's `AppButton` pattern (variant enum + `.spec()` → tokens),
reading the `design-system/` token layer (separate scope, not yet built). Builds
the widget; does not build tokens.

## Description
The three Mohapi button variants — primary lime pill, secondary ink pill, outline
hairline ring — each with an optional leading Lucide icon, expressed through one
variant enum and a `.spec()` token map.

## Purpose
Serves Objective 1 / DoD 1, and Goals 1 & 3 (token-driven, variant-enum pattern).
Buttons are the most-used kit primitive; every screen leans on them.

## Goal
An `AppButton` widget rendering all three variants from tokens, on the gallery.

## Tasks
- [x] Define the `AppButton` variant enum — primary / secondary / outline
- [x] Implement `.spec()` mapping each variant to design-system tokens (lime pill / ink pill / outline ring)
- [x] Add an optional leading Lucide icon slot
- [x] Wire pressed + disabled states from tokens
- [x] Drive every value via `.spec()` → tokens — no hardcoded colours/sizes
- [x] Add all three variants to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: lime pill, ink pill, outline ring — each with optional icon, vs spec
$ flutter test test/components/app_button_test.dart       # variant→spec golden, if added
$ grep -n "Color(0x\|EdgeInsets.all([0-9]" lib/components/app_button.dart   # expect none
```
