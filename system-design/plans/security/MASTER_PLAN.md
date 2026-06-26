# EasyRates Security Design

## Mission

Produce a complete, auditable security design for EasyRates before any backend code
is written. EasyRates handles personal municipal account data — including South African
identity numbers (special personal information under POPIA) — for the Flutter mobile
app. This scope covers POPIA compliance for all 12 model entities, JWT lifecycle for
the Flutter client, rate limiting for all REST endpoint categories, file upload
validation via magic-byte check for evidence documents, OWASP Mobile Top 10
cross-check, and Node.js production hardening. Security is a non-optional design
constraint on every service, API contract, and data model decision in the parent scope.

## Objectives

1. Classify every data model field under POPIA; assign a named control to every PII
   and Financial field; identify `idNumber` as special personal information with
   stricter obligations than ordinary PII.
2. Define the JWT security model for the Flutter client: algorithm, access token TTL
   and in-memory storage, refresh token storage (`flutter_secure_storage`), rotation
   policy, and revocation strategy.
3. Set rate limits for every REST endpoint category using Node.js middleware
   (`express-rate-limit` or equivalent); scope, window, and limit for each category.
4. Define file upload validation via magic-byte check for REST multipart uploads
   (evidence documents) using the `file-type` npm package; no payment card data
   stored locally.
5. Cross-check the full design against OWASP Mobile Top 10.
6. Produce a Node.js production-ready environment configuration: `helmet.js`,
   HTTPS enforcement, environment variable validation, CORS policy, secrets management.

## Goals

- G0 `docs/security/popia-inventory.md` — every model field classified (PII /
  Financial / Operational / Non-sensitive); every PII and Financial field has a named
  control; `idNumber` marked as special personal information with a stricter protection
  control than ordinary PII fields.
- G1 `docs/security/sessions.md` — JWT model for Flutter: algorithm (HS256 vs RS256),
  access token TTL, in-memory Flutter storage rationale, refresh token rotation policy,
  revocation strategy (Redis blacklist vs short TTL + rotation).
- G2 `docs/security/rate-limits.md` — four REST endpoint categories with a named
  Node.js rate-limiting middleware (`express-rate-limit` or equivalent): auth
  endpoints, OTP endpoints, read endpoints, write endpoints; scope (IP / user /
  phone), window, and limit for each.
- G3 `docs/security/upload-validation.md` — magic-byte check using the `file-type`
  npm package for REST multipart evidence uploads; AV scan decision documented;
  accepted MIME types and max file size derived from envelope.md; no payment card
  data stored locally (confirmed).
- G4 `docs/security/owasp.md` — all 10 OWASP Mobile Top 10 items addressed with
  Pass / Mitigate / Accept and a one-line note per item.
- G5 `docs/security/node-hardening.md` — `helmet.js` configuration; HTTPS
  enforcement; environment variable validation at startup (`zod` or `envalid`);
  secrets management (no secrets in code or committed files); CORS policy;
  `Content-Security-Policy` headers.
- G6 `docs/security.md` — top-level summary referencing all six sub-documents; the
  document that plan/07 in the parent scope links to.

## Expected Outcome

A single auditable security.md (plus six supporting documents) that any developer can
read to understand what data is protected, how, and why — before writing any code.
Every API contract and data model decision in sibling scopes can reference this
document for its security constraints. No security decision lives only in a working
document.

## Definition of Done

1. ✅ POPIA inventory complete: every field in every model classified; every PII/Financial
   field has a named control; `idNumber` marked as special personal information with a
   stricter control than ordinary PII fields.
2. ✅ JWT model decided: algorithm, TTL, Flutter in-memory storage confirmed, refresh token
   rotation policy, revocation strategy (Redis blacklist or short TTL).
3. ✅ Rate-limit table complete: four REST endpoint categories; each with a named Node.js
   middleware, scope, window, and limit.
4. ✅ File upload validation: `file-type` npm package specified for magic-byte check; REST
   multipart upload path covered; no payment card data stored locally (confirmed).
5. ✅ OWASP Mobile Top 10: all 10 items addressed with Pass / Mitigate / Accept.
6. ✅ Node.js production hardening: `helmet.js` configured; HTTPS enforced; env vars
   validated at startup; all items in the hardening checklist addressed.
7. ✅ `security.md` written and links to all six sub-documents.

## Sub-Scopes

(none)

## Plans

- ✅ [plans/00-popia-inventory.md](plans/00-popia-inventory.md) — POPIA field classification across all 12 models; idNumber as special personal information
- ✅ [plans/01-jwt-sessions.md](plans/01-jwt-sessions.md) — JWT security model for Flutter: algorithm, TTL, storage, rotation, revocation
- ⚠️ [plans/02-rate-limits.md](plans/02-rate-limits.md) — express-rate-limit for 4 REST endpoint categories; 429 shape; store decision
- ✅ [plans/03-upload-validation.md](plans/03-upload-validation.md) — file-type npm magic-byte check; accepted types; max size; AV scan decision
- ✅ [plans/04-owasp.md](plans/04-owasp.md) — OWASP Mobile Top 10 cross-check; all 10 items Pass/Mitigate/Accept
- ✅ [plans/05-node-hardening.md](plans/05-node-hardening.md) — helmet.js; HTTPS; zod/envalid startup validation; CORS; CSP
- ✅ [plans/06-summary.md](plans/06-summary.md) — docs/security.md top-level summary linking all 6 sub-documents
