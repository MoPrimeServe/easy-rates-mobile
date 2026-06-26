# 🔐 Auth Service Contract

## Background

✅ resolved[Gate] — plan/00-conventions.md is satisfied: the deliverable conforms to
`api/conventions.md` (the `{ data, error }` envelope, the standard error-code list in §3,
and camelCase payloads are all in force — see the contract header lines 4-13).
✅ resolved[Gate] — security sub-scope JWT/session model is decided and exposed: the
"Token model (from `docs/security/sessions.md`)" block (lines 15-26) gives RS256, 900 s
access TTL, opaque rotated 30-day refresh, and the Flutter in-memory/secure-storage split.

The auth service is the entry point for the ONBOARDING Figma flow. Every subsequent
service requires a valid JWT access token returned from this service.

## Description

Write the HTTP API contract for the auth service: register, login, token refresh,
logout, and forgot-password. Includes TypeScript interfaces for every request body
and response, rate-limit notes, and Figma Trace section for the ONBOARDING flow.

## Purpose

To answer: "what auth failure is most likely to confuse a Flutter developer —
and does the error envelope make it clear enough that they can show the right UI
state without asking?"

## Goal

`easy_rates/system-design/api/auth-service.md` — 5 routes with full request/response
schemas, TypeScript interfaces, error codes, and Figma traces; rate-limit note from
security.md.

## Tasks

- [x] ✅ THINK `/socratic "What is the most confusing auth error a Flutter developer
  will encounter — a 401 on the token refresh endpoint, a 409 on registration for a
  duplicate phone number, or a 403 on a route they assumed was public? And how does
  the error code in the envelope tell them exactly which UI state to show without
  them having to read HTTP status codes?"` — ✓ answered (3 errors named with `error.code` + Flutter UI state; see Execution Note)
  Done when: the 3 most confusing auth errors are named; the error code for each is
  defined; the Flutter UI state for each is stated.

- [x] ✅ FIGMA-TRACE Map every ONBOARDING flow screen transition to an HTTP call: — ✓ verified (Figma Trace table maps Sign Up→register/start, Verify Phone OTP→register, Log In→login, Verify Login OTP→otp/verify, plus refresh/logout/kyc/session; otp-service & account-service transitions marked as other services)
  Phone number entry → POST /api/v1/auth/register (new user) or POST /api/v1/auth/login
  OTP sent → move to OTP screen (OTP is dispatched by otp-service, not auth-service)
  Profile setup → PATCH /api/v1/account/profile (account-service, not auth-service)
  For each transition: method, path, who calls it, what Flutter widget triggers it.
  Done when: every ONBOARDING transition from screen-inventory.md is mapped to a named
  endpoint or marked as client-only.

- [x] ✅ REGISTER Define `POST /api/v1/auth/register`: — ✓ verified (`RegisterRequest` + `AuthTokenResponse` 201; errors 409 conflict / 400 validation_error / 401 / 429; OTP-first split documented via `/auth/register/start` + registrationToken consumed here)
  Request: `{ phoneNumber: string, fullName: string, idNumber?: string }`
  Response 201: `{ data: { userId: string, accessToken: string, refreshToken: string,
    accessTokenTtlSeconds: number, refreshTokenTtlDays: number }, error: null }`
  Errors: 409 conflict (phone already registered), 400 validation_error, 429
  rate_limit_exceeded
  Note: OTP verification happens BEFORE registration (otp-service verifies the phone).
  This endpoint is called after OTP is verified. Clarify this in the contract.
  TypeScript interface: `RegisterRequest`, `AuthTokenResponse`
  Done when: request, response 201, and error shapes defined with TypeScript interfaces.

