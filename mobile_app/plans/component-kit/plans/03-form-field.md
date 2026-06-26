# ✍️ Form Field — Leading-Glyph Input

## Background
On `design-system/` tokens (not yet built); `.spec()`-style state mapping.

## Description
The leading-glyph input field (`#` for account, `R` for amount) with a sky-500
focus ring, a negative error ring, and a muted/disabled state.

## Purpose
Serves Objective 3 / DoD 3, and Goals 1 & 3. Used wherever the app takes account
or amount input.

## Goal
An `AppFormField` widget with glyph + the three ring states, all from tokens.

## Tasks
- [x] Build the field with a leading-glyph slot (`#` account / `R` amount)
- [x] Implement the sky-500 focus ring from tokens
- [x] Implement the negative (error) ring state
- [x] Implement the muted/disabled state
- [x] Drive every value via tokens — no hardcoded colours/sizes
- [x] Add the field (all states) to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: field with #/R glyph; focus→sky ring, error→negative ring, disabled→muted, vs spec
$ flutter test test/components/app_form_field_test.dart
$ grep -n "Color(0x" lib/components/app_form_field.dart   # expect none
```
