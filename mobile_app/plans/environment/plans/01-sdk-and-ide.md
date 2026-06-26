# 🛠️ Flutter SDK & IDE

## Background
WSL2 host. The Flutter SDK bundles Dart, so one install covers both. Web (Chrome)
is the fast baseline run target; the Android emulator comes in `02`.

## Description
Install the Flutter SDK on PATH, wire up VS Code's Dart + Flutter extensions, and
enable the web target with a quick Chrome sanity run.

## Purpose
Serves Objectives 1–2 / DoD 1–2 (and the web baseline of DoD 3). Nothing else in
the scope can proceed without the SDK on PATH.

## Goal
`flutter --version` reports Flutter 3.x / Dart 3.x, the IDE has Flutter support,
and a counter app runs in the browser.

## Tasks
- [x] Install the Flutter SDK (stable channel) into a dev dir (git clone or tarball)
- [x] Add `flutter/bin` to PATH in `~/.bashrc`; `flutter precache`
- [x] Confirm bundled Dart (`dart --version`) — Dart 3.12.1
- [x] Install the VS Code **Dart** + **Flutter** extensions — `dart-code.dart-code` + `dart-code.flutter` present
- [x] Enable web (`flutter config --enable-web`); Chrome reachable from WSL2 — `flutter doctor` shows Chrome ✓
- [x] (optional) Linux desktop deps — `clang cmake ninja-build libgtk-3-dev` — `flutter doctor` shows Linux toolchain ✓

## Recommended skill
— custom; no skill fits (host SDK install + IDE setup; project-specific).

## Engagement Instructions
```
$ flutter --version              # Flutter 3.x (stable) + Dart 3.x
$ dart --version                 # Dart 3.x (bundled)
$ code --list-extensions | grep -iE "dart-code|flutter"   # both present
$ flutter config | grep enable-web    # enable-web: true
```