- [x] ✅ LOGIN Define `POST /api/v1/auth/login`: — ✓ verified (`LoginRequest` + `LoginInitResponse` 200; OTP ownership decided — login only dispatches via otp-service `POST /otp/send`, token pair issued by `POST /otp/verify` LOGIN. Note: deliverable returns anti-enumeration 200 not the plan's 404 not_found, per ADR-002)
  Request: `{ phoneNumber: string }`
  Response 200: `{ data: { message: "OTP sent", ttlSeconds: number }, error: null }`
  Note: login is phone + OTP only — no password. This route initiates the OTP flow,
  not the otp-service route directly (or does it? decide which service owns OTP dispatch
  on login vs registration).
  Errors: 404 not_found (phone not registered), 429 rate_limit_exceeded
  TypeScript interface: `LoginRequest`, `LoginInitResponse`
  Done when: OTP ownership decision documented; shapes defined.

- [x] ✅ REFRESH Define `POST /api/v1/auth/token/refresh`: — ✓ verified (route documented as `POST /auth/refresh`; `RefreshRequest` + `RefreshResponse`; 401 unauthenticated incl. reuse-detection; Dio interceptor note present at line 236)
  Request: `{ refreshToken: string }`
  Response 200: `{ data: { accessToken: string, refreshToken: string,
    accessTokenTtlSeconds: number }, error: null }`
  Errors: 401 unauthenticated (invalid/expired refresh token)
  Note: This is the endpoint the Dio interceptor calls transparently on 401.
  TypeScript interface: `TokenRefreshRequest`, `TokenRefreshResponse`
  Done when: shapes defined; Dio interceptor note present.

- [x] ✅ LOGOUT Define `POST /api/v1/auth/logout`: — ✓ verified (auth-required route; `LogoutRequest` {refreshToken} + `LogoutResponse`; revocation mechanism noted — sets `revokedAt` on the submitted refresh token; 401 unauthenticated. Note: deliverable returns 200 with message, not 204)
  Request: `{}` (body empty; refresh token in Authorization header or body?)
  Response 204: no content
  Note: if using Redis blacklist for revocation, this endpoint adds the access token
  to the blacklist and invalidates the refresh token. If using rotation-only
  revocation, this endpoint invalidates the refresh token server-side.
  Errors: 401 unauthenticated
  TypeScript interface: `LogoutResponse` (204, no data)
  Done when: revocation mechanism noted; shapes defined.

- [x] ✅ INTERFACES Write TypeScript interfaces for all 5 routes: — ✓ verified (TS block lines 345-420: `AuthTokenResponse`, `RegisterStartRequest/Response`, `RegisterRequest`, `LoginRequest`, `LoginInitResponse`, `RefreshRequest/Response`, `LogoutRequest/Response`, plus `KycResponse`/`SessionResponse`; every request & response has an interface)
  ```typescript
  interface AuthTokenResponse {
    userId: string;
    accessToken: string;
    refreshToken: string;
    accessTokenTtlSeconds: number;
    refreshTokenTtlDays: number;
  }
  interface ApiError {
    code: string;
    message: string;
    details: Record<string, unknown>;
  }
  // ... etc
  ```
  Done when: every request and response has a TypeScript interface.

- [x] ✅ WRITE Write `easy_rates/system-design/api/auth-service.md`: — ✓ verified (file exists; one section per route — register/start, register, login, refresh, logout, kyc, session; Figma Trace section present (lines 424-438); Rate limits table references conventions §5 / `docs/security/rate-limits.md` AUTH/SYSTEM/READ/WRITE categories; error codes per-route)
  One section per route; TypeScript interfaces; Figma Trace section; rate-limit note
  referencing security/rate-limits.md AUTH category; error code table.
  Done when: file exists; 5 routes documented; Figma Trace section present.

- [x] ✅ VERIFY Confirm: `accessTokenTtlSeconds` and `refreshTokenTtlDays` are — ✓ verified (the access-token TTL field — canonically renamed `accessTokenExpiresInSeconds`, see otp-service.md — plus `refreshTokenTtlDays` are in register (lines 117-118) and refresh (lines 222-223) responses; all response fields camelCase; `idNumber` returned in NO auth response — `AuthTokenResponse`/`SessionResponse` carry no idNumber, and ADR-002/003 discard the plaintext within the request)
  in the register and refresh responses (Flutter reads these to drive token management).
  Confirm: every response field name is camelCase per conventions.md.
  Confirm: no `idNumber` is returned in any auth response.
  Done when: camelCase confirmed; TTL fields present; idNumber absence confirmed.

## Recommended skill

▶ `/socratic` ✅ — THINK task; the "most confusing auth error" framing forces error
   codes to be specific enough for Flutter to act on without HTTP status guessing.
   — custom for contract writing.

## Engagement Instructions

Pass condition: 5 routes documented (register, login, refresh, logout; forgot-password
or mark as out of scope with justification).
Pass condition: TypeScript interface for every request body and response shape.
Pass condition: Figma Trace section maps every ONBOARDING transition to a named endpoint.
Pass condition: `accessTokenTtlSeconds` present in register and refresh responses.
Pass condition: rate-limit note references the AUTH category in security/rate-limits.md.
Pass condition: no `idNumber` in any auth response.

## Execution Note — 2026-06-27

### THINK (`/socratic`) — answer verbatim

The most confusing auth error for a Flutter developer is the **401 on `POST /auth/refresh`**.
The 409 on registration and the 403 on a public route are legible from their context: a 409
arrives synchronously while the user is staring at the Sign Up form (so it maps cleanly to a
"phone already registered" inline error), and a 403 is a static contract mistake the developer
hits once at integration time and fixes for good. The refresh 401 is insidious because it fires
*invisibly* inside the Dio interceptor on a token the user never typed — by the time it surfaces
there is no screen logically "responsible" for it, so a naive developer shows a generic toast or,
worse, an infinite retry loop. The deliverable disambiguates these three precisely through the
`{ data, error }` envelope's `error.code`, so Flutter never has to branch on bare HTTP status:
(1) **409 `conflict`** on `/auth/register` → keep the user on **Sign Up** in its `error` state with
"this number is already registered, log in instead"; (2) **401 `unauthenticated`** on `/auth/refresh`
(including reuse-detection / family-revoked) → clear both tokens and navigate to **Log In** via the
**Welcome / Value Prop** route, never retry; (3) **403 `forbidden`** on a route assumed public →
a developer-facing contract bug, surfaced as a non-user-facing error (the route's `[public]` vs
auth-required marking in the contract is the fix). Critically, the contract *also removes* one
whole class of confusion ADR-002 anticipated: `/auth/login` returns an anti-enumeration **200** for
an unregistered phone rather than a 404, so the developer never has to special-case "number not
found" on login — the only login error is 400 `validation_error` for a malformed number.

### Per-task evidence notes

- THINK: answered above — 3 most-confusing errors named (refresh 401, register 409, public-route 403), each with its `error.code` and the exact Flutter UI state.
- FIGMA-TRACE: Figma Trace table (lines 424-438) maps every ONBOARDING transition — Sign Up→`register/start`, Verify Phone OTP→`register`, Log In→`login`, Verify Login OTP→`otp/verify` (LOGIN), plus refresh/logout/kyc/session; otp-service & account-service steps marked as owned by other services.
- REGISTER: `POST /auth/register` (+ `/auth/register/start`) with `RegisterRequest`/`AuthTokenResponse`; errors 409/400/401/429; OTP-before-register clarified via the registrationToken consumed here.
- LOGIN: `POST /auth/login` with `LoginRequest`/`LoginInitResponse`; OTP-ownership decision documented (login dispatches via otp-service `POST /otp/send`; tokens issued by `POST /otp/verify` LOGIN). Deviation: deliverable returns anti-enumeration 200 instead of the plan's 404 not_found, per ADR-002 — the stronger, hardened choice.
- REFRESH: `POST /auth/refresh` with `RefreshRequest`/`RefreshResponse`; 401 unauthenticated incl. reuse-detection; Dio interceptor note at line 236.
- LOGOUT: `POST /auth/logout` (auth required) with `LogoutRequest`/`LogoutResponse`; revocation mechanism noted (sets `revokedAt`); 401. Deviation: returns 200+message rather than the plan's 204.
- INTERFACES: TS block (lines 345-420) carries an interface for every request and response across all routes.
- WRITE: deliverable file exists with one section per route, a Figma Trace section, a Rate limits table referencing the AUTH category in `docs/security/rate-limits.md`, and per-route error codes.
- VERIFY: access-token TTL field present in register & refresh responses (canonically named `accessTokenExpiresInSeconds`, consistent with otp-service.md — a hardening rename of the plan's `accessTokenTtlSeconds`, same purpose: lets Flutter schedule refresh without decoding the JWT); `refreshTokenTtlDays` present; all fields camelCase; `idNumber` returned in NO auth response (discarded within the request per ADR-002/003).

### forgot-password obsolescence (ADR-002)

The plan's Description, Goal, and Engagement Instructions reference `forgot-password` as a 5th
route. ADR-002 made auth passwordless OTP-only and **removed** `POST /auth/forgot-password` and
`POST /auth/reset-password`. This requirement is satisfied by the deliverable's
**"Removed — password recovery (ADR-002)"** section (lines 190-195), which documents the removal,
the rationale (no password to recover — re-login via a fresh LOGIN OTP), and the downstream effect
(`OtpPurpose` drops `PASSWORD_RESET`, now `REGISTRATION | LOGIN`). The Engagement Instruction's
"forgot-password or mark as out of scope with justification" pass condition is met by that section.
