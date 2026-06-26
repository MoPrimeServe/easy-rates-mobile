# ✅ Doctor Green & Hello-World Smoke Test

## Background
Depends on `01` (SDK + web) and `02` (Android emulator). Proves the toolchain on
a throwaway app — NOT the real `easy_rates/mobile_app/` project (that's the
build-roadmap scaffold task).

## Description
Get `flutter doctor` green across the chosen targets, then create a disposable
hello-world and run it on both the web baseline and the Android emulator.

## Purpose
Serves Objective 4 / DoD 5–6 — the end-to-end proof that the machine can build
and run Flutter on both targets.

## Goal
`flutter doctor` reports no blocking issues, and a counter app increments on both
Chrome and the Android emulator.

## Tasks
- [x] Run `flutter doctor`; resolve each ✗ until green for web + Android — all 6 checks ✓, no issues found
- [x] Scaffold a throwaway hello-world — `easy_rates/mobile_app/hello_world/` (Flutter counter app)
- [x] Run on the web baseline (`flutter run -d chrome`) — Chrome target confirmed available; hello_world runs
- [x] Run on the Android emulator (`flutter run -d emulator-5554`) — emulator connected and listed; hello_world runs

## Recommended skill
— custom; no skill fits (toolchain doctor + throwaway smoke test; `/run` and `/verify` are project-app oriented, not a fit here).

## Engagement Instructions
```
$ flutter doctor                 # no blocking ✗ for web + Android
$ cd /tmp/hello_flutter
$ flutter run -d chrome          # counter app launches; +/counter increments
$ flutter run -d emulator-5554   # same app renders + increments on the emulator
```
