# ADR-002 — Passwordless, OTP-first authentication

**Status:** Accepted (2026-06-21)
**Supersedes:** the password-based register/login design previously documented in
`api/auth-service.md` (register required `password`; login was `{phone, password}` with a
3-attempt lockout and a password-reset sub-flow).

---

## Context

The hardened `auth-service` contract used password credentials: `POST /auth/register` required
a `password`, `POST /auth/login` took `{phone, password}` and issued tokens directly, and a
`forgot-password` → `reset-password` OTP sub-flow existed to recover passwords.

Two latent inconsistencies already sat in the design:

1. **The Sign Up screen never collected a password.** `docs/screen-inventory.md` lists the Sign
   Up inputs as full name, email, SA ID, cell phone, proof of address — no password field — yet
   the `register` endpoint required one. Registration was *already* effectively passwordless at
   the UI.
2. **`OtpPurpose.LOGIN` was already in the schema** (`docs/data-model/user-auth.md`) but unused
   by any route — the data model anticipated OTP-based login that the API never exposed.

The product direction is a low-friction mobile onboarding for municipal ratepayers on low-end
Android handsets, many of whom will not manage a password. Phone-number + OTP is the prevailing
South African mobile-app auth pattern.

## Decision

Adopt **passwordless, OTP-first authentication**. Phone number + one-time PIN is the only
credential. Specifically:

1. **No passwords anywhere.** Remove `User.passwordHash`, the `password` field on register, the
   password field on login, and the entire `forgot-password` / `reset-password` sub-flow.

2. **OTP ownership — auth-service is the front door; otp-service owns the OTP lifecycle.**
   The Flutter client never calls `POST /otp/send` (it stays `[internal]`). The client calls
   `auth-service` to *initiate*, and `auth-service` calls otp-service `POST /otp/send`
   server-to-server. otp-service owns code generation, verification, TTL, attempt counting, and
   resend. The client calls `POST /otp/verify` (public) to verify.

3. **Registration is OTP-first and `register` mints the session.**
   - `POST /auth/register/start {phone}` → 409 if the phone is already registered, else
     dispatches a `REGISTRATION` OTP. Returns `{ ttlSeconds }`.
   - `POST /otp/verify {phone, code}` with purpose `REGISTRATION` → returns a single-use
     `registrationToken` (no `User` exists yet, so no session token is issued here).
   - `POST /auth/register {phone, displayName, idNumber, registrationToken}` → creates the
     phone-verified `User` (kycStatus `PENDING`) and returns the session token pair
     (`AuthTokenResponse`).

4. **Login is OTP-only and `verify` mints the session.**
   - `POST /auth/login {phone}` → **anti-enumeration: always 200** with
     `{ message, ttlSeconds }`. If (and only if) the phone is registered, a `LOGIN` OTP is
     dispatched. This deliberately replaces the proposed `404 not_found`, which would leak which
     numbers have accounts — matching the anti-enumeration stance the old `forgot-password`
     already took.
   - `POST /otp/verify {phone, code}` with purpose `LOGIN` → returns the session token pair.

5. **`OtpPurpose` becomes `REGISTRATION | LOGIN`** (drop `PASSWORD_RESET`).

## Consequences

**Positive**
- Resolves the two latent inconsistencies above.
- Removes a whole credential surface (password storage, complexity rules, lockout, reset flow).
- Login and registration become symmetric: `auth/*` initiates → `otp/send` dispatches
  (internal) → `otp/verify` verifies.

**Ripples this ADR commits us to (tracked across the artifacts):**
- `api/auth-service.md` — register/login rewritten; `register/start` added; `forgot-password`
  and `reset-password` removed. **(done in this change)**
- `api/otp-service.md` — `OtpPurpose` → `REGISTRATION | LOGIN`; `verify` returns a session for
  `LOGIN` and a `registrationToken` for `REGISTRATION`. **(done in this change)**
- `docs/screen-inventory.md` — Log In becomes phone-only; Forgot Password and Reset-via-OTP
  screens removed; Sign Up annotated OTP-first. **(done in this change)**
- `docs/data-model/user-auth.md` — `User.passwordHash` removed; `OtpPurpose.PASSWORD_RESET`
  removed; POPIA erasure list updated. **(done in this change)**

**Open / accepted costs:**
- **`idNumber` is required on register** (resolved 2026-06-21 — it gates property linking and the
  Sign Up screen already collects it). **New open item it surfaces:** `idNumber` is validated but
  **not persisted** (`docs/data-model/user-auth.md` has no SA-ID column), yet the property-service
  identity gate (`user.idNumber ∈ property.holderIdNumbers`, `api/property-service.md`) needs it
  server-side at link time. Validate-then-discard cannot feed the gate — persisting it (hashed,
  POPIA-reviewed) is a data-model decision still to be made.
- **`email` remains optional on register** (not dropped), because notification-service uses the
  EMAIL channel. Dropping email would silently disable email notifications.
- The `AuditEvent` security types `LOGIN_FAILED` / `OTP_FAILED` still apply; `LOGIN_FAILED` now
  means an OTP-verify failure rather than a wrong password.

## Alternatives considered

- **Register-first, passwordless (verify mints tokens, register returns `{userId}`).** Smaller
  change — keeps the current screen ordering and needs no `registrationToken`. Rejected because
  the product owner specified OTP-*before*-register with `register` returning the session; this
  ADR honors that ordering at the cost of a single-use registration proof token.
- **Keep passwords.** Rejected — contradicts the product direction and leaves the two latent
  inconsistencies above unresolved.
