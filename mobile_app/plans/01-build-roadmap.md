# 🗺️ Build Roadmap

## Description
The top-level work breakdown for `easy_rates/mobile_app` — the EasyRates Flutter front end
built to Mohapi V1 and localised to Emfuleni/Rand. Each task below is one cluster
of work. The three large clusters (design system, component kit, screens) are
sized to become their own sub-scopes via `decompose-plan`; scaffold, verification,
and capstone-retirement stay as tasks at this level.

## Purpose
Give the scope a concrete spine so `decompose-plan` has task lines to spawn
sub-scopes from, and so the dependency order is explicit:
environment → scaffold → design system → component kit → screens, with
fidelity-verification running alongside from the moment there is something to
verify.

## Goal
A populated plan tree: scaffold + verification planned here, and
`plans/design-system/`, `plans/component-kit/`, `plans/screens/` each spun out as
sub-scopes with their own MASTER_PLAN.md and plans/. From there, every task is a
runnable prompt.

## Tasks
- [x] Stand up the Dart + Flutter toolchain (prerequisite — do this first)  → decomposed: see `plans/environment/MASTER_PLAN.md`
- [x] Scaffold the Flutter project — landed at `easy_rates/mobile_app/easy_rates_app/` (not root of mobile_app/); pubspec has provider, go_router, lucide_icons_flutter, SpaceGrotesk + Manrope bundled fonts; `lib/{theme,components,screens}` in place.
- [x] Build the **design system** — light + dark token store, brightness switch, Space Grotesk + Manrope, Lucide icons wired.  → decomposed: see `plans/design-system/MASTER_PLAN.md`
- [x] Build the **component kit** — 3-variant AppButton + .spec(), 5 AppBadge states, AppFormField, AppBalanceCard, AppBillRow, AppTabBar, gallery screen.  → decomposed: see `plans/component-kit/MASTER_PLAN.md`
- [x] Assemble the **five screens** — Splash, Home, Pay, Success, Usage; go_router wired; Emfuleni/Rand-localised.  → decomposed: see `plans/screens/MASTER_PLAN.md`
- [ ] Establish **fidelity verification** — `no_hardcoded_design_values_test.dart` covers the no-hardcode half (token-parity audit passes); render-vs-spec screenshot comparison not yet wired. Remaining: decide and wire the visual comparison method.
- [ ] Retire the `learning/` capstone to reference — note in its README that
  `easy_rates/mobile_app/easy_rates_app/` is the product; nothing is imported from `learning/` into the app.

## Engagement Instructions
The roadmap is "done" as a planning artifact when the tree has spun out its
sub-scopes. Verify the structure:

```
$ find easy_rates/mobile_app -name MASTER_PLAN.md | sort
easy_rates/mobile_app/MASTER_PLAN.md
easy_rates/mobile_app/plans/component-kit/MASTER_PLAN.md
easy_rates/mobile_app/plans/design-system/MASTER_PLAN.md
easy_rates/mobile_app/plans/screens/MASTER_PLAN.md
# each sub-scope also has a non-empty plans/ folder:
$ ls easy_rates/mobile_app/plans/design-system/plans easy_rates/mobile_app/plans/component-kit/plans easy_rates/mobile_app/plans/screens/plans
```

Each decomposed task line above should carry its
`→ decomposed: see plans/<sub-scope>/MASTER_PLAN.md` link once spun out.
