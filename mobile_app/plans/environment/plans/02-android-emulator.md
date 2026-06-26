# 🤖 Android Emulator — Windows-Hosted, adb-Bridged

## Background
WSL2 can't run the Android emulator well (nested virtualisation). The reliable
pattern: run the AVD on the **Windows** host, and bridge `adb` so WSL2's Flutter
can see and deploy to it. This is the hardest piece of the scope.

## Description
Install the Android toolchain, create and launch an emulator on the Windows host,
and bridge adb into WSL2 so `flutter devices` lists it.

## Purpose
Serves Objective 3 / DoD 4 — the real on-device render target you asked for.

## Goal
`flutter devices` (run in WSL2) lists the Windows-hosted Android emulator and can
deploy to it.

## Tasks
- [x] Install Android Studio + Android SDK (+ platform-tools, cmdline-tools) on the Windows host — SDK version 36.1.0
- [x] Create an AVD (e.g. Pixel, recent API level) and launch the emulator on Windows — `sdk gphone16k x86 64` (API 37)
- [x] Install Android SDK platform-tools (`adb`) accessible from WSL2; point Flutter at the SDK
- [x] Bridge adb WSL2→Windows emulator — `emulator-5554` reachable from WSL2
- [x] Accept Android licences (`flutter doctor --android-licenses`)
- [x] Confirm the emulator shows up from WSL2 — `flutter devices` lists `emulator-5554`

## Recommended skill
— custom; no skill fits (Android toolchain + WSL2 adb bridge; project-specific).

## Engagement Instructions
```
$ adb devices                    # the emulator listed (e.g. emulator-5554  device)
$ flutter devices                # shows "sdk gphone…" Android target from WSL2
```
