# EasyRates — OWASP Mobile Top 10 (2023) Cross-Check

**OWASP version:** Mobile Top 10 2023 (owasp.org/www-project-mobile-top-10/)  
**Date of cross-check:** 2026-06-20  
**Design documents in scope:**
- `docs/security/sessions.md` — JWT model (plans/01)
- `docs/security/rate-limits.md` — rate limiting (plans/02)
- `docs/security/upload-validation.md` — file upload (plans/03)
- `docs/data-model/` — data model and POPIA inventory (plans/00)
- `api/auth.md`, `api/objection.md` — API contracts

**Note on numbering:** The user's task references "M5 Inadequate Privacy Controls."
In the standard 2023 OWASP Mobile Top 10, M5 is Insecure Communication and M6 is
Inadequate Privacy Controls. This document uses the standard 2023 numbering.
Items the user flagged for close examination are marked ★.

---

## Summary table

| # | Title | Status | One-line note |
|---|---|---|---|
| M1 ★ | Improper Credential Usage | **PASS** | Access token in-memory (Riverpod); refresh token in flutter_secure_storage Keychain/Keystore; signing key in Azure Key Vault — no hardcoded credential anywhere. |
| M2 ★ | Inadequate Supply Chain Security | **ACCEPT** | Reputable packages with pnpm lockfile; no SCA tool or npm audit in CI yet — pilot risk accepted; production trigger: npm audit + Dependabot before go-live. |
| M3 | Insecure Authentication/Authorization | **MITIGATE** | Auth is strong (RS256, OTP, 15-min TTL, rotation); authorization relies on handler-level ownership checks with no shared guard middleware — one forgotten check leaks data. |
| M4 | Insufficient Input/Output Validation | **MITIGATE** | File validation strong (Zod, magic-byte check, 10 MiB limit, MIME allowlist); gap: `express.json({ limit: '64kb' })` not yet explicitly configured; error responses strip stack traces. |
| M5 | Insecure Communication | **MITIGATE** | All Azure endpoints enforce HTTPS; tokens in Authorization header, not query string; TLS termination at App Service ingress not yet confirmed in node-hardening.md. |
| M6 ★ | Inadequate Privacy Controls | **MITIGATE** | POPIA inventory complete; erasure gives 0-second revocation; column-level encryption on PII fields (phone, email, address, accountNumber) NOT YET IMPLEMENTED — go-live gate. |
| M7 | Insufficient Binary Protections | **ACCEPT** | No client-side secrets or proprietary algorithms in binary; Flutter `--obfuscate` not yet confirmed in release build — one-line fix; no RASP required at pilot. |
| M8 ★ | Security Misconfiguration | **MITIGATE** | helmet.js, NODE_ENV, startup env validation, CORS, and error sanitization all scoped in plan/05 but node-hardening.md not yet written — M8 cannot be Pass until that document is complete. |
| M9 | Insecure Data Storage | **MITIGATE** | Refresh token in hardware-backed storage; access token in-memory; Azure SQL TDE + Blob AES-256 at rest; column-level encryption gap same as M6; `android:allowBackup=false` not yet confirmed. |
| M10 | Insufficient Cryptography | **PASS** | RS256 (2048-bit), bcrypt (12 rounds), crypto.randomBytes(32) for refresh tokens, SHA-256 for token hash storage, TLS 1.2+ at Azure ingress, no home-grown crypto. |

**Tally:** 2 Pass · 5 Mitigate · 2 Accept · 0 Blank

---

## Detailed analysis

### M1 ★ — Improper Credential Usage | PASS

**What it covers:** Hardcoded credentials, insecure storage of access tokens/API keys, weak
credential mechanisms.

**Controls in place:**

