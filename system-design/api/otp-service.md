# OTP Service — API Contract

**Service:** otp-service
**Base path:** `/otp` (relative to the `/api/v1` prefix — see `api/conventions.md` §1)
**Conforms to:** `api/conventions.md` (root contract). This file specifies only routes,
payloads, and per-route error codes; the `{ data, error }` envelope, standard error codes
(`validation_error`, `unauthenticated`, …), date/money formats, and camelCase rule are
defined there and are **not** re-documented here.
**Sources of truth:** OTP error codes, lifecycle params, and the handler/transition map are
copied from `docs/twilio-integration.md`. Rate-limit categories come from
`docs/security/rate-limits.md`.

## Overview

This service drives phone verification via the **Twilio Verify API**. Twilio owns code
generation, storage, TTL enforcement, attempt counting, and built-in rate limiting; the
otp-service owns error handling, resend tracking, and post-verification routing. At send
time the server stores per-phone context in **Redis** (`otp_sid:${phone}`,
`otp_attempts:${phone}`) so `verify` can determine the post-approval action without a
request parameter.

The four `OTP_*` lifecycle parameters are returned as **integer fields** in OTP responses so
the Flutter client never hardcodes them. Central resolved values:

| Field | Value | Env var (otp-service) |
|---|---|---|
| `ttlSeconds` | `600` | `OTP_TTL_SECONDS` |
| `resendCooldownSeconds` | `30` | `OTP_RESEND_COOLDOWN_SECONDS` |
| `maxResends` | `3` | `OTP_MAX_RESENDS_PER_SESSION` |
| `maxAttempts` | `5` | `OTP_MAX_INVALID_ATTEMPTS` |

