# 🧭 Navigation — go_router Wiring & End-to-End Pass

## Background
Wires the five assembled screens (01–05) together. Depends on those plans being
done; this plan connects them and owns the end-to-end acceptance.

## Description
Configure `go_router` and wire the full navigation graph: Splash → Home;
Home → Pay → Success; Home tab → Usage; Success "Done" → Home. Then run the
end-to-end fidelity pass.

## Purpose
Serves Objective 6 / DoD 6, and owns DoD 7 — the aggregate "all five render,
navigate, display R, and pass the fidelity check."

## Goal
A runnable EasyRates app navigable end-to-end via `go_router`, click-through
faithful to Mohapi V1 in correct per-screen brightness, entirely in R.

## Tasks
- [x] Add the `go_router` dependency and a `GoRouter` config (e.g. `lib/router.dart`)
- [x] Define routes for splash / home / pay / success / usage
- [x] Wire Splash → Home ("Get started")
- [x] Wire Home → Pay → Success (Pay action → "Pay R…" button)
- [x] Wire Home tab → Usage (tab bar)
- [x] Wire Success "Done" → Home
- [x] End-to-end pass: click Splash→Home→Pay→Success and Home→Usage; confirm R everywhere (no £) and correct brightness per screen (DoD 7)

## Engagement Instructions
```
$ flutter run
# Click through: Splash → (Get started) → Home → (Pay) → Pay → (Pay R…) →
#   Success → (Done) → Home → (Usage tab) → Usage.
# expect: every transition works via go_router; no £ anywhere; Splash & Success
#         dark ink-900, others light; all screens match their spec.
$ flutter test                # all screen golden tests green
```

## Recommended skill
— custom; no skill fits (go_router wiring + end-to-end fidelity; project-specific).
