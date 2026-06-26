# ✅ Token Parity + No-Hardcode Audit

## Description
Verify the full token surface exists in both brightnesses, and that nothing
downstream hardcodes a colour or size.

## Purpose
DoD 5 (full parity) + DoD 6 (no leaks). This is the scope's completion gate — it
proves the design system is the single source of truth.

## Goal
A passing parity check (every spec token present in both brightnesses) and a
clean grep audit (zero raw `Color(`, hex literals, or magic numbers outside
`lib/theme/`).

## Tasks
- [x] Parity check: every spec token (colours, 4px spacing, radii 8/16/22/28/36/pill, type ramp) present in BOTH light and dark
- [x] Grep audit over `lib/` for raw `Color(`, hex literals, magic numbers outside the theme layer
- [x] Fix or tokenize any leaks the audit finds
- [x] (Optional) add a CI/lint guard so new hardcoded values fail fast

## Engagement Instructions
```
$ flutter test test/theme/token_parity_test.dart   # both brightnesses cover the spec sheet
$ grep -rnE "Color\(0x|#[0-9A-Fa-f]{6}" lib/ --include=*.dart | grep -v lib/theme/   # expect no matches
```
A clean run of both — the parity test green and the grep returning nothing — is
the signal that the design-system scope is done.
