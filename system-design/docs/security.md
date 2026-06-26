# EasyRates Security Design

**Status:** Complete (six sub-documents linked)  
**Date:** 2026-06-20  
**Input to:** ADR-001 (parent scope)

---

## Posture summary

EasyRates is a Flutter mobile client backed by a Node.js/Express microservice backend on
Azure, processing municipal billing dispute records for Emfuleni Local Municipality
ratepayers. The system holds personal information across 15 Prisma models (including two
Special Personal Information fields under POPIA §26: SA ID document blobs via
`User.kycDocumentKey` and `EvidenceFile.storageKey`). The security design is complete
across six domains: POPIA field classification and erasure procedure, RS256 JWT session
management (Azure Key Vault signing), six-category rate limiting, magic-byte file
validation, OWASP Mobile Top 10 cross-check (2 Pass / 6 Mitigate / 2 Accept), and
Node.js production hardening. Overall risk posture is **low at pilot** — all endpoints
require authentication, files are validated at the byte level before storage, and
rate limiters cover every attack surface — with **one mandatory go-live gate**:
column-level encryption (CLE) on all 14 PII fields must be implemented before production
to meet POPIA §19 confidentiality obligations.

---

## Sub-documents

| Document | Key finding |
| --- | --- |
| [POPIA Field Inventory](security/popia-inventory.md) | `User.kycDocumentKey` and `EvidenceFile.storageKey` are Special Personal Information (SA ID document blobs); CLE on 14 PII fields across 7 models is the mandatory go-live gate; `Property.metadata` is unknown-PII until audited against the municipality export format. |
| [JWT Security Model](security/sessions.md) | RS256 with Azure Key Vault (private key never leaves Key Vault); access token 15-minute TTL stored in-memory only; refresh token is an opaque 256-bit hex stored as SHA-256 hash, rotated on every use, and held in `flutter_secure_storage`; `User.deletedAt` check gives 0-second revocation with no Redis dependency. |
| [Rate Limits](security/rate-limits.md) | Six categories via `express-rate-limit` v7 covering all 37 endpoints; key ceilings: AUTH 10/15 min/IP, OTP-SEND 3/10 min/phone, SUBMIT 5/24 hr/userId, AI-ESTIMATE 5/1 min/userId; memory store at pilot; trigger to Redis: >1 Node.js instance. |
| [Upload Validation](security/upload-validation.md) | `file-type` npm magic-byte check (first 4,100 bytes) rejects non-PDF/JPEG/PNG at 422 before blob write; max 10 MiB (P99 covers all three file types); AV scan deferred — Azure Defender for Storage (~$3.38/year) activated when municipality integration goes live; no payment card data collected or stored. |
| [OWASP Mobile Top 10](security/owasp.md) | 2 Pass (M1 Credential Usage, M10 Cryptography) / 6 Mitigate / 2 Accept; Accepts are M2 Supply Chain (trigger: `pnpm audit` + Dependabot in CI before production) and M7 Binary Protections (trigger: Flutter `--obfuscate --split-debug-info` confirmed in release build before production); highest-risk gap is M6 Privacy Controls — CLE absence passes all tests silently. |
| [Node.js Hardening](security/node-hardening.md) | helmet.js enabled with CSP disabled (JSON-only API, no HTML served); `app.set('trust proxy', 1)` MUST be first line (without it `req.ip` returns the load balancer's IP and all rate limiters fail silently); Zod env schema crashes the process on missing secrets at startup; CORS locked to `ALLOWED_ORIGINS` env var; error handler strips stack traces and SQL details in production. |
| [Authorization Blast-Radius Audit](security/authorization.md) | All 37 Flutter-callable endpoints verified; blast-radius is user-scoped for account/bill/objection/notification/status; two property-service gaps: `GET /property?accountNumber=` exposes third-party `owner` name (fix: remove field), and 4 status-service endpoints have undocumented ownership checks; `shared/authz.ts` utility pattern required (return 404 not 403 on ownership failure). |

---

## Five things a new team member must know

**1. The refresh token lives in `flutter_secure_storage` — never in the JWT payload or on disk.**  
The access token is in-memory only and lasts 15 minutes. On app restart, the app calls
`POST /auth/refresh` using the stored opaque token to get a new access token — it does
not re-authenticate. The refresh token is single-use: the server issues a new one with
every successful refresh call and revokes the old one. Never store the access token in
shared preferences or a database — it is in-memory by design so that OWASP M9 (Insecure
Data Storage) has nothing to steal. Source: [sessions.md](security/sessions.md) Decisions B and C.

**2. Column-level encryption is not implemented — this is a go-live gate, not a backlog item.**  
Azure SQL TDE encrypts physical files on disk, but a valid-credential SQL query returns
phone numbers, addresses, and account numbers in plaintext. CLE with Azure Key Vault is
the only control for POPIA §19 before production. The fields requiring CLE are listed
explicitly in [popia-inventory.md](security/popia-inventory.md) (14 PII fields across
7 models, plus `Property.metadata` pending audit). There is no runtime error when CLE is
absent — the code runs and all tests pass — so it must be tracked as a deployment gate,
not a failing test. Source: [owasp.md](security/owasp.md) M6, [popia-inventory.md](security/popia-inventory.md) control gap table.

**3. `app.set('trust proxy', 1)` must be the first line in `app.ts` — before any middleware.**  
Without it, `req.ip` returns the Azure App Service load balancer's internal IP
(`10.x.x.x`), not the client's IP. Every rate limiter in the system uses `req.ip` as
the key for IP-based limits (`authLimiter`, `refreshLimiter`, `otpSendLimiter`). With
the wrong IP, all clients share the same rate-limit counter and a single legitimate burst
from one user blocks all other users. This setting must precede `helmet`, `cors`,
`express.json`, and all routers. Source: [node-hardening.md](security/node-hardening.md) item 1.

**4. The `Content-Type` header and file extension are not trusted for upload validation.**  
Both are set by the HTTP client and trivially faked (`curl -F "file=@malware.exe;type=application/pdf"`). The `validateMimeType` middleware reads the first 4,100 bytes of the file buffer via the `file-type` npm package and detects the real format. A file that claims to be a JPEG but has no JPEG magic bytes (`FF D8 FF`) is rejected with 422 before it reaches Azure Blob Storage. The _detected_ MIME type (not the declared one) is stored in `EvidenceFile.mimeType` and used when serving downloads. Do not bypass this middleware or trust the incoming `Content-Type`. Source: [upload-validation.md](security/upload-validation.md) Rule C.

**5. The two OWASP Accept items must be closed before production launch — they are not risk-accepted indefinitely.**  
M2 (Supply Chain Security): add `pnpm audit --audit-level=critical` to the CI pipeline
and enable Dependabot on the repo. One workflow file addition, no code changes. M7
(Binary Protections): confirm `flutter build appbundle --obfuscate --split-debug-info=...`
is the production release command, not `flutter build appbundle` alone (without flags,
the binary ships with readable symbol names and the stack trace is reconstructible). Both
items have zero test coverage — they silently remain open unless explicitly checked in the
deployment checklist. Source: [owasp.md](security/owasp.md) M2 and M7 open item table.
