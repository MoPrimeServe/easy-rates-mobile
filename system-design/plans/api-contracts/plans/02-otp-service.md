# 📱 OTP Service Contract

## Background

✅ GATE CLEARED (2026-06-22) — both prerequisites are written: `api/conventions.md` and
`docs/twilio-integration.md` (`OTP_TTL_SECONDS=600`, `OTP_RESEND_COOLDOWN_SECONDS=30`). The
Twilio lifecycle parameters are locked, so the OTP API contract was free to be written.

The OTP service is used in two Figma flows: ONBOARDING (verify phone on registration)
and the login step (verify phone on every login). The `ttlSeconds` and
`resendCooldownSeconds` fields are machine-readable integers in every OTP response —
they drive the Flutter countdown timer and the "resend" button disabled state.

## Description

Write the HTTP API contract for the OTP service: send, verify, resend. Every response
includes `ttlSeconds` (seconds until OTP expires) and `resendCooldownSeconds` (seconds
until resend is allowed). Defines 4 service-specific error codes.

## Purpose

To answer: "what happens on the Flutter OTP screen if the network is slow and the
OTP expires before the user receives it — and which response field drives the countdown
timer and the resend button, so the Flutter developer never hardcodes these values?"

## Goal

`easy_rates/system-design/api/otp-service.md` — 3 routes with TypeScript interfaces;
`ttlSeconds` and `resendCooldownSeconds` present in every response; 4 error codes
with exact shapes.

## Tasks

- [x] ✅ THINK `/socratic "What happens to the Flutter OTP screen if the OTP expires
  during the countdown — and which field in the API response drives the countdown
  timer so the Flutter developer doesn't hardcode it? What is the worst-case scenario
  for a user who receives the OTP code late (e.g. Twilio delivery delay) — and which
  error code tells the Flutter app to show 'OTP expired, please request a new one'
  rather than 'incorrect code'?"`
  Done when: countdown timer field identified; expiry-during-delivery scenario
  addressed; otp_expired vs otp_invalid error codes distinguished.

- [x] ✅ FIGMA-TRACE Map every OTP-related screen transition in ONBOARDING and LOGIN
  flows to an HTTP call:
  "Send code" button → POST /api/v1/otp/send
  OTP input submitted → POST /api/v1/otp/verify
  "Resend" button → POST /api/v1/otp/resend
  For each: which Flutter widget triggers it; which response field updates the UI.
  Done when: all OTP screen transitions mapped; countdown timer field identified in
  the send/resend response.

- [x] ✅ SEND Define `POST /api/v1/otp/send`:
  Request: `{ phoneNumber: string, purpose: "REGISTRATION" | "LOGIN" }`
  Response 200: `{ data: { ttlSeconds: number, resendCooldownSeconds: number,
    maskedPhone: string }, error: null }`
  `ttlSeconds`: integer; the Flutter countdown timer starts from this value.
  `resendCooldownSeconds`: integer; the "resend" button is disabled for this many
  seconds after send.
  `maskedPhone`: e.g. "+27****1234" — displayed on the OTP screen.
  Errors: 429 rate_limit_exceeded (detail: resendCooldownSeconds remaining),
  404 not_found (phone not registered, for LOGIN purpose)
  TypeScript interface: `OtpSendRequest`, `OtpSendResponse`
  Done when: shapes defined; `ttlSeconds` and `resendCooldownSeconds` are integers.

- [x] ✅ VERIFY-ROUTE Define `POST /api/v1/otp/verify`:
  Request: `{ phoneNumber: string, code: string, purpose: "REGISTRATION" | "LOGIN" }`
  Response 200 (REGISTRATION): `{ data: { verificationToken: string }, error: null }`
    — `verificationToken` is a short-lived token passed to the register endpoint
    to prove phone ownership.
  Response 200 (LOGIN): `{ data: { accessToken: string, refreshToken: string,
    accessTokenTtlSeconds: number }, error: null }`
    — on LOGIN verify success, auth tokens are returned directly.
  Errors:
  `otp_invalid` (wrong code entered)
  `otp_expired` (TTL elapsed before verify was called)
  `max_attempts_exceeded` (too many wrong attempts; account locked for N minutes)
  TypeScript interface: `OtpVerifyRequest`, `OtpVerifyLoginResponse`,
  `OtpVerifyRegisterResponse`
  Done when: two response shapes (LOGIN and REGISTRATION) defined separately.