| Credential | Storage | Evidence |
|---|---|---|
| JWT access token | Flutter `StateProvider<String?>` (Riverpod) — in-memory only, cleared on app close and logout | sessions.md Decision B |
| JWT refresh token | `flutter_secure_storage` → iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) / Android Keystore (hardware-backed) | sessions.md Decision C |
| RSA signing key | Azure Key Vault — auth-service calls Key Vault `sign` API; key never leaves Key Vault; never in env vars or container filesystem | sessions.md Decision A |
| Refresh token server-side | SHA-256 hash stored in `RefreshToken.tokenHash`; plaintext sent once in response, never persisted | sessions.md Decision C |
| All other secrets | Environment variables (DATABASE_URL, REDIS_URL, TWILIO_*); validated at startup; no defaults that are also production secrets | plan/05 scope |

**No hardcoded credentials** in any source file by design. Azure Key Vault is the single
point of key storage.

**Implementation risk** (not a design gap): a developer could accidentally log an access
token in debug output. Add `ACCESS_TOKEN` and `REFRESH_TOKEN` to the log-scrubbing deny-list
when node-hardening.md is written.

---

### M2 ★ — Inadequate Supply Chain Security | ACCEPT (pilot) → MITIGATE (production)

**What it covers:** Third-party packages with known vulnerabilities; unverified packages;
no software composition analysis (SCA) process.

**Controls in place:**

| Layer | Packages | Basis for trust |
|---|---|---|
| Node.js | `jose`, `express-rate-limit`, `file-type`, `multer`, `prisma`, `bcrypt`, `zod`, `express` | Top-tier npm adoption; used in production by major vendors |
| Flutter | `flutter_secure_storage`, `dio`, `file_picker` | Google-verified or widely used in production Flutter apps |
| Lockfile | `pnpm-lock.yaml` provides deterministic installs by content hash | Prevents version drift between installs |

**Not defined:**

- No `pnpm audit --audit-level=critical` step in CI pipeline
- No Dependabot or Renovate for automated dependency update PRs
- No SBOM (Software Bill of Materials) — may be required for SA government procurement
- No `--ignore-scripts` at install time (malicious lifecycle scripts not blocked)

**Acceptance rationale:** At pilot, ~7 Node.js services use ~15 npm packages, all actively
maintained. The attack surface for a supply chain compromise in the pilot window is narrow.

**Production trigger (all three required before production launch):**
1. `pnpm audit --audit-level=critical` in CI — blocks merge if critical CVE
2. Dependabot or Renovate auto-PRs with weekly schedule
3. SBOM generation via `@cyclonedx/cyclonedx-npm` if municipal procurement requires it

---

### M3 — Insecure Authentication/Authorization | MITIGATE

**What it covers:** Broken authentication flows, insufficient session management,
authorization checks that can be bypassed.

**Authentication: PASS**

| Control | Mechanism | Reference |
|---|---|---|
| Token signing | RS256, Azure Key Vault private key — compromise of any resource service reveals only the public key | sessions.md Decision A |
| Access token TTL | 15 minutes — stolen token expires naturally; no Redis blacklist needed | sessions.md Decision B |
| Refresh token | Rotate on every use; familyId reuse detection revokes all sessions on reuse | sessions.md Decision C |
| Account revocation | `User.deletedAt` check in JWT middleware — 0-second lag for POPIA erasure and suspension | sessions.md Decision D |
| Phone verification | Twilio Verify OTP on registration and login — confirms phone ownership (passwordless, ADR-002) | twilio-integration.md |
| Credential stuffing | 10 requests / 15 min / IP on all auth endpoints | rate-limits.md Category 1 |
| Enumeration prevention | CUID PKs on all models — no sequential integer guessable by iteration | data-model/decisions.md D |

**Authorization: MITIGATE**

Authorization is enforced per-handler:
- `propertyId must be linked to requesting user` (checked in property-service handlers)
- `objection not owned by this user → 403` (checked in objection-service handlers)
- Property enumeration: SEARCH category 10/min/userId cap prevents systematic scraping

**Residual risk:** Authorization is handler-level, not middleware-enforced. A new route that
omits the ownership check silently exposes data. There is no ABAC/RBAC guard that makes
this structurally impossible to omit.

**Mitigation:** Define `assertOwnsProperty(req, propertyId)` and
`assertOwnsObjection(req, objectionId)` as shared utility functions; add code-review
checklist item. Full ABAC middleware is the production trigger.

