# Environment & Toolchain — Dart + Flutter on WSL2

## Mission
Stand up a working Dart + Flutter development environment on this WSL2 host and
prove it end to end, so every downstream mobile_app scope (design-system,
component-kit, screens) builds, analyses, and runs on a trusted toolchain.
Targets: web / Linux desktop for fast iteration, plus a Windows-hosted Android
emulator for real on-device rendering.

## Objectives
1. Install the Flutter SDK (stable) + bundled Dart, on PATH, with VS Code Dart/
   Flutter IDE support.
2. Provision the fast baseline run targets — web (Chrome) and/or Linux desktop —
   with their platform deps.
3. Provision a Windows-hosted Android emulator and bridge it into WSL2 over adb,
   so `flutter run` can deploy to it.
4. Get `flutter doctor` green for the chosen targets and prove the toolchain with
   a throwaway hello-world that renders on both a baseline target AND the Android
   emulator.
5. Pin the chosen Flutter + Dart versions so the project uses one toolchain.

## Goals
1. `flutter doctor` is green for web/Linux desktop and the Android toolchain.
2. `flutter devices` lists both a baseline target and the Windows-hosted Android
   emulator (via adb).
3. A throwaway hello-world launches and the counter increments on BOTH a baseline
   target (Chrome/Linux) and the Android emulator.
4. The Flutter + Dart versions are recorded in the repo.

## Expected Outcome
A developer on this WSL2 box can `flutter run` to a Windows-hosted Android
emulator and to web/Linux desktop, with `flutter doctor` green. The throwaway
hello-world proves it; the real mobile_app scaffold can then proceed on a trusted
toolchain.

## Definition of Done
1. Flutter SDK (stable) + Dart installed, on PATH; `flutter --version` = 3.x / Dart 3.x.
2. VS Code Dart + Flutter extensions installed.
3. Web (Chrome) and/or Linux desktop works; desktop deps installed (clang / cmake /
   ninja-build / libgtk-3-dev).
4. Android toolchain installed (Android Studio / SDK + cmdline-tools), emulator
   created on the Windows host, adb bridged into WSL2; `flutter devices` shows it.
5. `flutter doctor` green (no blocking ✗) for web/desktop + Android.
6. Throwaway hello-world renders and increments on BOTH a baseline target and the
   Android emulator.
7. Flutter + Dart versions pinned in a repo note.
8. ❌ (deferred) iPhone tethered run — out of scope on WSL2; revisit only with a
   Mac + Xcode.

## Sub-Scopes
(none)

## Plans
- ✅ 01-sdk-and-ide.md
- ✅ 02-android-emulator.md
- ✅ 03-doctor-and-hello-world.md
- ✅ 04-pin-versions.md
