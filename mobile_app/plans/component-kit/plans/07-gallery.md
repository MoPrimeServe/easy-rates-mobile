# 🖼️ Component Gallery

## Background
Depends on `01`–`06` existing; this is the screen that renders them all. The
aggregate fidelity-review surface for the kit.

## Description
A gallery screen that renders every kit component (all button variants, all five
badges, the form field's states, the balance card, bill rows, the tab bar) for
side-by-side comparison against the Mohapi V1 sheet.

## Purpose
Serves Objective 7 / DoD 7, and owns the **"matches its spec render"** half of
DoD 8 — it's the surface where each component is checked against the spec.
(The "used by at least one screen" half is verified downstream in `screens/`.)

## Goal
A `gallery_screen.dart` rendering all kit components, switchable light/dark.

## Tasks
- [x] Build the gallery screen scaffold with light/dark brightness toggle
- [x] Render all button variants, all five badges, the form-field states
- [x] Render the balance card, representative bill rows, and the tab bar
- [x] Lay out sections so each cluster sits beside its spec reference
- [x] Fidelity pass: compare every component to the Mohapi V1 sheet, note gaps

## Recommended skill
— custom; no skill fits (Flutter gallery assembly + fidelity review; project-specific).

## Engagement Instructions
```
$ flutter run    # gallery renders every component; toggle light/dark; compare each to the Mohapi sheet
$ flutter test test/components/   # all component golden tests green
# spec-match checklist: buttons ✓ badges ✓ field ✓ balance card ✓ bill row ✓ tab bar ✓
```
