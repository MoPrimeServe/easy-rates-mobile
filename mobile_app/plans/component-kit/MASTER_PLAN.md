# Component Kit — Mohapi V1 Reusable Widgets

## Mission
Build every component on Mohapi's component sheet as a reusable, theme-driven
Flutter widget that reads the `design-system/` token layer and never hardcodes a
value, localised to South African Rand. Each component follows the capstone's
established architecture — a variant `enum` plus a `.spec()` method that maps the
variant to tokens (the `AppButton` pattern) — so the kit is uniform and
extensible.

## Objectives
1. Build the three button variants (primary lime pill, secondary ink pill,
   outline hairline ring) with optional leading Lucide icon, on the existing
   `AppButton` variant-enum + `.spec()` pattern.
2. Build the five status badges (Paid, Due, Past due, Auto-pay on, New bill) each
   with its semantic colour + Lucide glyph.
3. Build the form-field component (leading-glyph input for `#` account / `R`
   amount) with sky-500 focus ring, negative error ring, and a muted/disabled
   state.
4. Build the balance card (lime surface, TOTAL OWED display figure, masked card
   digits, name + due date).
5. Build the bill row (icon tile + title + subtitle + signed amount + trailing
   status badge).
6. Build the dark floating tab bar (5 Lucide icons — house / receipt / droplet /
   bell / user — with a lime active pill).
7. Build a gallery screen that renders every component for fidelity review.

## Goals
1. All seven clusters exist as reusable, theme-driven widgets driving every value
   from `design-system/` tokens — zero hardcoded colours/sizes.
2. Every component matches its Mohapi V1 spec render.
3. Buttons, badges, fields, and the tab bar are all expressed through the variant-
   enum + `.spec()` token-mapping pattern, not bespoke per-instance styling.
4. All money is displayed in R with SA formatting; signed amounts on bill rows
   render their sign correctly.
5. The gallery screen renders all components together for side-by-side fidelity
   review against the spec.

## Expected Outcome
A `easy_rates/mobile_app/lib/components/` library where every Mohapi V1 component is a
single, reusable, token-driven widget. Assembling a screen means composing these
widgets — there is no per-screen restyling. The gallery screen is the visual
proof that the kit matches the sheet.

## Definition of Done
1. Buttons: primary (lime pill), secondary (ink pill), outline (hairline ring),
   each supporting an optional leading Lucide icon, via variant-enum + `.spec()`.
2. Status badges: Paid (positive + check), Due (warning + clock), Past due
   (negative + circle-alert), Auto-pay on (ink + repeat), New bill (sky +
   file-text).
3. Form field: leading-glyph input (# account / R amount), sky-500 focus ring,
   negative error ring, and a muted/disabled state.
4. Balance card: lime surface, TOTAL OWED display figure, masked card digits,
   name + due date.
5. Bill row: icon tile + title + subtitle + signed amount + trailing status badge.
6. Dark floating tab bar: 5 Lucide icons (house / receipt / droplet / bell /
   user), lime active pill.
7. Gallery screen renders every component.
8. Each component matches its spec render and is used by at least one screen.

## Sub-Scopes
(none)

## Plans
- ✓ 01-buttons.md
- ✓ 02-status-badges.md — widget renamed `AppBadge` / `AppBadgeVariant` during implementation
- ✓ 03-form-field.md
- ✓ 04-balance-card.md
- ✓ 05-bill-row.md
- ✓ 06-tab-bar.md
- ✓ 07-gallery.md
