# 💳 Balance Card

## Background
On `design-system/` tokens (not yet built). Displays money — R, SA formatting.

## Description
The lime-surface balance card: TOTAL OWED display figure, masked card digits,
account-holder name and due date.

## Purpose
Serves Objective 4 / DoD 4, and Goals 1, 3 & 4 (R formatting). The Home screen's
hero element.

## Goal
An `AppBalanceCard` widget rendering the lime card from tokens, money in R.

## Tasks
- [x] Build the lime-surface card from tokens
- [x] Add the TOTAL OWED display figure (Space Grotesk tabular, R/SA formatting)
- [x] Add masked card digits
- [x] Add account-holder name + due date
- [x] Drive every value via tokens — no hardcoded colours/sizes
- [x] Add the card to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: lime balance card — TOTAL OWED in R, masked digits, name+due — vs spec
$ flutter test test/components/app_balance_card_test.dart
$ grep -n "Color(0x\|£" lib/components/app_balance_card.dart   # expect none (no raw colour, no £)
```
