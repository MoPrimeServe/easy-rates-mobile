# 🧭 Floating Tab Bar

## Background
On `design-system/` tokens — specifically the **dark** ink-900 surface (not yet
built). Lucide icon set.

## Description
The dark floating tab bar: five Lucide icons (house / receipt / droplet / bell /
user) with a lime active pill behind the selected tab.

## Purpose
Serves Objective 6 / DoD 6, and Goals 1 & 3. The persistent navigation chrome on
Home and Usage.

## Goal
An `AppTabBar` widget rendering the dark bar + lime active pill from tokens.

## Tasks
- [x] Build the dark ink-900 floating bar surface from tokens
- [x] Add the five Lucide icons (house / receipt / droplet / bell / user)
- [x] Implement the lime active pill behind the selected tab
- [x] Expose selected-index + onTap so screens can drive navigation
- [x] Drive every value via tokens — no hardcoded colours/sizes
- [x] Add the tab bar to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: dark floating bar, 5 Lucide icons, lime active pill moves on tap, vs spec
$ flutter test test/components/app_tab_bar_test.dart
$ grep -n "Color(0x" lib/components/app_tab_bar.dart   # expect none
```
