# EasyRates — JWT Security Model

**Status:** Decided  
**Date:** 2026-06-20  
**Downstream:** `backend/plans/03-auth-service.md` — copy the five constants in the
[Configuration constants](#configuration-constants) section verbatim. No auth-service
implementation may choose its own algorithm, TTL, or storage location. If these values
change, update this document first, then update plan/03.

**Gap:** The data model (`docs/data-model/`) does not include a `RefreshToken` model.
Plan/03 assumes one exists. The schema for this model is specified in the
[RefreshToken table](#refreshtoken-table) section below. It must be added to
`docs/data-model/user-auth.md` and `schema.prisma` before plan/03 starts.

---

## Decision A — Algorithm: RS256

**Chosen: RS256 (asymmetric, RSA-SHA256)**

RS256 uses a private key to sign tokens and a public key to verify them. Only auth-service
holds the private key. Every other service holds only the public key.

### Why not HS256

HS256 uses a single shared secret for both signing and verification. In this architecture
there are eight services, each of which must verify tokens on every authenticated request.
With HS256, every one of those services must hold the signing secret. If bill-service or
objection-service is compromised, the attacker obtains the signing secret and can forge
tokens for any userId indefinitely. The blast radius of a single service breach is total
authentication bypass across the platform.

RS256 eliminates this. A compromised resource service reveals only the public key — which
is already public. Only a breach of auth-service or Azure Key Vault exposes the private key.

### Key management

The RSA private key is stored in Azure Key Vault. Auth-service calls the Key Vault `sign`
API — the private key never leaves Key Vault, never appears in environment variables, and
is never written to disk inside the container.

### Verification endpoint

Auth-service exposes:

```
GET /auth/.well-known/jwks.json
```

Response: a JSON Web Key Set containing the current public key (and the previous key during
rotation overlap). Services call this endpoint on startup and cache the result. On JWT
verification failure where the `kid` is not in cache, services re-fetch JWKS before
returning 401.

### Node.js library

Use `jose` (not `jsonwebtoken`). `jose` supports JWKS natively via `createRemoteJWKSet`,
handles RS256, and avoids the `algorithm: none` vulnerability class in older libraries.

---

## Decision B — Access token: 15-minute TTL, Flutter in-memory only

### TTL

**15 minutes** (`ACCESS_TOKEN_TTL_SECONDS = 900`).

Justification from the blast-radius scenario: if an attacker extracts a Flutter access
token from device memory (via process dump, screenshot of debug state, or a malicious
library with memory access), the token is valid for at most 15 minutes. After that, every
API call returns 401 and the attacker can do nothing with the token. No action from the
system is required.

15 minutes is long enough for an uninterrupted user session (checking a bill, submitting
an objection, viewing notifications takes 2–5 minutes). The Dio interceptor refreshes
transparently on 401, so the user never sees the expiry during active use.

### Flutter storage: in-memory only

The access token is stored in a Riverpod `StateProvider<String?>` (or equivalent Bloc
state). It is never written to any file, database, or secure storage on the device.

**Why in-memory:**

1. **Short lifespan makes persistence pointless.** A 15-minute token that is lost on
   app close restarts cleanly via the refresh token. There is nothing to gain by persisting
   something that expires before the user is likely to reopen the app.

2. **Disk storage survives the app.** Files in app-private storage, `SharedPreferences`,
   and `flutter_secure_storage` all survive app close and device restart. Android cloud
   backup and ADB backup (`adb backup`) can extract `SharedPreferences` and app files
   unless `android:allowBackup="false"` is set. A 15-minute token on disk provides no
   security benefit but extends the extraction surface to backup tooling and forensic
   analysis.

3. **Memory is cleared on logout.** Logout sets the in-memory provider to null. The
   access token ceases to exist on the device immediately — no revocation delay, no
   residual storage to clean.

### Token format

The access token is a signed JWT. Payload claims:

```json
{
  "sub": "<userId CUID>",
  "iat": 1750000000,
  "exp": 1750000900,
  "jti": "<CUID — unique per token; reserved for future blacklisting>",
  "alg": "RS256"
}
```

Header:
```json
{
  "alg": "RS256",
  "kid": "<current Key Vault key ID>",
  "typ": "JWT"
}
```

---

## Decision C — Refresh token: 30-day TTL, flutter_secure_storage, rotate on every use

### TTL

**30 days** (`REFRESH_TOKEN_TTL_DAYS = 30`).

Justification: EasyRates is a monthly billing app. Users open it when their bill arrives.
A 30-day TTL means a user who opens the app once a month stays logged in indefinitely
without re-authentication, as long as each monthly session refreshes before the token
expires. A 7-day TTL forces re-login for any user who doesn't open the app in a week —
unacceptable for a low-frequency utility app.

### Flutter storage: flutter_secure_storage

The refresh token is stored using the `flutter_secure_storage` package.

**iOS:** writes to the iOS Keychain with accessibility
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The Keychain is hardware-backed on
devices with Secure Enclave (all iPhones since 5s). The value is not included in iCloud
or iTunes backups when this accessibility level is set. A locked device cannot be read
via Keychain extraction without the device passcode.

**Android:** writes to Android Encrypted Shared Preferences, backed by the Android
Keystore System. On devices with a hardware-backed keystore (Android 6+ with a secure
element), the encryption key is generated and stored in hardware and is not extractable.
ADB backup does not extract Keystore-backed data. The value requires device unlock to read.

The refresh token is worth persisting because it represents the long-lived session that
would otherwise require full OTP re-authentication to establish.

### Token format: opaque string

The refresh token is a cryptographically random 256-bit value (32 bytes from
`crypto.randomBytes(32)`) encoded as a hex string. It is not a JWT.

- It is always validated against the database (no stateless verification).
- It does not carry a `kid` or signing-key dependency — key rotation does not affect it.
- The plaintext token is sent once (in the login or refresh response). Auth-service stores
  only its `SHA-256` hash in the `RefreshToken` table.

### Rotation policy: rotate on every use

Every call to `POST /auth/refresh` does all of the following atomically:

1. Look up the submitted token hash in the `RefreshToken` table.
2. Verify `revokedAt IS NULL` and `expiresAt > NOW()`.
3. Set `revokedAt = NOW()` on the current row.
4. Generate a new random refresh token + a new JWT access token.
5. Insert a new `RefreshToken` row with `familyId` inherited from the current row.
6. Return `{ accessToken, refreshToken }`.

Each refresh token is single-use. The previous token is revoked before the new one is
issued. Steps 3–5 are a single database transaction.

**Why not rotate on expiry only:** A stolen refresh token that is only rotated on expiry
remains valid for its entire remaining TTL (up to 30 days). There is no detection
mechanism. Rejected.

### Reuse attack detection

If a refresh token that is already `revokedAt IS NOT NULL` is presented:

1. Auth-service identifies the `familyId` of the presented token.
2. It revokes ALL `RefreshToken` rows with the same `familyId` for this userId
   (setting `revokedAt = NOW()` on the entire chain).
3. Returns 401 to the caller.
4. Emits an `OTP_FAILED` or new `REFRESH_TOKEN_REUSE` AuditEvent.

The result: both the legitimate user and the attacker are locked out. The legitimate user
must re-authenticate with phone + OTP. The attacker cannot proceed without
physical access to the user's phone.

---

## Decision D — Revocation: no Redis blacklist

**No Redis blacklist in Phase 1.**

### Why a blacklist is not needed

**Logout:** The Flutter client destroys the in-memory access token immediately on logout.
It deletes the refresh token from `flutter_secure_storage`. It calls `POST /auth/logout`
which revokes the `RefreshToken` row in the database. There is no dangling token on the
device — logout on mobile is a device-local action that clears the only copies that exist.

**POPIA erasure:** The JWT middleware reads `User.deletedAt` on every authenticated request
(one indexed read: `WHERE id = ? AND deletedAt IS NULL`). When `deletedAt` is set, the
middleware returns 401 immediately. This is equivalent to instant revocation — no Redis
required. The erasure is effective within one database read of the request arriving.

**Stolen access token:** The blast radius is the remaining TTL at the moment of theft —
at most 15 minutes. No intervention is needed; the token expires naturally.

**Stolen refresh token:** Detected via reuse attack detection (Decision C). The attacker
can mint access tokens only until the legitimate user next refreshes (at which point reuse
is detected and all sessions are revoked). The access token they hold expires in at most
15 minutes.

### Maximum revocation lag per scenario

| Scenario | Lag |
|---|---|
| Logout (same device) | 0 seconds — in-memory token destroyed |
| POPIA erasure | 0 seconds — deletedAt check in middleware |
| Account suspension | 0 seconds — same deletedAt/status check in middleware |
| Stolen access token | ≤ 15 minutes — natural TTL expiry |
| Stolen refresh token | ≤ 15 minutes after reuse detection |

A Redis blacklist would reduce the "stolen access token" lag from 15 minutes to near-zero.
This is not justified at pilot scale: 15 minutes is an acceptable lag for a mobile billing
app, and the infrastructure cost (Redis instance, cache invalidation logic, latency on
every request) is disproportionate to the risk reduction.

**Re-evaluate at:** ≥ 10,000 DAU, or if a financial institution integration requires
real-time session termination capability.

---

## Decision E — Key rotation: JWKS with overlap window

### Rotation procedure

Key rotation requires no service redeployment and invalidates no active sessions.

**Step 1.** Generate a new RSA-2048 key pair in Azure Key Vault. Assign a new `kid`
(e.g., `kid: "2026-07-01"`). The old key retains its existing `kid`.

**Step 2.** Update auth-service config (`JWT_SIGNING_KEY_ID`) to point to the new key.
Auth-service starts signing new tokens with the new private key. New tokens carry
`kid: "2026-07-01"` in the JWT header. Old tokens carry the previous `kid`.

**Step 3.** Add the new public key to the JWKS endpoint response alongside the old public
key. The endpoint now returns two keys.

**Step 4.** Wait 15 minutes (one access token TTL). All tokens signed with the old key
have either been refreshed (and are now signed with the new key) or expired naturally.

**Step 5.** Remove the old public key from the JWKS endpoint. Disable (do not delete)
the old private key in Key Vault — Key Vault retains it for audit.

### Service-side JWKS caching

Each service caches the JWKS response in memory. Cache TTL: 5 minutes
(`Cache-Control: max-age=300`). On JWT verification failure where the `kid` is not found
in cache, the service re-fetches JWKS before returning 401. This means:

- During rotation, services that cached the old JWKS will auto-refresh within 5 minutes
  when they encounter a token with the new `kid`.
- No service needs to be redeployed or reconfigured during rotation.

### Node.js implementation

```typescript
import { createRemoteJWKSet, jwtVerify } from 'jose'

const JWKS = createRemoteJWKSet(
  new URL('http://auth-service/auth/.well-known/jwks.json'),
  { cacheMaxAge: 300_000 } // 5-minute cache
)

export async function verifyAccessToken(token: string) {
  const { payload } = await jwtVerify(token, JWKS, { algorithms: ['RS256'] })
  return payload
}
```

`createRemoteJWKSet` handles cache refresh on `kid` miss automatically.

---

## Dio interceptor (Flutter)

The Flutter Dio client wraps all authenticated requests with a transparent refresh flow.

```dart
// On every 401 response from any endpoint:
// 1. Read refresh token from flutter_secure_storage
// 2. POST /auth/refresh with the refresh token
// 3. On 200: store new access token in-memory; store new refresh token in secure storage
// 4. Retry the original request with the new access token
// 5. On refresh 401 (token revoked or expired): clear both tokens; navigate to Login screen
```

The user never sees a "session expired" message during normal use. They see the Login
screen only when the refresh token has expired (30 days of inactivity) or when a reuse
attack triggers full revocation.

---

## RefreshToken table

This model is missing from `docs/data-model/user-auth.md` and must be added.

```prisma
model RefreshToken {
  id         String    @id @default(cuid())
  userId     String
  tokenHash  String    @unique  // SHA-256 hex of the plaintext refresh token
  familyId   String             // links a rotation chain for reuse attack detection
  expiresAt  DateTime
  revokedAt  DateTime?          // null = active; set on rotation or explicit revocation
  createdAt  DateTime  @default(now())

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@index([userId, revokedAt])
}
```

`@@index([userId, revokedAt])` — serves `WHERE userId = ? AND revokedAt IS NULL` when
revoking all active tokens for a user (logout-all or reuse attack response).

---

## Blast-radius test

Scenario: attacker has extracted both the access token and the refresh token from a
compromised device.

**Minute 0–15: attacker uses the access token.**
Every service verifies the JWT signature against JWKS and checks `exp`. The token is
valid. The attacker can read bills, submit objections, read notifications for the user.

**Minute 15: access token expires.**
Every API call returns 401. The attacker cannot use the access token any further.

**Minute 15+: attacker uses the refresh token.**
`POST /auth/refresh` with the stolen refresh token. Auth-service finds the token hash in
`RefreshToken`, verifies it is not revoked, atomically revokes it, issues a new access
token and a new refresh token. The attacker now has a new 15-minute access token and a
new single-use refresh token.

**When the legitimate user next opens the app:**
The Dio interceptor, on receiving a 401 from their expired access token, calls
`POST /auth/refresh` with their stored refresh token. But that token was already rotated
by the attacker. Auth-service finds `revokedAt IS NOT NULL`. Reuse detected.
Auth-service revokes all `RefreshToken` rows with the same `familyId`. Returns 401.
Dio interceptor clears both tokens. User sees the Login screen.

**Attacker's session after reuse detection:**
The attacker's new refresh token (from the rotation in the previous step) is now also
revoked (same `familyId`). Their next `POST /auth/refresh` returns 401. Their current
access token expires within 15 minutes. Access is terminated.

**Maximum attacker persistence:**
15 minutes after the legitimate user triggers reuse detection. If the legitimate user does
not open the app (phone is off, app is closed), the attacker can keep refreshing
indefinitely — until either:
- The legitimate user next opens the app (triggers detection), or
- An admin suspends the account (sets `deletedAt`; middleware rejects all requests).

The 15-minute access token TTL limits the API blast radius per rotation cycle even without
detection.

---

## Configuration constants

Copy these verbatim into `backend/plans/03-auth-service.md`. No auth-service
implementation may use different values.

```
JWT_ALGORITHM              = RS256
JWT_SIGNING_KEY_ID         = <current Azure Key Vault key name>
JWKS_ENDPOINT              = /auth/.well-known/jwks.json
JWKS_CACHE_TTL_MS          = 300_000        // 5 minutes

ACCESS_TOKEN_TTL_SECONDS   = 900            // 15 minutes
ACCESS_TOKEN_STORAGE       = in-memory only (Flutter Riverpod state — never written to disk)

REFRESH_TOKEN_TTL_DAYS     = 30
REFRESH_TOKEN_STORAGE      = flutter_secure_storage (iOS Keychain / Android Keystore)
REFRESH_TOKEN_FORMAT       = opaque 256-bit random hex (not JWT)
REFRESH_TOKEN_ROTATION     = on every use (single-use; rotate atomically)
REFRESH_TOKEN_HASH         = SHA-256, stored in RefreshToken.tokenHash

REVOCATION_STRATEGY        = no Redis blacklist; deletedAt check in JWT middleware;
                             reuse attack detection via familyId chain revocation
MAX_REVOCATION_LAG         = 15 minutes (access token TTL) for theft scenarios;
                             0 seconds for logout and POPIA erasure
```
