# 🧾 Bill Row

## Background
On `design-system/` tokens (not yet built). Composes the `02-status-badges`
widget as its trailing element. Money in R.

## Description
The bill list row: an icon tile, title + subtitle, a signed amount, and a
trailing status badge.

## Purpose
Serves Objective 5 / DoD 5, and Goals 1, 3 & 4 (signed amounts render their sign
correctly, in R). Repeated down the Home "Your bills" list.

## Goal
An `AppBillRow` widget rendering from tokens, with correct signed-R amounts.

## Tasks
- [x] Build the row layout — icon tile + title/subtitle + amount + trailing slot
- [x] Render the signed amount in R with the correct +/− sign and colour from tokens
- [x] Slot in the status badge (`02-status-badges`) as the trailing element
- [x] Drive every value via tokens — no hardcoded colours/sizes
- [x] Add a few representative rows to the gallery screen

## Recommended skill
— custom; no skill fits (token-driven Flutter widget to spec; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery: bill rows — icon/title/subtitle, signed R amount, trailing badge — vs spec
$ flutter test test/components/app_bill_row_test.dart      # incl. +/− sign rendering
$ grep -n "Color(0x\|£" lib/components/app_bill_row.dart    # expect none
```
