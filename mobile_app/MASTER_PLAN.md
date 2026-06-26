# EasyRates Mobile App — Flutter, Mohapi V1 → Emfuleni

## Mission
The ratepayer-facing EasyRates mobile front end for the Emfuleni account-
intelligence platform: Mohapi's Design System V1 rendered as a real, runnable
Flutter app, faithful to the kit's look but localised to the Emfuleni domain
and South African Rand.

## Objectives
1. Stand up the repo's first real Flutter project at `easy_rates/mobile_app/` with a clean
   theme / components / screens structure.
2. Encode Mohapi V1 as the single design-system source — light AND dark surfaces.
3. Build the full component kit faithfully (3-variant buttons, 5 status badges,
   form fields, balance card, bill rows, dark floating tab bar) on Lucide icons.
4. Assemble the five spec screens (Splash, Home, Pay, Success, Usage) to the
   agreed fidelity bar, localised to Emfuleni / Rand.
5. Establish a fidelity-verification method so "faithful to the kit" is checkable.
6. Decide & document the build approach (hand-written vs AI-orchestrated) and the
   test-against-kit loop — feeding decompose-plan.

## Goals
1. `flutter run` launches and navigates Splash → Home → Pay → Success, and
   Home → Usage, end to end.
2. The theme carries the complete Mohapi V1 token set in both light and dark,
   with zero hardcoded colours/sizes in any widget.
3. Every component on Mohapi's sheet exists as a reusable, theme-driven widget
   matching the spec render.
4. All five screens render to the agreed fidelity bar against the spec images.
5. All money displays in R with SA formatting; no £ remains anywhere.
6. The scope is decomposed into runnable task prompts (one cluster per plan).

## Expected Outcome
A runnable Flutter app at `easy_rates/mobile_app/` that a stakeholder can click through as
the EasyRates ratepayer experience — visually indistinguishable from Mohapi V1
except for Emfuleni/Rand content. The `learning/` capstone is retired to reference.

## Definition of Done
1. `easy_rates/mobile_app/` is a valid Flutter project (pubspec, lib/, assets, fonts) that
   passes `flutter analyze` with no errors.
2. Light + dark themes complete; each renders its screens correctly.
3. Component kit complete and shown on a component-gallery screen.
4. Five screens assembled, navigable, Emfuleni/Rand-localised, passing the
   agreed fidelity check.
5. Space Grotesk + Manrope fonts and Lucide icons bundled and rendering.
6. Fidelity verification runs and reports pass.
7. Plan tree decomposed: each screen/component cluster has a plan file with
   engagement instructions.

## Sub-Scopes
- ✅ plans/environment/ — "stand up & prove a Dart + Flutter toolchain on WSL2"
- ✅ plans/design-system/ — "encode Mohapi V1 as the app's single design-system source"
- ✅ plans/component-kit/ — "build every Mohapi V1 component as a reusable, theme-driven widget"
- ✅ plans/screens/ — "assemble the five Mohapi V1 screens, navigable and Emfuleni/Rand-localised"

## Plans
- ⚠️ 01-build-roadmap.md (fidelity verification + capstone retirement still open)