---

### M4 — Insufficient Input/Output Validation | MITIGATE

**What it covers:** SQL injection, oversized payloads, malformed requests, data leakage
in error responses.

**Controls in place:**

| Vector | Control | Reference |
|---|---|---|
| SQL injection | Prisma ORM — all queries are parameterized; no raw SQL in design documents | prisma schema |
| File type | Magic-byte check (`file-type`) — reads actual bytes, not Content-Type header | upload-validation.md Rule C |
| File size | `multer({ limits: { fileSize: 10_485_760 } })` — rejects before buffer fills | upload-validation.md Rule B |
| MIME allowlist | PDF, JPEG, PNG only; exclusion table covers Office, ZIP, HTML, executables | upload-validation.md Rule A |
| Request body schema | Zod validation on all API inputs (plan/03, plan/05) | api/auth.md, api/objection.md |
| String length | `description: 10–2000 chars` enforced; enum fields validated against allowlist | api/objection.md |
| Error responses | `{ data: null, error: { code, message } }` — no stack traces, no file paths in production | plan/05 checklist item g |
| Enumeration | SEARCH rate limit 10/min/userId + CUID PKs | rate-limits.md Category 4b |

**Residual risk / gaps:**

1. **JSON body size limit:** `express.json()` default is 100 kb. A malformed client sending
   a 10 MB JSON payload to a non-upload endpoint would buffer the entire body before Zod
   rejects it. **Gap:** `express.json({ limit: '64kb' })` should be explicit in
   node-hardening.md.

2. **Output XSS:** Flutter is a native client — reflected/stored XSS via API responses is
   not applicable to the current design. If a municipality admin WebView panel is added,
   all stored string fields (description, filename, displayName) must be HTML-escaped before
   rendering.

---

### M5 — Insecure Communication | MITIGATE

**What it covers:** Missing TLS, weak cipher suites, sensitive data in query strings or
log lines, certificate validation bypassed.

**Controls defined:**

| Channel | TLS status | Notes |
|---|---|---|
| Flutter → App Service | HTTPS enforced at Azure App Service ingress | Azure HTTPS-only mode |
| App Service → Azure SQL | Encrypted by Azure SQL by default (TLS 1.2+) | Azure default |
| App Service → Redis | TLS port 6380 (Azure Cache for Redis default) | Azure default |
| App Service → Azure Key Vault | HTTPS (Azure SDK default) | Azure default |
| auth-service → Twilio | Twilio Verify API requires HTTPS (Twilio enforcement) | Twilio guarantee |
| App Service → Azure Blob | HTTPS only; private container; no anonymous GET | Azure Blob default |
| Tokens in transit | `Authorization: Bearer` header — never in URL query string, never in server logs | api/auth.md |

**Residual risk / gaps:**

1. **TLS termination confirmation:** The design assumes Azure App Service handles TLS at
   the ingress layer. The Node.js service receives plaintext internally. This must be
   confirmed in node-hardening.md: App Service HTTPS-only mode enabled; HTTP → HTTPS
   redirect; Node.js not exposed on a public HTTP port.

2. **HSTS:** `helmet.js` enables `Strict-Transport-Security: max-age=31536000` by default.
   Must be confirmed when helmet is configured.

3. **Certificate pinning:** Not implemented. `dio` uses the system TLS trust store.
   Acceptable for a billing query app at pilot scale. Pinning is required by the
   Minimum Information Security Standards (MISS) if EasyRates is classified as a
   government system under SITA governance.

**Production trigger:** MISS classification assessment before go-live. If SITA/MISS scope
applies, certificate pinning becomes mandatory.

---

### M6 ★ — Inadequate Privacy Controls | MITIGATE (go-live gate: column-level encryption)

**What it covers:** Collecting, storing, or transmitting personal information without
appropriate consent, access controls, data minimization, or encryption.

**POPIA field classification summary (from plan/00 inventory):**

