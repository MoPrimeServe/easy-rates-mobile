# auth-service — API Contract

**Service base path:** `/auth`
**Conforms to:** [`api/conventions.md`](./conventions.md) — every response uses the
`{ data, error }` envelope; all paths below are relative to the `/api/v1` prefix.
**Auth requirement:** routes are `[public]` (no token) or authenticated
(`Authorization: Bearer <accessToken>`) as marked per route.

This contract documents only routes, payloads, and **route-specific** error codes. Standard
codes (`validation_error` 400, `unauthenticated` 401, `forbidden` 403, `not_found` 404,
`conflict` 409, `unprocessable` 422, `rate_limit_exceeded` 429, `internal_server_error` 500)
are defined once in `conventions.md` §3 and are not re-documented here; each route lists which
standard codes it raises.

**Token model (from `docs/security/sessions.md`, central resolutions):**
- **Access token:** RS256 JWT, TTL **900 s (15 min)**. Sent as `Authorization: Bearer`.
  Stored **in memory only** on the Flutter client (Riverpod state, never disk).
- **Refresh token:** opaque 256-bit hex, TTL **30 days**, **single-use, rotated on every
  refresh**. Stored in `flutter_secure_storage`. Reuse of a rotated token revokes the whole
  `familyId` chain.
- Every session-issuing response (`POST /auth/register`, `POST /otp/verify` purpose `LOGIN`,
  `POST /auth/refresh`) returns `accessTokenExpiresInSeconds: 900` so the client need not decode
  the JWT to schedule refresh; register, login, and refresh also return `refreshTokenTtlDays: 30`
  (refresh rotates the refresh token, so it re-states the new token's TTL each time).
- **No passwords (ADR-002).** Authentication is phone + OTP only; there is no `passwordHash`,
  no password on register/login, and no password-reset flow.

---

## POST /auth/register/start `[public]`

Begins OTP-first registration (ADR-002). Verifies the phone is **not** already registered,
then dispatches a `REGISTRATION` OTP via otp-service `POST /otp/send` (server-to-server — the
client never calls otp-service to send). Creates no `User`.

**Request**

| Field | Type | Required | Constraint |
|---|---|---|---|
| phone | string | Yes | E.164, South Africa (`+27…`) |

```json
{ "phone": "+27821234567" }
```

**Response — 202 Accepted**

```json
{ "data": { "ttlSeconds": 600, "resendCooldownSeconds": 30, "maskedPhone": "+27****1234" }, "error": null }
```

`resendCooldownSeconds` and `maskedPhone` are returned so the Verify Phone OTP screen can seed
its initial resend countdown and display the masked number without hardcoding either (the
internal `POST /otp/send` owns these values; auth-service surfaces them to the client).

The client advances to the Verify Phone OTP screen and calls `POST /otp/verify` (purpose
`REGISTRATION`), which returns a single-use `registrationToken`.

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | phone malformed |
| 409 | `conflict` | phone already registered |

> **Enumeration note.** Unlike `POST /auth/login` (anti-enumeration), registration must reject a
> duplicate phone, so `409` here does reveal a number is taken — an accepted cost of preventing
> duplicate accounts.

Standard `429 rate_limit_exceeded` (AUTH limiter) and `500` also apply.

---

## POST /auth/register `[public]`

Completes OTP-first registration: consumes the single-use `registrationToken` from
`POST /otp/verify` (purpose `REGISTRATION`), creates the phone-verified `User` (kycStatus
defaults to `PENDING`), and **issues the session token pair** (ADR-002 — passwordless).

**Request**

| Field | Type | Required | Constraint |
|---|---|---|---|
| phone | string | Yes | E.164 (`+27…`); must match the verified `registrationToken` |
| displayName | string | Yes | non-empty |
| email | string | No | valid email; unique if present (notification EMAIL channel) |
| idNumber | string | Yes | 13-digit South African ID, Luhn-valid |
| registrationToken | string | Yes | single-use token from `POST /otp/verify` (`REGISTRATION`) |

```json
{
  "phone": "+27821234567",
  "displayName": "Thabo Mokoena",
  "email": "thabo@example.co.za",
  "idNumber": "9202204720082",
  "registrationToken": "rt_3f2a91c0d4e5..."
}
```

> **No password (ADR-002).** Authentication is phone + OTP only; the Sign Up screen never
> collected a password.

> **`idNumber` is required; stored as a keyed hash (ADR-002, ADR-003).** Validated (format + Luhn)
> at registration, then stored as `User.idNumberHash = HMAC_SHA256(pepper, idNumber)` — the
> **plaintext is discarded within the request**, never written to the DB or logs. The
> property-service identity gate matches hash-to-hash
> (`user.idNumberHash ∈ property.holderIdNumberHashes`). The pepper lives in the KMS, never the DB.

**Response — 201 Created** (`AuthTokenResponse` — the session token pair)

```json
{
  "data": {
    "userId": "clx9a8b7c6d5e4f3g2h1",
    "accessToken": "eyJhbGciOiJSUzI1Ni␣...",
    "refreshToken": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "accessTokenExpiresInSeconds": 900,
    "refreshTokenTtlDays": 30
  },
  "error": null
}
```

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | phone/displayName/idNumber fail validation (incl. failed Luhn on `idNumber`) |
| 401 | `unauthenticated` | `registrationToken` invalid, expired, or already used |
| 409 | `conflict` | phone already registered (race after `register/start`) |

Standard `429 rate_limit_exceeded` (AUTH limiter) and `500 internal_server_error` also apply.

---

## POST /auth/login `[public]`

Initiates OTP-only login (ADR-002). **Anti-enumeration: always returns `200`** with the same
body whether or not the phone is registered. If (and only if) the phone is registered,
dispatches a `LOGIN` OTP via otp-service `POST /otp/send` (server-to-server). The token pair is
issued later by `POST /otp/verify` (purpose `LOGIN`), not here.

**Request**

| Field | Type | Required | Constraint |
|---|---|---|---|
| phone | string | Yes | E.164, `+27…` |

```json
{ "phone": "+27821234567" }
```

**Response — 200 OK** (identical regardless of whether the phone exists)

```json
{
  "data": {
    "message": "If that number is registered, an OTP has been sent.",
    "ttlSeconds": 600,
    "resendCooldownSeconds": 30,
    "maskedPhone": "+27****1234"
  },
  "error": null
}
```

`maskedPhone` is a masked echo of the **submitted** number (not a DB lookup), so it is
anti-enumeration safe — the body stays byte-identical whether or not the phone is registered.
`resendCooldownSeconds` seeds the Verify Login OTP screen's initial resend countdown.

The client advances to the Verify Login OTP screen and calls `POST /otp/verify` (purpose
`LOGIN`) → `AuthTokenResponse`.

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | phone malformed |

> **No `404` on unknown phone (ADR-002).** Returning `404 not_found` for an unregistered phone
> would leak which numbers have accounts. The body is byte-identical whether or not the phone is
> registered; an unregistered phone simply receives no OTP. There is **no password and no
> account-lockout** — brute-force resistance is the OTP attempt limit (otp-service
> `max_attempts_exceeded`).

Standard `429 rate_limit_exceeded` (AUTH) and `500` also apply.

---

## Removed — password recovery (ADR-002)

`POST /auth/forgot-password` and `POST /auth/reset-password` are **removed**. With passwordless
OTP-only auth there is no password to recover — a user who cannot get in simply logs in again via
`POST /auth/login` (a fresh `LOGIN` OTP). The former `PASSWORD_RESET` OTP purpose is dropped;
otp-service now has `OtpPurpose = REGISTRATION | LOGIN`.

---

## POST /auth/refresh `[public]`

Exchanges a valid refresh token for a new token pair. **Rotates on every use** (the submitted
refresh token is revoked and a new one issued). Reuse of an already-rotated token is detected
and revokes the entire token family.

**Request**

| Field | Type | Required | Constraint |
|---|---|---|---|
| refreshToken | string | Yes | opaque 256-bit hex |

```json
{ "refreshToken": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" }
```

**Response — 200 OK**

```json
{
  "data": {
    "accessToken": "eyJhbGciOiJSUzI1Ni␣...",
    "refreshToken": "1b4f0e9851971998e732078544c96b36c3d01cedf7caa332359d6f1d83567014",
    "accessTokenExpiresInSeconds": 900,
    "refreshTokenTtlDays": 30
  },
  "error": null
}
```

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | refreshToken missing/malformed |
| 401 | `unauthenticated` | token invalid, revoked, expired, or **reuse detected** (family revoked) |

> On `401`, the Dio interceptor (conventions §6) clears both tokens and navigates to Login.
> Standard `429 rate_limit_exceeded` (SYSTEM limiter — IP-scoped, 30/15 min) and `500` apply.

---

## POST /auth/logout

**Auth required.** Revokes the submitted refresh token (sets `revokedAt`). The client also
clears the in-memory access token and deletes the refresh token from secure storage. Serves
the Account & Settings "Log Out" confirmation.

**Request**

| Field | Type | Required | Constraint |
|---|---|---|---|
| refreshToken | string | Yes | the refresh token to revoke |

```json
{ "refreshToken": "1b4f0e9851971998e732078544c96b36c3d01cedf7caa332359d6f1d83567014" }
```

**Response — 200 OK**

```json
{ "data": { "message": "Logged out." }, "error": null }
```

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `validation_error` | refreshToken missing/malformed |
| 401 | `unauthenticated` | no/invalid access token |

Standard `429 rate_limit_exceeded` (SYSTEM — userId-scoped, 10/15 min) and `500` also apply.

---

## POST /auth/kyc

**Auth required. `Content-Type: multipart/form-data`.** Uploads a proof-of-address document
and sets `kycStatus = SUBMITTED`. Serves the "Upload Proof of Address" screen.

**Request — multipart fields**

| Field | Type | Required | Constraint |
|---|---|---|---|
| file | binary | Yes | proof of address; max **10485760** bytes (10 MB); MIME one of `application/pdf`, `image/jpeg`, `image/png` |

**Response — 201 Created**

```json
{
  "data": { "kycStatus": "SUBMITTED", "uploadedAt": "2026-06-21T10:30:00.000Z" },
  "error": null
}
```

> The document is stored in Azure Blob Storage; only its key is recorded on `User`
> (`kycDocumentKey`). Per POPIA the raw document is never stored in the database, and the
> upload emits a `KYC_DOCUMENT_UPLOADED` AuditEvent. `kycStatus` enum is exactly
> `PENDING | SUBMITTED | VERIFIED | REJECTED`.

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `file_missing` | no `file` part in the multipart body |
| 413 | `rate_limit_exceeded` → **payload too large** | file exceeds 10485760 bytes (returns the standard 413 body; `error.code` is the upload size code, see conventions §3 service-specific list) |
| 422 | `invalid_file_type` | MIME type not in the accepted set |

> `file_missing` and `invalid_file_type` are the service-specific codes from conventions §3.
> Standard `401 unauthenticated`, `429 rate_limit_exceeded` (WRITE limiter), `500` also apply.

---

## GET /auth/session

**Auth required.** Returns a session summary for the App Launch — Token Check step. The
client calls this with its stored access token; a `200` means the token is valid and routing
proceeds to Home Dashboard, a `401` triggers the refresh flow (then Login).

**Request:** none (token only).

**Response — 200 OK**

```json
{
  "data": {
    "userId": "clx9a8b7c6d5e4f3g2h1",
    "phone": "+27821234567",
    "kycStatus": "VERIFIED"
  },
  "error": null
}
```

**Errors**

| HTTP | `error.code` | When |
|---|---|---|
| 401 | `unauthenticated` | no/invalid/expired access token |

Standard `429 rate_limit_exceeded` (READ limiter) and `500` also apply.

---

## TypeScript interfaces

```ts
// Shared
type KycStatus = 'PENDING' | 'SUBMITTED' | 'VERIFIED' | 'REJECTED';

// Shared session token pair — issued by POST /auth/register and POST /otp/verify (LOGIN)
interface AuthTokenResponse {
  userId: string;
  accessToken: string;                 // RS256 JWT, in-memory only
  refreshToken: string;                // opaque 256-bit hex, secure storage
  accessTokenExpiresInSeconds: number; // 900
  refreshTokenTtlDays: number;         // 30
}

// POST /auth/register/start  (OTP-first; dispatches REGISTRATION OTP)
interface RegisterStartRequest {
  phone: string;                       // E.164 +27
}
interface RegisterStartResponse {
  ttlSeconds: number;                  // OTP TTL
  resendCooldownSeconds: number;       // initial resend cooldown for the Verify OTP screen
  maskedPhone: string;                 // e.g. "+27****1234" — shown on the Verify OTP screen
}

// POST /auth/register  (consumes registrationToken; issues the session)
interface RegisterRequest {
  phone: string;                       // E.164 +27; matches the verified registrationToken
  displayName: string;
  email?: string;
  idNumber: string;                    // 13-digit SA ID, Luhn-valid; required (ADR-002); persistence open
  registrationToken: string;           // single-use, from POST /otp/verify (REGISTRATION)
}
// 201 data: AuthTokenResponse

// POST /auth/login  (OTP-only; anti-enumeration — token pair comes from POST /otp/verify LOGIN)
interface LoginRequest {
  phone: string;
}
interface LoginInitResponse {
  message: string;                     // identical whether or not the phone is registered
  ttlSeconds: number;
  resendCooldownSeconds: number;       // seeds the Verify Login OTP resend countdown
  maskedPhone: string;                 // masked echo of the submitted phone — anti-enumeration safe
}

// POST /auth/refresh
interface RefreshRequest {
  refreshToken: string;
}
interface RefreshResponse {
  accessToken: string;
  refreshToken: string;                 // rotated — replaces the old one
  accessTokenExpiresInSeconds: number;  // 900
  refreshTokenTtlDays: number;          // 30 — TTL of the newly rotated refresh token
}

// POST /auth/logout
interface LogoutRequest {
  refreshToken: string;
}
interface LogoutResponse {
  message: string;
}

// POST /auth/kyc (multipart/form-data; `file` part not modelled in TS)
interface KycResponse {
  kycStatus: KycStatus;  // SUBMITTED on success
  uploadedAt: string;    // ISO-8601 UTC ms
}

// GET /auth/session
interface SessionResponse {
  userId: string;
  phone: string;
  kycStatus: KycStatus;
}
```

---

## Figma Trace

Maps each route to the screen transitions it serves (from `docs/screen-inventory.md`,
flows **ONBOARDING** and **ACCOUNT & SETTINGS**).

| Route | Screen → transition served |
|---|---|
| `POST /auth/register/start` | **Sign Up** (`submitting`) → on `202` → **OTP Sent → Verify Phone OTP** (REGISTRATION OTP dispatched). `409` → phone already registered → Sign Up `error`. |
| `POST /auth/register` | **Verify Phone OTP** → after `otp/verify` returns `registrationToken` → on `201` creates user + issues tokens → **Upload Proof of Address**. `401` → registrationToken expired → restart. |
| `POST /auth/login` | **Log In** (`submitting`, phone only) → always `200` → **Verify Login OTP** (LOGIN OTP dispatched if registered). Anti-enumeration; no password, no lockout. |
| `POST /otp/verify` (LOGIN) | **Verify Login OTP** → on `200` → `AuthTokenResponse` → **Home Dashboard**. (otp-service route; shown here as the login token-issue point.) |
| `POST /auth/refresh` | Cross-screen — the Dio 401→refresh→retry interceptor. On `401` → clear tokens → **Welcome / Value Prop → Log In**. Also drives **App Launch — Token Check** when the access token is stale. |
| `POST /auth/logout` | **Log Out** (`confirming`) → "Log out" confirmed → tokens cleared → **App Launch — Token Check** (→ Splash Screen, unauthenticated). |
| `POST /auth/kyc` | **Upload Proof of Address** (`uploading` → `uploaded`) → on `201` (`kycStatus = SUBMITTED`) → **Awaiting KYC Approval**. `400 file_missing` / `413` / `422 invalid_file_type` → Upload `error`. |
| `GET /auth/session` | **App Launch — Token Check** (`checking`) → `200` (valid token) → **Home Dashboard**; `401` → refresh flow → else **Splash Screen**. |

---

## Rate limits

Categories from `conventions.md` §5 / `docs/security/rate-limits.md`.

| Endpoint | Method | Category | Scope · Window · Limit |
|---|---|---|---|
| `/auth/register/start` | POST | AUTH | IP · 15 min · 10 |
| `/auth/register` | POST | AUTH | IP · 15 min · 10 |
| `/auth/login` | POST | AUTH | IP · 15 min · 10 |
| `/auth/refresh` | POST | SYSTEM | IP · 15 min · 30 |
| `/auth/logout` | POST | SYSTEM | userId · 15 min · 10 |
| `/auth/kyc` | POST | WRITE | userId · 1 hour · 20 |
| `/auth/session` | GET | READ | userId · 1 min · 60 |
