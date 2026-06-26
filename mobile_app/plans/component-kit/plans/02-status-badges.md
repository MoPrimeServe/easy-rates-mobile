# 🏷️ Status Badges — Five States

## Background
Variant-enum + `.spec()` pattern on `design-system/` tokens (not yet built).

## Description
The five Mohapi status badges — Paid, Due, Past due, Auto-pay on, New bill — each
a semantic colour + Lucide glyph, via one variant enum and `.spec()`.

## Purpose
Serves Objective 2 / DoD 2, and Goals 1 & 3. Badges annotate bill rows and the
Pay screen's due state.

## Goal
An `AppBadge` widget rendering all five states from tokens, on the gallery.

## Tasks
- [x] Define the badge variant enum — paid / due / pastDue / autoPay / newBill
- [x] Implement `.spec()` mapping each to its semantic colour + Lucide glyph (check / clock / circle-alert / repeat / file-text)
- [x] Render pill shape, label, and glyph from tokens
- [x] Drive every value via `.spec()` → tokens — no hardcoded colours/sizes
- [x] Add all five badges to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: five badges — Paid/Due/Past-due/Auto-pay/New — colour+glyph vs spec
$ flutter test test/components/app_badge_test.dart
$ grep -n "Color(0x" lib/components/app_badge.dart   # expect none
```