| Sensitivity | Fields | Control in place |
|---|---|---|
| Special personal info (POPIA §26) | `EvidenceFile.kycDocumentKey` (blob key to SA ID copy) | Private blob container; proxy-only download; AuditEvent on every access |
| High-risk PII | `User.phone`, `User.email`, `User.displayName` | Rate-limited; not returned in public responses; OTPAttempt purged after 30 days |
| PII | `Property.address`, `Property.ownerName`, `Account.accountNumber`, `Bill.accountNumber` | Returned only to authenticated account holder; access AuditEvent |
| Financial | Bill amounts, arrears, payment history | Authenticated-user-only; 5-year retention per SA financial regulations |

**Controls in place:**

- **POPIA erasure:** `User.deletedAt` set → JWT middleware returns 401 immediately (0-second
  revocation lag); PII fields nulled; kycDocumentKey blob deleted. Sessions.md Decision D.
- **Notification retention:** Hard-deleted after 90 days.
- **Soft-delete on legal records:** Objection and EvidenceFile retain referential integrity
  for dispute resolution even after user erasure (POPIA erasure vs consumer protection
  regulation tension is documented in data-model/objection.md).
- **Enumeration prevention:** CUID PKs + SEARCH rate limit 10/min/userId.
- **Payment card data:** EasyRates is not a payment processor. No PAN/CVV/expiry collected
  or stored at any layer. Upload-validation.md Rule E.

**Critical gap — go-live gate:**

Column-level encryption (CLE) is **not yet implemented.** Fields `User.phone`,
`User.email`, `User.displayName`, `Property.address`, `Property.ownerName`,
`Account.accountNumber`, `Bill.accountNumber` are stored in **plaintext in Azure SQL.**

Azure SQL TDE (Transparent Data Encryption) is enabled by default — it encrypts physical
storage files and protects against physical media theft. It does **not** protect against
a valid-credential SQL query or a compromised database administrator account.

Column-level encryption with keys in Azure Key Vault is required for POPIA compliance
before production launch. A valid-credential attacker who exfiltrates the database
sees plaintext PII without CLE. With CLE, they see only ciphertext.

**Go-live gate:** CLE on all PII fields must be implemented. Key in Azure Key Vault.
Plan reference: plan/00-popia-inventory.md CONTROLS task.

**Open question:** `Property.metadata` (untyped JSON from municipality billing system sync)
may contain unknown PII sub-fields. Must be audited against actual municipality export
format before go-live. Any PII sub-field must be extracted into a typed column or the
entire column must be encrypted.

---

### M7 — Insufficient Binary Protections | ACCEPT (pilot) → MITIGATE (production)

**What it covers:** Mobile app binary reverse engineering, code extraction, tampering,
missing obfuscation.

**Controls in place:**

- No secrets hardcoded in the Flutter app binary. API base URL is the only
  configuration embedded; the JWT signing key never appears client-side.
- Flutter compiles to native ARM bytecode — harder to reverse than JVM bytecode.
- No proprietary AI model or municipality-specific signing key embedded in client binary.

**Not confirmed:**

- Flutter release build obfuscation flags (`--obfuscate --split-debug-info`) not yet
  verified as enabled in the build configuration. This is a one-line change in the
  `flutter build appbundle --release` command.

**Acceptance rationale:** At pilot, the app is distributed to ~2,500 registered users in
two Emfuleni wards. There are no client-side secrets or proprietary algorithms that would
give an attacker value from reverse engineering. The threat model for deliberate binary
reverse engineering at pilot scale is low.

**Production trigger:**
1. Play Store / App Store distribution — MASVS-RESILIENCE-1 baseline requires `--obfuscate`.
2. Any client-embedded secret or proprietary AI model triggers Runtime Application
   Self-Protection (RASP) requirement.

**Immediate action (no design change required):** Add
`--obfuscate --split-debug-info=build/app/outputs/symbols` to the Flutter release build
command in plan/04 (mobile build config). Zero design implications.

---

### M8 ★ — Security Misconfiguration | MITIGATE (→ PASS when node-hardening.md is written)

