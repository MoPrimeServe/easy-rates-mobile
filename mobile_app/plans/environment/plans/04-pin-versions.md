# 📌 Pin the Toolchain Versions

## Background
A proven toolchain is only reproducible if its versions are written down. Closes
the scope so the build-roadmap scaffold step starts from a known toolchain.

## Description
Capture the working Flutter + Dart versions and record them in a repo note so the
project pins one toolchain.

## Purpose
Serves Objective 5 / DoD 7 — reproducibility across the team / future sessions.

## Goal
A committed repo note records the exact Flutter + Dart versions in use.

## Tasks
- [x] Capture `flutter --version` output (Flutter version, channel, framework hash, Dart version)
- [x] Record it in a repo note (e.g. `easy_rates/mobile_app/TOOLCHAIN.md`)
- [x] Note the intended Dart SDK constraint for the future `pubspec.yaml` (handed to the scaffold step)

## Recommended skill
— custom; no skill fits (version capture + repo note; project-specific).

## Engagement Instructions
```
$ flutter --version                          # matches the pinned versions
$ cat easy_rates/mobile_app/TOOLCHAIN.md     # records Flutter + Dart versions in use
```