> **Screen-inventory note (twilio Open Issue #1 — RESOLVED 2026-06-21):**
> `docs/screen-inventory.md` previously showed the resend link enabling after **60 s** on the
> Verify Phone OTP and Verify Login OTP screens — a screen-inventory bug against the decided value
> `resendCooldownSeconds = 30`. The inventory copy has been corrected to **30 s**; the Flutter
> countdown reads `30` from this API and the on-screen copy now matches.

---

## `POST /otp/send` `[internal]`

Starts a verification. **Not called directly by the Flutter app** — it is invoked
server-to-server by auth-service when a user starts registration (REGISTRATION, via
`POST /auth/register/start`) and when a user initiates login (LOGIN, via `POST /auth/login`).
Documented here because the endpoint exists and
carries the rate-limit category that protects it.

Side effect: stores `{ verificationSid, context, resendCount: 0 }` in Redis at
`otp_sid:${phone}` with EX 600. Twilio call:
`verifications.create({ to: phone, channel: 'sms' })`.

**Request**

| Field | Type | Required | Notes |
|---|---|---|---|
| `phone` | string | yes | `+27` E.164 |
| `purpose` | enum | yes | `REGISTRATION` \| `LOGIN` |

```json
{ "phone": "+27821234567", "purpose": "REGISTRATION" }
```

**Response `202 Accepted`** — returns the lifecycle params so the client (which receives them
indirectly via the auth-service flow) never hardcodes them.

```json
{
  "data": {
    "ttlSeconds": 600,
    "resendCooldownSeconds": 30,
    "maxResends": 3,
    "maxAttempts": 5
  },
  "error": null
}
```

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | Missing/invalid `phone` or `purpose` (see conventions §4) |

---

## `POST /otp/verify` `[public]`

Checks a submitted code. Reads `context` from Redis to decide the post-approval action.
Twilio call: `verificationChecks.create({ to: phone, code: userInput })`, wrapped in
try/catch. On approval the SID key is cleared (`otp_sid:${phone}`).

**Request**

| Field | Type | Required | Notes |
|---|---|---|---|
| `phone` | string | yes | `+27` E.164 |
| `code` | string | yes | 6-digit code |

```json
{ "phone": "+27821234567", "code": "123456" }
```

**Response `200 OK` — approved REGISTRATION** (Twilio `status: 'approved'`, context
`phone_verification`). No `User` exists yet (registration is OTP-first, ADR-002), so **no
session is issued** — returns a single-use `registrationToken` (10-minute TTL) consumed by
`POST /auth/register`.

```json
{
  "data": { "registrationToken": "<single-use, 10-min TTL>", "ttlSeconds": 600 },
  "error": null
}
```

**Response `200 OK` — approved LOGIN** (Twilio `status: 'approved'`, context `login`). The
`User` already exists; issues the session token pair (see conventions §6).

```json
{
  "data": {
    "userId": "<cuid>",
    "accessToken": "<RS256 JWT>",
    "refreshToken": "<opaque 256-bit hex>",
    "accessTokenExpiresInSeconds": 900,
    "refreshTokenTtlDays": 30
  },
  "error": null
}
```

**Errors** — the four OTP codes are copied **verbatim** from `docs/twilio-integration.md` §5.
The `error.code` strings stay snake_case (they are codes, unchanged). The `details` field
**names** are camelCase per conventions §10 — the twilio doc's snake_case examples
(`ttl_seconds`, `attempts_remaining`, `max_attempts`) are converted to
`ttlSeconds`, `attemptsRemaining`, `maxAttempts`.

| HTTP | `error.code` | `details` | Trigger | Flutter action |
|---|---|---|---|---|
| 410 | `otp_expired` | `ttlSeconds: 0` (remaining TTL — always 0 for an expired code) | `verifyOtp` catches `err.code === 60200` | Route to OTP Expired / Resend |
| 422 | `otp_invalid` | `attemptsRemaining: int`, `maxAttempts: int` | Twilio `status: 'pending'`, `valid: false` | Show inline "X attempts remaining" |
| 429 | `max_attempts_exceeded` | `maxAttempts: int` | `verifyOtp` catches `err.code === 60202` | Route to OTP Expired / Resend |
| 400 | `validation_error` | `details.fields` (conventions §4) | Missing/malformed `phone` or `code` | Inline field errors |

```json
{ "data": null, "error": { "code": "otp_expired", "message": "Your verification code has expired. Please request a new one.", "details": { "ttlSeconds": 0 } } }
```

```json
{ "data": null, "error": { "code": "otp_invalid", "message": "Incorrect code. Please try again.", "details": { "attemptsRemaining": 3, "maxAttempts": 5 } } }
```

```json
{ "data": null, "error": { "code": "max_attempts_exceeded", "message": "Too many incorrect attempts. Please request a new code.", "details": { "maxAttempts": 5 } } }
```

`attemptsRemaining` is dynamic — otp-service tracks it in `otp_attempts:${phone}` (Twilio
does not return a remaining count). `otp_expired` and `max_attempts_exceeded` share the OTP
Expired / Resend destination; the distinct `error.code` lets the client render the correct
copy ("code expired" vs "too many attempts").

---

## `POST /otp/resend` `[public]`

Cancels the live verification and starts a new one. Twilio calls (sequential):
`verifications(storedSid).update({ status: 'canceled' })` then
`verifications.create({ to: phone, channel: 'sms' })`. Cancellation is explicit (via the
stored SID) so two live codes never coexist.

Pre-checks before any Twilio call: `resendCount < maxResends` (else `max_attempts_exceeded`
path is *not* used — the count is surfaced via `resendsRemaining`, see below) and elapsed
since last send `≥ resendCooldownSeconds` (else `resend_cooldown_active`).

**Request**

| Field | Type | Required | Notes |
|---|---|---|---|
| `phone` | string | yes | `+27` E.164 |
| `purpose` | enum | yes | `REGISTRATION` \| `LOGIN` |

```json
{ "phone": "+27821234567", "purpose": "LOGIN" }
```

**Response `202 Accepted`**

```json
{
  "data": {
    "ttlSeconds": 600,
    "resendCooldownSeconds": 30,
    "resendsRemaining": 2
  },
  "error": null
}
```

`ttlSeconds` is re-stated because a resend mints a **new** code with a fresh TTL; the client
resets its expiry countdown from this value rather than reusing the original send's TTL — so a
server-side `OTP_TTL_SECONDS` change is honoured without hardcoding (consistent with the
lifecycle-param principle in this contract's Overview).

> **`resendsRemaining` resolves twilio Open Issue #2.** When `resendsRemaining` reaches `0`
> (i.e. `maxResends` resends have been used this session), the Flutter client swaps the
> Resend button for a support-contact CTA. This avoids needing a fifth error code.

**Errors**

| HTTP | `error.code` | `details` | Notes |
|---|---|---|---|
| 429 | `resend_cooldown_active` | `retryAfterSeconds: int` | `Retry-After: <retryAfterSeconds>` header. Value is the **remaining** cooldown (`resendCooldownSeconds − elapsedSinceLastSend`), not the total. |
| 400 | `validation_error` | `details.fields` (conventions §4) | Missing/invalid `phone` or `purpose` |

```json
{ "data": null, "error": { "code": "resend_cooldown_active", "message": "Please wait before requesting another code.", "details": { "retryAfterSeconds": 18 } } }
```

Flutter's resend countdown widget renders `retryAfterSeconds` directly; when it reaches zero
the button unlocks without a page reload.

---

## TypeScript interfaces

```ts
// ---- send (internal) ----
type OtpPurpose = 'REGISTRATION' | 'LOGIN';

interface OtpSendRequest {
  phone: string;        // +27 E.164
  purpose: OtpPurpose;
}

interface OtpSendResponse {
  ttlSeconds: number;             // 600
  resendCooldownSeconds: number;  // 30
  maxResends: number;             // 3
  maxAttempts: number;            // 5
}

// ---- verify ----
interface OtpVerifyRequest {
  phone: string;        // +27 E.164
  code: string;         // 6-digit
}

// approved REGISTRATION — no User yet; single-use proof consumed by POST /auth/register
interface OtpVerifyRegistrationResponse {
  registrationToken: string;  // single-use, 10-min TTL
  ttlSeconds: number;
}

// approved LOGIN — User exists; issues the session token pair (AuthTokenResponse)
interface OtpVerifyLoginResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
  accessTokenExpiresInSeconds: number;  // 900
  refreshTokenTtlDays: number;          // 30
}

// ---- resend ----
interface OtpResendRequest {
  phone: string;        // +27 E.164
  purpose: OtpPurpose;
}

interface OtpResendResponse {
  ttlSeconds: number;             // 600 — the new code's TTL; client resets its expiry countdown from this
  resendCooldownSeconds: number;  // 30
  resendsRemaining: number;       // 0 → client shows support CTA
}

// ---- OTP-specific error detail shapes (error.code stays snake_case) ----
interface OtpExpiredDetails { ttlSeconds: number; }              // otp_expired (410) — remaining TTL, 0 for an expired code
interface OtpInvalidDetails { attemptsRemaining: number; maxAttempts: number; } // otp_invalid (422)
interface MaxAttemptsExceededDetails { maxAttempts: number; }    // max_attempts_exceeded (429)
interface ResendCooldownActiveDetails { retryAfterSeconds: number; } // resend_cooldown_active (429)
```

---

## Figma Trace

Three Node.js handlers (`sendOtp`, `verifyOtp`, `resendOtp`) cover the ONBOARDING OTP screen
transitions. Mapping uses the transition map in `docs/twilio-integration.md` §4.

| Route | Handler | From screen | Trigger | To screen | Context |
|---|---|---|---|---|---|
| `POST /otp/send` | `sendOtp` | Sign Up | `POST /auth/register/start` succeeds | OTP Sent → Verify Phone OTP | `phone_verification` (REGISTRATION) |
| `POST /otp/send` | `sendOtp` | Log In | `POST /auth/login` (phone registered) | Verify Login OTP | `login` (LOGIN) |
| `POST /otp/verify` | `verifyOtp` | **Verify Phone OTP** | Correct code (`approved`, REGISTRATION) | returns `registrationToken` → `POST /auth/register` → Upload Proof of Address | clear `otp_sid` |
| `POST /otp/verify` | `verifyOtp` | **Verify Phone OTP** | Wrong code (`pending`) → `otp_invalid` 422 | **OTP Expired / Resend** | `otp_invalid` + lifecycle params |
| `POST /otp/verify` | `verifyOtp` | **Verify Phone OTP** | Expired (`60200`) → `otp_expired` 410 | **OTP Expired / Resend** | `otp_expired` + lifecycle params |
| `POST /otp/verify` | `verifyOtp` | **Verify Phone OTP** | Max attempts (`60202`) → `max_attempts_exceeded` 429 | **OTP Expired / Resend** | `max_attempts_exceeded` + lifecycle params |
| `POST /otp/verify` | `verifyOtp` | **Verify Login OTP** | Correct code (`approved`, LOGIN) | issues session token pair → Home Dashboard | clear `otp_sid` |
| `POST /otp/verify` | `verifyOtp` | **Verify Login OTP** | Expired (`60200`) → `otp_expired` 410 | OTP Expired / Resend | `otp_expired` + lifecycle params |
| `POST /otp/verify` | `verifyOtp` | **Verify Login OTP** | Max attempts (`60202`) → `max_attempts_exceeded` 429 | OTP Expired / Resend | `max_attempts_exceeded` + lifecycle params |
| `POST /otp/resend` | `resendOtp` | **Verify Phone OTP** | Resend link tapped (after 30 s) | Verify Phone OTP — new code | `phone_verification` (REGISTRATION) |
| `POST /otp/resend` | `resendOtp` | **OTP Expired / Resend** | "Resend OTP" CTA tapped | Verify Phone OTP / Verify Login OTP — new code | original purpose |
| `POST /otp/resend` | `resendOtp` | **Verify Login OTP** | Resend link tapped (after 30 s) | Verify Login OTP — new code | `login` (LOGIN) |

When `resendsRemaining` reaches `0`, the OTP Expired / Resend screen swaps the Resend CTA for
a support-contact CTA (resolves twilio Open Issue #2).

---

## Rate limits

From `docs/security/rate-limits.md` (Endpoint category table). OTP-specific 429s
(`max_attempts_exceeded`, `resend_cooldown_active`) carry their own `error.code` and are
issued by otp-service, **not** by the generic `rate_limit_exceeded` limiter — the Flutter
handler switches on `error.code`.

| Endpoint | Method | Category | Scope | Window | Limit |
|---|---|---|---|---|---|
| `/otp/send` | POST | OTP-SEND | phone | 10 min | 3 |
| `/otp/verify` | POST | OTP-VERIFY | phone | 10 min | 10 |
| `/otp/resend` | POST | OTP-SEND | phone | 10 min | 3 |