- [x] ✅ RESEND Define `POST /api/v1/otp/resend`:
  Request: `{ phoneNumber: string, purpose: "REGISTRATION" | "LOGIN" }`
  Response 200: `{ data: { ttlSeconds: number, resendCooldownSeconds: number },
    error: null }`
  Errors: 429 `resend_cooldown_active` (resend requested before cooldown expired;
  `details.retryAfterSeconds` = remaining cooldown)
  Note: resend generates a new OTP code; the previous code is invalidated.
  TypeScript interface: `OtpResendRequest`, `OtpResendResponse`
  Done when: shapes defined; cooldown error has `retryAfterSeconds` in details.

- [x] ✅ ERRORS Lock in the 4 OTP-specific error codes:
  `otp_invalid` — wrong code; `details.attemptsRemaining: number`
  `otp_expired` — TTL elapsed; `details.ttlSeconds: 0`
  `max_attempts_exceeded` — account locked; `details.unlockAfterMinutes: number`
  `resend_cooldown_active` — resend too soon; `details.retryAfterSeconds: number`
  Flutter implication for each: which UI state does the Flutter OTP screen enter?
  Done when: 4 codes defined; details shape for each; Flutter UI state for each.

- [x] ✅ WRITE Write `easy_rates/system-design/api/otp-service.md`:
  3 routes; TypeScript interfaces; 4 error codes; Figma Trace section; rate-limit
  note referencing security/rate-limits.md OTP category.
  Done when: file exists; `ttlSeconds` and `resendCooldownSeconds` in every response;
  4 error codes defined.

- [x] ✅ VERIFY Cross-reference with twilio-integration.md: confirm `ttlSeconds`
  value in the OTP send response matches the Twilio OTP TTL configured in that plan.
  Confirm: `resendCooldownSeconds` is compatible with the OTP rate limit from
  security/rate-limits.md (rate limit window must be ≥ resend cooldown).
  Done when: Twilio TTL match confirmed; rate limit compatibility confirmed.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "expiry-during-delivery" scenario forces the
   `ttlSeconds` field to be justified as the countdown timer driver, not a
   documentation detail.
   — custom for contract writing.

## Engagement Instructions

Pass condition: `ttlSeconds` and `resendCooldownSeconds` are integers in every OTP
send and resend response.
Pass condition: 4 error codes defined with `details` shapes.
Pass condition: two separate response shapes for verify (LOGIN vs REGISTRATION).
Pass condition: Figma Trace section maps every OTP screen transition.
Pass condition: `ttlSeconds` value in contract matches twilio-integration.md.

## Sync Note — 2026-06-22

All 8 tasks completed this session and verified against the canonical `api/otp-service.md`
plus the Flutter implementation (`mobile_app/easy_rates_app/lib/services/{otp_service,auth_service}.dart`,
`lib/screens/otp/otp_screen.dart`, `lib/screens/signup/signup_screen.dart`). Task 8 cross-check
confirmed: contract `ttlSeconds 600` == `docs/twilio-integration.md` `OTP_TTL_SECONDS 600`;
resend cooldown `30 s` ≤ OTP-SEND window `600 s` (`docs/security/rate-limits.md`). **Plan
aggregates to ✅ done.** Parent `plans/api-contracts/MASTER_PLAN.md` Plans entry for this file
→ ✅ done (apply on the next wider sync).

**Implemented-as divergences** — the task text above is the *original ask*; the contract was
built to canonical per decisions made this session (ADR-002 + the system-design contract). The
task text is kept as historical record:
- **SEND:** `phone` (not `phoneNumber`); `maskedPhone` is returned by the auth-initiate
  endpoints (`register/start`, `login`), not by `/otp/send`; no `404` (anti-enumeration).
- **VERIFY-ROUTE:** `registrationToken` (not `verificationToken`);
  `accessTokenExpiresInSeconds` (not `accessTokenTtlSeconds`); **no account lockout**.
- **ERRORS:** `max_attempts_exceeded` carries `details.maxAttempts` — **no `unlockAfterMinutes`**
  (no lockout, ADR-002); `otp_expired.details.ttlSeconds: 0` (matches the ask).
- **WRITE:** `ttlSeconds` + `resendCooldownSeconds` appear in the dispatch responses
  (send/resend) and the auth-initiate responses, but **deliberately not** in the terminal
  verify-success token responses (nothing left to count down).
