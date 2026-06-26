# Screens — The Five Mohapi V1 Screens, Assembled & Navigable

## Mission
Assemble the five Mohapi Design System V1 screens — Splash, Home, Pay, Success,
Usage — by composing the `component-kit/` widgets on the `design-system/` token
layer, wired into an end-to-end navigable app with `go_router`, localised to
Emfuleni and South African Rand, and faithful to the spec screenshots.

## Objectives
1. Build the Splash screen (dark ink-900, lime droplet logo with glow, carousel
   dots, headline + subhead, "Get started" lime button).
2. Build the Home screen (light; "Hi {name}" greeting + bell; lime balance card;
   5-action quick row — Pay / Bills / Usage / Auto-pay / More; sky tip banner;
   "Your bills" list of rows + badges; dark floating tab bar).
3. Build the Pay screen (light; back button; AMOUNT DUE hero display; due badge;
   line-item breakdown card — supply / wastewater / standing / total; payment-
   method card; sticky "Pay R…" button; secured footer).
4. Build the Success screen (dark ink-900; lime glow check circle; "Payment
   sent"; amount in lime; receipt line; "Done" button).
5. Build the Usage screen (light; Water / Council-tax toggle; usage card — m³,
   +% vs last month, period dropdown, sky line chart; History list; tab bar).
6. Wire navigation with `go_router`: Splash → Home; Home → Pay → Success; Home
   tab → Usage.

## Goals
1. All five screens are assembled purely by composing `component-kit/` widgets —
   no per-screen restyling, no hardcoded colours/sizes.
2. The app navigates end-to-end: Splash → Home → Pay → Success, and Home → Usage,
   via `go_router`.
3. Every screen matches its Mohapi V1 spec screenshot at the agreed fidelity bar,
   in the correct brightness (ink-900 dark on Splash/Success; light elsewhere).
4. All money displays in R with SA formatting; no £ remains anywhere.
5. Domain content is Emfuleni-localised (names, bill types, council-tax usage).

## Expected Outcome
A runnable EasyRates app a stakeholder can click through end-to-end — landing on
Splash, reaching Home, paying a bill through to the Success confirmation, and
viewing Usage — visually faithful to Mohapi V1 and entirely in Emfuleni/Rand
terms.

## Definition of Done
1. Splash: dark ink-900, lime droplet logo with glow, carousel dots, headline +
   subhead, "Get started" lime button.
2. Home: light, "Hi {name}" + bell, lime balance card, 5-action quick row, sky
   tip banner, "Your bills" rows + badges, dark tab bar.
3. Pay: light, back button, AMOUNT DUE hero, due badge, line-item breakdown
   (supply / wastewater / standing / total), payment-method card, sticky
   "Pay R…" button, secured footer.
4. Success: dark ink-900, lime glow check circle, "Payment sent", amount in lime,
   receipt line, "Done" button.
5. Usage: light, Water / Council-tax toggle, usage card (m³, +% vs last month,
   period dropdown, sky line chart), History list, tab bar.
6. Navigation wired with `go_router`: Splash → Home; Home → Pay → Success; Home
   tab → Usage.
7. All five render, navigate, display R, and pass the fidelity check.

## Sub-Scopes
(none)

## Plans
- ✅ 01-splash.md
- ✅ 02-home.md
- ✅ 03-pay.md
- ✅ 04-success.md
- ✅ 05-usage.md
- ✅ 06-navigation.md