**What it covers:** Debug mode in production, missing security headers, open CORS, secrets
in committed files, missing environment validation.

**Controls scoped in plan/05-node-hardening.md (not yet implemented):**

| Item | Configuration | Status |
|---|---|---|
| `helmet.js` | All default headers: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, HSTS, `Referrer-Policy: no-referrer`; CSP deferred (Flutter is native, no browser) | Scoped — not yet written |
| `NODE_ENV=production` | Required in deployment environment; Express disables stack traces, enables caching, disables dev features | Scoped — not yet confirmed |
| Startup env validation | `zod` or `envalid` validates all required vars at startup: `DATABASE_URL`, `REDIS_URL`, `JWT_SIGNING_KEY_ID`, `TWILIO_*`, `ALLOWED_ORIGINS`, `NODE_ENV`; process crashes immediately if any missing or malformed | Scoped — not yet written |
| CORS | `origin: process.env.ALLOWED_ORIGINS` (not `*`); `credentials: false` (JWT in Authorization header — not cookies); explicit methods allowlist | Scoped — not yet written |
| Error sanitization | `{ data: null, error: { code, message } }` only; no stack field, no file paths in production error handler | Scoped — not yet written |
| JSON body limit | `express.json({ limit: '64kb' })` | Scoped — not yet confirmed |
| Secrets in VCS | `.env` files excluded from git via `.gitignore`; `git-secrets` or pre-commit hook not yet configured | Not yet confirmed |

**Residual risk:** node-hardening.md is the plan that documents all 7 items above. Until
that document is written and each item is marked Pass, M8 cannot be Pass. The scope is
well-defined; this is a documentation and implementation gap, not an architectural gap.

**Production trigger:** node-hardening.md WRITE task complete + all 7 checklist items Pass.

---

### M9 — Insecure Data Storage | MITIGATE

**What it covers:** PII written to device filesystem, SharedPreferences, unencrypted local
database, or cloud database without encryption at rest.

**Flutter client:**

| Data | Storage | Status |
|---|---|---|
| JWT access token | Riverpod `StateProvider` (RAM only) — cleared on app close and logout | PASS |
| JWT refresh token | `flutter_secure_storage` → iOS Keychain / Android Keystore | PASS |
| Bill data, property data | Not stored locally — fetched on demand from API | PASS |
| ADB backup protection | `android:allowBackup="false"` required in AndroidManifest.xml | **Gap — not confirmed** |

**Server side:**

| Storage | Encryption | Status |
|---|---|---|
| Azure SQL | TDE (AES-256) — enabled by default on all tiers; protects physical files | PASS (TDE) |
| Azure SQL PII fields | Plaintext — CLE not yet implemented | **Gap — go-live gate** |
| Azure Blob Storage | AES-256 server-side encryption (Azure default); private container | PASS |
| Azure Cache for Redis | Encryption at rest enabled by default on Azure Cache | PASS |
| OTPAttempt table | Contains `phone` (PII); 30-day TTL purge policy defined | PASS (with TTL) |

**Key residual risks:**

1. Column-level encryption not implemented — same gap as M6. Go-live gate. PII in Azure
   SQL is plaintext to any valid-credential query.

2. `android:allowBackup="false"` not yet confirmed. Without this, ADB backup on a rooted
   Android device or via `adb backup` can extract `SharedPreferences`. Although
   `flutter_secure_storage` uses Keystore (not SharedPreferences), the flag should be
   set as defense-in-depth.

3. `EvidenceFile.filename` stores the user-supplied original filename, which could contain
   PII (e.g. `molefes-id-jan2026.pdf`). The blob itself is stored under a CUID key — the
   filename is display-only. Control: the display field is subject to the same column-level
   encryption requirement as other PII fields.

---

### M10 — Insufficient Cryptography | PASS

**What it covers:** Weak or broken algorithms (MD5, SHA-1, DES, ECB mode), short key
lengths, hardcoded keys, insufficient randomness.

**Controls in place:**

| Operation | Algorithm | Standard |
|---|---|---|
| JWT signing | RS256 (RSA-SHA256), 2048-bit minimum | NIST SP 800-131A Rev 2 |
| JWT verification | RS256 via `jose` `createRemoteJWKSet` — `algorithm: 'none'` not accepted | jose library guarantee |
| Refresh token generation | `crypto.randomBytes(32)` — 256-bit CSPRNG | Node.js `crypto` built-in |
| Refresh token storage hash | SHA-256 hex — one-way lookup key; 256-bit source has sufficient entropy without salting | NIST |
| Transport encryption | TLS 1.2+ at Azure App Service ingress; weak cipher suites (RC4, DES, 3DES) disabled by Azure default | Azure TLS policy |
| Data at rest (blobs) | AES-256 server-side encryption (Azure default) | Azure Blob |
| No home-grown crypto | All crypto via `jose`, Node.js `crypto` built-in, `bcrypt` — no custom implementation | — |

**Residual risk:** RSA key rotation is defined (sessions.md Decision E — 15-minute overlap
window, Key Vault retains old key) but a **rotation schedule is not specified.** Before
production, define a rotation frequency (e.g., every 90 days) and automate it via Azure
Key Vault key rotation policy. A key that is never rotated is a key that is eventually
leaked without detection.

**Production trigger:** Document rotation frequency in sessions.md Decision E before
production launch; enable Azure Key Vault automatic rotation policy.

---

## THINK: hardest to test in CI

**Two items are most likely to be violated undetected in production:**

### M7 (Binary Protections) — hardest to test

`--obfuscate` is a build flag on the release build command. The debug build (used in CI
and development) works identically without it. No unit test fails. No integration test
fails. No linter catches it. The CI pipeline tests the debug APK; the Play Store receives
the release APK. The only environment where this matters is the one that is hardest to
test automatically.

A CI job that builds the release APK and checks for the presence of `--obfuscate` in
the `flutter build appbundle` command is the fix — but it is commonly skipped because
it requires building the full release artifact, which is slow.

### M6 (Privacy Controls — column-level encryption) — most dangerous to miss

The application functions correctly without column-level encryption. All tests pass.
The Flutter UI looks identical. The API contracts are satisfied. There is no runtime error.

The only way to detect the absence of CLE from outside the database is a penetration test
that directly queries the database and reads a PII column. This is outside the scope of
unit tests, integration tests, and CI pipelines. It requires a deliberate audit step.

EasyRates is specifically at risk here because the go-live pressure is driven by a
municipality with documented financial distress. "We'll add encryption after launch" is
the most predictable path to a POPIA breach notification obligation.

**Control:** Make CLE an explicit CI gate — add a startup check that queries a known PII
field, confirms it returns ciphertext (not plaintext), and crashes the service if not. This
is the only way to prevent a deployment without CLE from reaching production.

---

## Open items requiring action before go-live

| Item | OWASP ref | Action | Owner |
|---|---|---|---|
| Column-level encryption | M6, M9 | Implement CLE on all PII fields; key in Azure Key Vault | architect → dev |
| node-hardening.md | M8 | Write plan/05 output document; all 7 checklist items Pass | architect → dev |
| `android:allowBackup="false"` | M9 | Confirm in AndroidManifest.xml | dev |
| Flutter `--obfuscate` in release build | M7 | Add flag to release build command in plan/04 | dev |
| SCA in CI pipeline | M2 | `pnpm audit --audit-level=critical` in CI; Dependabot config | dev/ops |
| JWT key rotation schedule | M10 | Document 90-day rotation in sessions.md Decision E; enable Azure KV policy | architect |
| `express.json({ limit: '64kb' })` | M4, M8 | Add to node-hardening.md checklist | dev |
| TLS termination confirmation | M5 | Confirm App Service HTTPS-only mode in node-hardening.md | dev/ops |
| `Property.metadata` PII audit | M6 | Audit against municipality export format before go-live | architect |
| Authorization middleware | M3 | Define `assertOwnsProperty` / `assertOwnsObjection` utility functions | dev |
